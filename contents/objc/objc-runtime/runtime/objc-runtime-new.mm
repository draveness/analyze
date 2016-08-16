/*
 * Copyright (c) 2005-2009 Apple Inc.  All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/***********************************************************************
* objc-runtime-new.m
* Support for new-ABI classes and images.
**********************************************************************/

#if __OBJC2__

#include "objc-private.h"
#include "objc-runtime-new.h"
#include "objc-file.h"
#include "objc-cache.h"
#include <Block.h>
#include <objc/message.h>
#include <mach/shared_region.h>

#define newprotocol(p) ((protocol_t *)p)

static void disableTaggedPointers();
static void detach_class(Class cls, bool isMeta);
static void free_class(Class cls);
static Class setSuperclass(Class cls, Class newSuper);
static Class realizeClass(Class cls);
static method_t *getMethodNoSuper_nolock(Class cls, SEL sel);
static method_t *getMethod_nolock(Class cls, SEL sel);
static IMP addMethod(Class cls, SEL name, IMP imp, const char *types, bool replace);
static NXHashTable *realizedClasses(void);
static bool isRRSelector(SEL sel);
static bool isAWZSelector(SEL sel);
static bool methodListImplementsRR(const method_list_t *mlist);
static bool methodListImplementsAWZ(const method_list_t *mlist);
static void updateCustomRR_AWZ(Class cls, method_t *meth);
static method_t *search_method_list(const method_list_t *mlist, SEL sel);
static void flushCaches(Class cls);
#if SUPPORT_FIXUP
static void fixupMessageRef(message_ref_t *msg);
#endif

static bool MetaclassNSObjectAWZSwizzled;
static bool ClassNSObjectRRSwizzled;

#define SDK_FORMAT "%hu.%hhu.%hhu"
#define FORMAT_SDK(v) \
    (unsigned short)(((uint32_t)(v))>>16),  \
    (unsigned  char)(((uint32_t)(v))>>8),   \
    (unsigned  char)(((uint32_t)(v))>>0)


id objc_noop_imp(id self, SEL _cmd __unused) {
    return self;
}


/***********************************************************************
* Lock management
**********************************************************************/
rwlock_t runtimeLock;
rwlock_t selLock;
mutex_t cacheUpdateLock;
recursive_mutex_t loadMethodLock;

#if SUPPORT_QOS_HACK
pthread_priority_t BackgroundPriority = 0;
pthread_priority_t MainPriority = 0;
# if DEBUG
static __unused void destroyQOSKey(void *arg) {
    _objc_fatal("QoS override level at thread exit is %zu instead of zero", 
                (size_t)(uintptr_t)arg);
}
# endif
#endif

void lock_init(void)
{
#if SUPPORT_QOS_HACK
    BackgroundPriority = _pthread_qos_class_encode(QOS_CLASS_BACKGROUND, 0, 0);
    MainPriority = _pthread_qos_class_encode(qos_class_main(), 0, 0);
# if DEBUG
    pthread_key_init_np(QOS_KEY, &destroyQOSKey);
# endif
#endif
}


/***********************************************************************
* Non-pointer isa decoding
**********************************************************************/
#if SUPPORT_NONPOINTER_ISA

const uintptr_t objc_debug_isa_class_mask  = ISA_MASK;
const uintptr_t objc_debug_isa_magic_mask  = ISA_MAGIC_MASK;
const uintptr_t objc_debug_isa_magic_value = ISA_MAGIC_VALUE;

// die if masks overlap
STATIC_ASSERT((ISA_MASK & ISA_MAGIC_MASK) == 0);

// die if magic is wrong
STATIC_ASSERT((~ISA_MAGIC_MASK & ISA_MAGIC_VALUE) == 0);

// die if virtual address space bound goes up
STATIC_ASSERT((~ISA_MASK & MACH_VM_MAX_ADDRESS) == 0  ||  
              ISA_MASK + sizeof(void*) == MACH_VM_MAX_ADDRESS);

#else

// These variables exist but enforce pointer alignment only.
const uintptr_t objc_debug_isa_class_mask  = (~WORD_MASK);
const uintptr_t objc_debug_isa_magic_mask  = WORD_MASK;
const uintptr_t objc_debug_isa_magic_value = 0;

#endif


typedef locstamped_category_list_t category_list;


/*
  Low two bits of mlist->entsize is used as the fixed-up marker.
  PREOPTIMIZED VERSION:
    Method lists from shared cache are 1 (uniqued) or 3 (uniqued and sorted).
    (Protocol method lists are not sorted because of their extra parallel data)
    Runtime fixed-up method lists get 3.
  UN-PREOPTIMIZED VERSION:
    Method lists from shared cache are 1 (uniqued) or 3 (uniqued and sorted)
    Shared cache's sorting and uniquing are not trusted, but do affect the 
    location of the selector name string.
    Runtime fixed-up method lists get 2.

  High two bits of protocol->flags is used as the fixed-up marker.
  PREOPTIMIZED VERSION:
    Protocols from shared cache are 1<<30.
    Runtime fixed-up protocols get 1<<30.
  UN-PREOPTIMIZED VERSION:
  Protocols from shared cache are 1<<30.
    Shared cache's fixups are not trusted.
    Runtime fixed-up protocols get 3<<30.
*/

static uint32_t fixed_up_method_list = 3;
static uint32_t fixed_up_protocol = PROTOCOL_FIXED_UP_1;

void
disableSharedCacheOptimizations(void)
{
    fixed_up_method_list = 2;
    fixed_up_protocol = PROTOCOL_FIXED_UP_1 | PROTOCOL_FIXED_UP_2;
}

bool method_list_t::isFixedUp() const {
    return flags() == fixed_up_method_list;
}

void method_list_t::setFixedUp() {
    runtimeLock.assertWriting();
    assert(!isFixedUp());
    entsizeAndFlags = entsize() | fixed_up_method_list;
}

bool protocol_t::isFixedUp() const {
    return (flags & PROTOCOL_FIXED_UP_MASK) == fixed_up_protocol;
}

void protocol_t::setFixedUp() {
    runtimeLock.assertWriting();
    assert(!isFixedUp());
    flags = (flags & ~PROTOCOL_FIXED_UP_MASK) | fixed_up_protocol;
}


method_list_t **method_array_t::endCategoryMethodLists(Class cls) 
{
    method_list_t **mlists = beginLists();
    method_list_t **mlistsEnd = endLists();
    
    if (mlists == mlistsEnd  ||  !cls->data()->ro->baseMethods()) 
    {
        // No methods, or no base methods. 
        // Everything here is a category method.
        return mlistsEnd;
    }
    
    // Have base methods. Category methods are 
    // everything except the last method list.
    return mlistsEnd - 1;
}

static const char *sel_cname(SEL sel)
{
    return (const char *)(void *)sel;
}


static size_t protocol_list_size(const protocol_list_t *plist)
{
    return sizeof(protocol_list_t) + plist->count * sizeof(protocol_t *);
}


static void try_free(const void *p) 
{
    if (p && malloc_size(p)) free((void *)p);
}


static Class 
alloc_class_for_subclass(Class supercls, size_t extraBytes)
{
    if (!supercls  ||  !supercls->isSwift()) {
        return _calloc_class(sizeof(objc_class) + extraBytes);
    }

    // Superclass is a Swift class. New subclass must duplicate its extra bits.

    // Allocate the new class, with space for super's prefix and suffix
    // and self's extraBytes.
    swift_class_t *swiftSupercls = (swift_class_t *)supercls;
    size_t superSize = swiftSupercls->classSize;
    void *superBits = swiftSupercls->baseAddress();
    void *bits = malloc(superSize + extraBytes);

    // Copy all of the superclass's data to the new class.
    memcpy(bits, superBits, superSize);

    // Erase the objc data and the Swift description in the new class.
    swift_class_t *swcls = (swift_class_t *)
        ((uint8_t *)bits + swiftSupercls->classAddressOffset);
    bzero(swcls, sizeof(objc_class));
    swcls->description = nil;

    // Mark this class as Swift-enhanced.
    swcls->bits.setIsSwift();
    
    return (Class)swcls;
}


/***********************************************************************
* object_getIndexedIvars.
**********************************************************************/
void *object_getIndexedIvars(id obj)
{
    uint8_t *base = (uint8_t *)obj;

    if (!obj) return nil;
    if (obj->isTaggedPointer()) return nil;

    if (!obj->isClass()) return base + obj->ISA()->alignedInstanceSize();

    Class cls = (Class)obj;
    if (!cls->isSwift()) return base + sizeof(objc_class);
    
    swift_class_t *swcls = (swift_class_t *)cls;
    return base - swcls->classAddressOffset + word_align(swcls->classSize);
}


/***********************************************************************
* make_ro_writeable
* Reallocates rw->ro if necessary to make it writeable.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static class_ro_t *make_ro_writeable(class_rw_t *rw)
{
    runtimeLock.assertWriting();

    if (rw->flags & RW_COPIED_RO) {
        // already writeable, do nothing
    } else {
        class_ro_t *ro = (class_ro_t *)
            memdup(rw->ro, sizeof(*rw->ro));
        rw->ro = ro;
        rw->flags |= RW_COPIED_RO;
    }
    return (class_ro_t *)rw->ro;
}


/***********************************************************************
* unattachedCategories
* Returns the class => categories map of unattached categories.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static NXMapTable *unattachedCategories(void)
{
    runtimeLock.assertWriting();

    static NXMapTable *category_map = nil;

    if (category_map) return category_map;

    // fixme initial map size
    category_map = NXCreateMapTable(NXPtrValueMapPrototype, 16);

    return category_map;
}


/***********************************************************************
* addUnattachedCategoryForClass
* Records an unattached category.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void addUnattachedCategoryForClass(category_t *cat, Class cls, 
                                          header_info *catHeader)
{
    runtimeLock.assertWriting();

    // DO NOT use cat->cls! cls may be cat->cls->isa instead
    NXMapTable *cats = unattachedCategories();
    category_list *list;

    list = (category_list *)NXMapGet(cats, cls);
    if (!list) {
        list = (category_list *)
            calloc(sizeof(*list) + sizeof(list->list[0]), 1);
    } else {
        list = (category_list *)
            realloc(list, sizeof(*list) + sizeof(list->list[0]) * (list->count + 1));
    }
    list->list[list->count++] = (locstamped_category_t){cat, catHeader};
    NXMapInsert(cats, cls, list);
}


/***********************************************************************
* removeUnattachedCategoryForClass
* Removes an unattached category.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void removeUnattachedCategoryForClass(category_t *cat, Class cls)
{
    runtimeLock.assertWriting();

    // DO NOT use cat->cls! cls may be cat->cls->isa instead
    NXMapTable *cats = unattachedCategories();
    category_list *list;

    list = (category_list *)NXMapGet(cats, cls);
    if (!list) return;

    uint32_t i;
    for (i = 0; i < list->count; i++) {
        if (list->list[i].cat == cat) {
            // shift entries to preserve list order
            memmove(&list->list[i], &list->list[i+1], 
                    (list->count-i-1) * sizeof(list->list[i]));
            list->count--;
            return;
        }
    }
}


/***********************************************************************
* unattachedCategoriesForClass
* Returns the list of unattached categories for a class, and 
* deletes them from the list. 
* The result must be freed by the caller. 
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static category_list *
unattachedCategoriesForClass(Class cls, bool realizing)
{
    runtimeLock.assertWriting();
    return (category_list *)NXMapRemove(unattachedCategories(), cls);
}


/***********************************************************************
* removeAllUnattachedCategoriesForClass
* Deletes all unattached categories (loaded or not) for a class.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void removeAllUnattachedCategoriesForClass(Class cls)
{
    runtimeLock.assertWriting();

    void *list = NXMapRemove(unattachedCategories(), cls);
    if (list) free(list);
}


/***********************************************************************
* classNSObject
* Returns class NSObject.
* Locking: none
**********************************************************************/
static Class classNSObject(void)
{
    extern objc_class OBJC_CLASS_$_NSObject;
    return (Class)&OBJC_CLASS_$_NSObject;
}


/***********************************************************************
* printReplacements
* Implementation of PrintReplacedMethods / OBJC_PRINT_REPLACED_METHODS.
* Warn about methods from cats that override other methods in cats or cls.
* Assumes no methods from cats have been added to cls yet.
**********************************************************************/
static void printReplacements(Class cls, category_list *cats)
{
    uint32_t c;
    bool isMeta = cls->isMetaClass();

    if (!cats) return;

    // Newest categories are LAST in cats
    // Later categories override earlier ones.
    for (c = 0; c < cats->count; c++) {
        category_t *cat = cats->list[c].cat;

        method_list_t *mlist = cat->methodsForMeta(isMeta);
        if (!mlist) continue;

        for (const auto& meth : *mlist) {
            SEL s = sel_registerName(sel_cname(meth.name));

            // Don't warn about GC-ignored selectors
            if (ignoreSelector(s)) continue;

            // Search for replaced methods in method lookup order.
            // Complain about the first duplicate only.

            // Look for method in earlier categories
            for (uint32_t c2 = 0; c2 < c; c2++) {
                category_t *cat2 = cats->list[c2].cat;

                const method_list_t *mlist2 = cat2->methodsForMeta(isMeta);
                if (!mlist2) continue;

                for (const auto& meth2 : *mlist2) {
                    SEL s2 = sel_registerName(sel_cname(meth2.name));
                    if (s == s2) {
                        logReplacedMethod(cls->nameForLogging(), s, 
                                          cls->isMetaClass(), cat->name, 
                                          meth2.imp, meth.imp);
                        goto complained;
                    }
                }
            }

            // Look for method in cls
            for (const auto& meth2 : cls->data()->methods) {
                SEL s2 = sel_registerName(sel_cname(meth2.name));
                if (s == s2) {
                    logReplacedMethod(cls->nameForLogging(), s, 
                                      cls->isMetaClass(), cat->name, 
                                      meth2.imp, meth.imp);
                    goto complained;
                }
            }

        complained:
            ;
        }
    }
}


static bool isBundleClass(Class cls)
{
    return cls->data()->ro->flags & RO_FROM_BUNDLE;
}


static void 
fixupMethodList(method_list_t *mlist, bool bundleCopy, bool sort)
{
    runtimeLock.assertWriting();
    assert(!mlist->isFixedUp());

    // fixme lock less in attachMethodLists ?
    sel_lock();
    
    // Unique selectors in list.
    for (auto& meth : *mlist) {
        const char *name = sel_cname(meth.name);
        
        SEL sel = sel_registerNameNoLock(name, bundleCopy);
        meth.name = sel;
        
        if (ignoreSelector(sel)) {
            meth.imp = (IMP)&_objc_ignored_method;
        }
    }
    
    sel_unlock();

    // Sort by selector address.
    if (sort) {
        method_t::SortBySELAddress sorter;
        std::stable_sort(mlist->begin(), mlist->end(), sorter);
    }
    
    // Mark method list as uniqued and sorted
    mlist->setFixedUp();
}


static void 
prepareMethodLists(Class cls, method_list_t **addedLists, int addedCount, 
                   bool baseMethods, bool methodsFromBundle)
{
    runtimeLock.assertWriting();

    if (addedCount == 0) return;

    // Don't scan redundantly
    bool scanForCustomRR = !UseGC && !cls->hasCustomRR();
    bool scanForCustomAWZ = !UseGC && !cls->hasCustomAWZ();

    // There exist RR/AWZ special cases for some class's base methods. 
    // But this code should never need to scan base methods for RR/AWZ: 
    // default RR/AWZ cannot be set before setInitialized().
    // Therefore we need not handle any special cases here.
    if (baseMethods) {
        assert(!scanForCustomRR  &&  !scanForCustomAWZ);
    }

    // Add method lists to array.
    // Reallocate un-fixed method lists.
    // The new methods are PREPENDED to the method list array.

    for (int i = 0; i < addedCount; i++) {
        method_list_t *mlist = addedLists[i];
        assert(mlist);

        // Fixup selectors if necessary
        if (!mlist->isFixedUp()) {
            fixupMethodList(mlist, methodsFromBundle, true/*sort*/);
        }

        // Scan for method implementations tracked by the class's flags
        if (scanForCustomRR  &&  methodListImplementsRR(mlist)) {
            cls->setHasCustomRR();
            scanForCustomRR = false;
        }
        if (scanForCustomAWZ  &&  methodListImplementsAWZ(mlist)) {
            cls->setHasCustomAWZ();
            scanForCustomAWZ = false;
        }
    }
}


// Attach method lists and properties and protocols from categories to a class.
// Assumes the categories in cats are all loaded and sorted by load order, 
// oldest categories first.
static void 
attachCategories(Class cls, category_list *cats, bool flush_caches)
{
    if (!cats) return;
    if (PrintReplacedMethods) printReplacements(cls, cats);

    bool isMeta = cls->isMetaClass();

    // fixme rearrange to remove these intermediate allocations
    method_list_t **mlists = (method_list_t **)
        malloc(cats->count * sizeof(*mlists));
    property_list_t **proplists = (property_list_t **)
        malloc(cats->count * sizeof(*proplists));
    protocol_list_t **protolists = (protocol_list_t **)
        malloc(cats->count * sizeof(*protolists));

    // Count backwards through cats to get newest categories first
    int mcount = 0;
    int propcount = 0;
    int protocount = 0;
    int i = cats->count;
    bool fromBundle = NO;
    while (i--) {
        auto& entry = cats->list[i];

        method_list_t *mlist = entry.cat->methodsForMeta(isMeta);
        if (mlist) {
            mlists[mcount++] = mlist;
            fromBundle |= entry.hi->isBundle();
        }

        property_list_t *proplist = entry.cat->propertiesForMeta(isMeta);
        if (proplist) {
            proplists[propcount++] = proplist;
        }

        protocol_list_t *protolist = entry.cat->protocols;
        if (protolist) {
            protolists[protocount++] = protolist;
        }
    }

    auto rw = cls->data();

    prepareMethodLists(cls, mlists, mcount, NO, fromBundle);
    rw->methods.attachLists(mlists, mcount);
    free(mlists);
    if (flush_caches  &&  mcount > 0) flushCaches(cls);

    rw->properties.attachLists(proplists, propcount);
    free(proplists);

    rw->protocols.attachLists(protolists, protocount);
    free(protolists);
}


/***********************************************************************
* methodizeClass
* Fixes up cls's method list, protocol list, and property list.
* Attaches any outstanding categories.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void methodizeClass(Class cls)
{
    runtimeLock.assertWriting();

    bool isMeta = cls->isMetaClass();
    auto rw = cls->data();
    auto ro = rw->ro;

    // Methodizing for the first time
    if (PrintConnecting) {
        _objc_inform("CLASS: methodizing class '%s' %s", 
                     cls->nameForLogging(), isMeta ? "(meta)" : "");
    }

    // Install methods and properties that the class implements itself.
    method_list_t *list = ro->baseMethods();
    if (list) {
        prepareMethodLists(cls, &list, 1, YES, isBundleClass(cls));
        rw->methods.attachLists(&list, 1);
    }

    property_list_t *proplist = ro->baseProperties;
    if (proplist) {
        rw->properties.attachLists(&proplist, 1);
    }

    protocol_list_t *protolist = ro->baseProtocols;
    if (protolist) {
        rw->protocols.attachLists(&protolist, 1);
    }

    // Root classes get bonus method implementations if they don't have 
    // them already. These apply before category replacements.
    if (cls->isRootMetaclass()) {
        // root metaclass
        addMethod(cls, SEL_initialize, (IMP)&objc_noop_imp, "", NO);
    }

    // Attach categories.
    category_list *cats = unattachedCategoriesForClass(cls, true /*realizing*/);
    attachCategories(cls, cats, false /*don't flush caches*/);

    if (PrintConnecting) {
        if (cats) {
            for (uint32_t i = 0; i < cats->count; i++) {
                _objc_inform("CLASS: attached category %c%s(%s)", 
                             isMeta ? '+' : '-', 
                             cls->nameForLogging(), cats->list[i].cat->name);
            }
        }
    }
    
    if (cats) free(cats);

#if DEBUG
    // Debug: sanity-check all SELs; log method list contents
    for (const auto& meth : rw->methods) {
        if (PrintConnecting) {
            _objc_inform("METHOD %c[%s %s]", isMeta ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(meth.name));
        }
        assert(ignoreSelector(meth.name)  ||  
               sel_registerName(sel_getName(meth.name)) == meth.name); 
    }
#endif
}


/***********************************************************************
* remethodizeClass
* Attach outstanding categories to an existing class.
* Fixes up cls's method list, protocol list, and property list.
* Updates method caches for cls and its subclasses.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void remethodizeClass(Class cls)
{
    category_list *cats;
    bool isMeta;

    runtimeLock.assertWriting();

    isMeta = cls->isMetaClass();

    // Re-methodizing: check for more categories
    if ((cats = unattachedCategoriesForClass(cls, false/*not realizing*/))) {
        if (PrintConnecting) {
            _objc_inform("CLASS: attaching categories to class '%s' %s", 
                         cls->nameForLogging(), isMeta ? "(meta)" : "");
        }
        
        attachCategories(cls, cats, true /*flush caches*/);        
        free(cats);
    }
}


/***********************************************************************
* nonMetaClasses
* Returns the secondary metaclass => class map
* Used for some cases of +initialize and +resolveClassMethod:.
* This map does not contain all class and metaclass pairs. It only 
* contains metaclasses whose classes would be in the runtime-allocated 
* named-class table, but are not because some other class with the same name 
* is in that table.
* Classes with no duplicates are not included.
* Classes in the preoptimized named-class table are not included.
* Classes whose duplicates are in the preoptimized table are not included.
* Most code should use getNonMetaClass() instead of reading this table.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static NXMapTable *nonmeta_class_map = nil;
static NXMapTable *nonMetaClasses(void)
{
    runtimeLock.assertLocked();

    if (nonmeta_class_map) return nonmeta_class_map;

    // nonmeta_class_map is typically small
    INIT_ONCE_PTR(nonmeta_class_map, 
                  NXCreateMapTable(NXPtrValueMapPrototype, 32), 
                  NXFreeMapTable(v));

    return nonmeta_class_map;
}


/***********************************************************************
* addNonMetaClass
* Adds metacls => cls to the secondary metaclass map
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void addNonMetaClass(Class cls)
{
    runtimeLock.assertWriting();
    void *old;
    old = NXMapInsert(nonMetaClasses(), cls->ISA(), cls);

    assert(!cls->isMetaClass());
    assert(cls->ISA()->isMetaClass());
    assert(!old);
}


static void removeNonMetaClass(Class cls)
{
    runtimeLock.assertWriting();
    NXMapRemove(nonMetaClasses(), cls->ISA());
}


static bool scanMangledField(const char *&string, const char *end, 
                             const char *&field, int& length)
{
    // Leading zero not allowed.
    if (*string == '0') return false;

    length = 0;
    field = string;
    while (field < end) {
        char c = *field;
        if (!isdigit(c)) break;
        field++;
        if (__builtin_smul_overflow(length, 10, &length)) return false;
        if (__builtin_sadd_overflow(length, c - '0', &length)) return false;
    }

    string = field + length;
    return length > 0  &&  string <= end;
}


/***********************************************************************
* copySwiftV1DemangledName
* Returns the pretty form of the given Swift-v1-mangled class or protocol name. 
* Returns nil if the string doesn't look like a mangled Swift v1 name.
* The result must be freed with free().
**********************************************************************/
static char *copySwiftV1DemangledName(const char *string, bool isProtocol = false)
{
    if (!string) return nil;

    // Swift mangling prefix.
    if (strncmp(string, isProtocol ? "_TtP" : "_TtC", 4) != 0) return nil;
    string += 4;

    const char *end = string + strlen(string);

    // Module name.
    const char *prefix;
    int prefixLength;
    if (strncmp(string, "Ss", 2) == 0) {
        prefix = "Swift";
        prefixLength = 5;
        string += 2;
    } else {
        if (! scanMangledField(string, end, prefix, prefixLength)) return nil;
    }

    // Class or protocol name.
    const char *suffix;
    int suffixLength;
    if (! scanMangledField(string, end, suffix, suffixLength)) return nil;

    if (isProtocol) {
        // Remainder must be "_".
        if (strcmp(string, "_") != 0) return nil;
    } else {
        // Remainder must be empty.
        if (string != end) return nil;
    }

    char *result;
    asprintf(&result, "%.*s.%.*s", prefixLength,prefix, suffixLength,suffix);
    return result;
}


/***********************************************************************
* copySwiftV1MangledName
* Returns the Swift 1.0 mangled form of the given class or protocol name. 
* Returns nil if the string doesn't look like an unmangled Swift name.
* The result must be freed with free().
**********************************************************************/
static char *copySwiftV1MangledName(const char *string, bool isProtocol = false)
{
    if (!string) return nil;

    size_t dotCount = 0;
    size_t dotIndex;
    const char *s;
    for (s = string; *s; s++) {
        if (*s == '.') {
            dotCount++;
            dotIndex = s - string;
        }
    }
    size_t stringLength = s - string;

    if (dotCount != 1  ||  dotIndex == 0  ||  dotIndex >= stringLength-1) {
        return nil;
    }
    
    const char *prefix = string;
    size_t prefixLength = dotIndex;
    const char *suffix = string + dotIndex + 1;
    size_t suffixLength = stringLength - (dotIndex + 1);
    
    char *name;

    if (prefixLength == 5  &&  memcmp(prefix, "Swift", 5) == 0) {
        asprintf(&name, "_Tt%cSs%zu%.*s%s", 
                 isProtocol ? 'P' : 'C', 
                 suffixLength, (int)suffixLength, suffix, 
                 isProtocol ? "_" : "");
    } else {
        asprintf(&name, "_Tt%c%zu%.*s%zu%.*s%s", 
                 isProtocol ? 'P' : 'C', 
                 prefixLength, (int)prefixLength, prefix, 
                 suffixLength, (int)suffixLength, suffix, 
                 isProtocol ? "_" : "");
    }
    return name;
}


/***********************************************************************
* getClass
* Looks up a class by name. The class MIGHT NOT be realized.
* Demangled Swift names are recognized.
* Locking: runtimeLock must be read- or write-locked by the caller.
**********************************************************************/

// This is a misnomer: gdb_objc_realized_classes is actually a list of 
// named classes not in the dyld shared cache, whether realized or not.
NXMapTable *gdb_objc_realized_classes;  // exported for debuggers in objc-gdb.h

static Class getClass_impl(const char *name)
{
    runtimeLock.assertLocked();

    // allocated in _read_images
    assert(gdb_objc_realized_classes);

    // Try runtime-allocated table
    Class result = (Class)NXMapGet(gdb_objc_realized_classes, name);
    if (result) return result;

    // Try table from dyld shared cache
    return getPreoptimizedClass(name);
}

static Class getClass(const char *name)
{
    runtimeLock.assertLocked();

    // Try name as-is
    Class result = getClass_impl(name);
    if (result) return result;

    // Try Swift-mangled equivalent of the given name.
    if (char *swName = copySwiftV1MangledName(name)) {
        result = getClass_impl(swName);
        free(swName);
        return result;
    }

    return nil;
}


/***********************************************************************
* addNamedClass
* Adds name => cls to the named non-meta class map.
* Warns about duplicate class names and keeps the old mapping.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void addNamedClass(Class cls, const char *name, Class replacing = nil)
{
    runtimeLock.assertWriting();
    Class old;
    if ((old = getClass(name))  &&  old != replacing) {
        inform_duplicate(name, old, cls);

        // getNonMetaClass uses name lookups. Classes not found by name 
        // lookup must be in the secondary meta->nonmeta table.
        addNonMetaClass(cls);
    } else {
        NXMapInsert(gdb_objc_realized_classes, name, cls);
    }
    assert(!(cls->data()->flags & RO_META));

    // wrong: constructed classes are already realized when they get here
    // assert(!cls->isRealized());
}


/***********************************************************************
* removeNamedClass
* Removes cls from the name => cls map.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void removeNamedClass(Class cls, const char *name)
{
    runtimeLock.assertWriting();
    assert(!(cls->data()->flags & RO_META));
    if (cls == NXMapGet(gdb_objc_realized_classes, name)) {
        NXMapRemove(gdb_objc_realized_classes, name);
    } else {
        // cls has a name collision with another class - don't remove the other
        // but do remove cls from the secondary metaclass->class map.
        removeNonMetaClass(cls);
    }
}


/***********************************************************************
* realizedClasses
* Returns the class list for realized non-meta classes.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static NXHashTable *realized_class_hash = nil;

static NXHashTable *realizedClasses(void)
{
    runtimeLock.assertLocked();

    // allocated in _read_images
    assert(realized_class_hash);

    return realized_class_hash;
}


/***********************************************************************
* realizedMetaclasses
* Returns the class list for realized metaclasses.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static NXHashTable *realized_metaclass_hash = nil;
static NXHashTable *realizedMetaclasses(void)
{    
    runtimeLock.assertLocked();

    // allocated in _read_images
    assert(realized_metaclass_hash);

    return realized_metaclass_hash;
}


/***********************************************************************
* addRealizedClass
* Adds cls to the realized non-meta class hash.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void addRealizedClass(Class cls)
{
    runtimeLock.assertWriting();
    void *old;
    old = NXHashInsert(realizedClasses(), cls);
    objc_addRegisteredClass(cls);
    assert(!cls->isMetaClass());
    assert(!old);
}


/***********************************************************************
* removeRealizedClass
* Removes cls from the realized non-meta class hash.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void removeRealizedClass(Class cls)
{
    runtimeLock.assertWriting();
    if (cls->isRealized()) {
        assert(!cls->isMetaClass());
        NXHashRemove(realizedClasses(), cls);
        objc_removeRegisteredClass(cls);
    }
}


/***********************************************************************
* addRealizedMetaclass
* Adds cls to the realized metaclass hash.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void addRealizedMetaclass(Class cls)
{
    runtimeLock.assertWriting();
    void *old;
    old = NXHashInsert(realizedMetaclasses(), cls);
    assert(cls->isMetaClass());
    assert(!old);
}


/***********************************************************************
* removeRealizedMetaclass
* Removes cls from the realized metaclass hash.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void removeRealizedMetaclass(Class cls)
{
    runtimeLock.assertWriting();
    if (cls->isRealized()) {
        assert(cls->isMetaClass());
        NXHashRemove(realizedMetaclasses(), cls);
    }
}


/***********************************************************************
* futureNamedClasses
* Returns the classname => future class map for unrealized future classes.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static NXMapTable *future_named_class_map = nil;
static NXMapTable *futureNamedClasses()
{
    runtimeLock.assertWriting();
    
    if (future_named_class_map) return future_named_class_map;

    // future_named_class_map is big enough for CF's classes and a few others
    future_named_class_map = 
        NXCreateMapTable(NXStrValueMapPrototype, 32);

    return future_named_class_map;
}


/***********************************************************************
* addFutureNamedClass
* Installs cls as the class structure to use for the named class if it appears.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void addFutureNamedClass(const char *name, Class cls)
{
    void *old;

    runtimeLock.assertWriting();

    if (PrintFuture) {
        _objc_inform("FUTURE: reserving %p for %s", (void*)cls, name);
    }

    class_rw_t *rw = (class_rw_t *)calloc(sizeof(class_rw_t), 1);
    class_ro_t *ro = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
    ro->name = strdup(name);
    rw->ro = ro;
    cls->setData(rw);
    cls->data()->flags = RO_FUTURE;

    old = NXMapKeyCopyingInsert(futureNamedClasses(), name, cls);
    assert(!old);
}


/***********************************************************************
* popFutureNamedClass
* Removes the named class from the unrealized future class list, 
* because it has been realized.
* Returns nil if the name is not used by a future class.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static Class popFutureNamedClass(const char *name)
{
    runtimeLock.assertWriting();

    Class cls = nil;

    if (future_named_class_map) {
        cls = (Class)NXMapKeyFreeingRemove(future_named_class_map, name);
        if (cls && NXCountMapTable(future_named_class_map) == 0) {
            NXFreeMapTable(future_named_class_map);
            future_named_class_map = nil;
        }
    }

    return cls;
}


/***********************************************************************
* remappedClasses
* Returns the oldClass => newClass map for realized future classes.
* Returns the oldClass => nil map for ignored weak-linked classes.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static NXMapTable *remappedClasses(bool create)
{
    static NXMapTable *remapped_class_map = nil;

    runtimeLock.assertLocked();

    if (remapped_class_map) return remapped_class_map;
    if (!create) return nil;

    // remapped_class_map is big enough to hold CF's classes and a few others
    INIT_ONCE_PTR(remapped_class_map, 
                  NXCreateMapTable(NXPtrValueMapPrototype, 32), 
                  NXFreeMapTable(v));

    return remapped_class_map;
}


/***********************************************************************
* noClassesRemapped
* Returns YES if no classes have been remapped
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static bool noClassesRemapped(void)
{
    runtimeLock.assertLocked();

    bool result = (remappedClasses(NO) == nil);
#if DEBUG
    // Catch construction of an empty table, which defeats optimization.
    NXMapTable *map = remappedClasses(NO);
    if (map) assert(NXCountMapTable(map) > 0);
#endif
    return result;
}


/***********************************************************************
* addRemappedClass
* newcls is a realized future class, replacing oldcls.
* OR newcls is nil, replacing ignored weak-linked class oldcls.
* Locking: runtimeLock must be write-locked by the caller
**********************************************************************/
static void addRemappedClass(Class oldcls, Class newcls)
{
    runtimeLock.assertWriting();

    if (PrintFuture) {
        _objc_inform("FUTURE: using %p instead of %p for %s", 
                     (void*)newcls, (void*)oldcls, oldcls->nameForLogging());
    }

    void *old;
    old = NXMapInsert(remappedClasses(YES), oldcls, newcls);
    assert(!old);
}


/***********************************************************************
* remapClass
* Returns the live class pointer for cls, which may be pointing to 
* a class struct that has been reallocated.
* Returns nil if cls is ignored because of weak linking.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static Class remapClass(Class cls)
{
    runtimeLock.assertLocked();

    Class c2;

    if (!cls) return nil;

    NXMapTable *map = remappedClasses(NO);
    if (!map  ||  NXMapMember(map, cls, (void**)&c2) == NX_MAPNOTAKEY) {
        return cls;
    } else {
        return c2;
    }
}

static Class remapClass(classref_t cls)
{
    return remapClass((Class)cls);
}

Class _class_remap(Class cls)
{
    rwlock_reader_t lock(runtimeLock);
    return remapClass(cls);
}

/***********************************************************************
* remapClassRef
* Fix up a class ref, in case the class referenced has been reallocated 
* or is an ignored weak-linked class.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static void remapClassRef(Class *clsref)
{
    runtimeLock.assertLocked();

    Class newcls = remapClass(*clsref);    
    if (*clsref != newcls) *clsref = newcls;
}


/***********************************************************************
* getNonMetaClass
* Return the ordinary class for this class or metaclass. 
* `inst` is an instance of `cls` or a subclass thereof, or nil. 
* Non-nil inst is faster.
* Used by +initialize. 
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static Class getNonMetaClass(Class metacls, id inst)
{
    static int total, named, secondary, sharedcache;
    runtimeLock.assertLocked();

    realizeClass(metacls);

    total++;

    // return cls itself if it's already a non-meta class
    if (!metacls->isMetaClass()) return metacls;

    // metacls really is a metaclass

    // special case for root metaclass
    // where inst == inst->ISA() == metacls is possible
    if (metacls->ISA() == metacls) {
        Class cls = metacls->superclass;
        assert(cls->isRealized());
        assert(!cls->isMetaClass());
        assert(cls->ISA() == metacls);
        if (cls->ISA() == metacls) return cls;
    }

    // use inst if available
    if (inst) {
        Class cls = (Class)inst;
        realizeClass(cls);
        // cls may be a subclass - find the real class for metacls
        while (cls  &&  cls->ISA() != metacls) {
            cls = cls->superclass;
            realizeClass(cls);
        }
        if (cls) {
            assert(!cls->isMetaClass());
            assert(cls->ISA() == metacls);
            return cls;
        }
#if DEBUG
        _objc_fatal("cls is not an instance of metacls");
#else
        // release build: be forgiving and fall through to slow lookups
#endif
    }

    // try name lookup
    {
        Class cls = getClass(metacls->mangledName());
        if (cls->ISA() == metacls) {
            named++;
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: %d/%d (%g%%) "
                             "successful by-name metaclass lookups",
                             named, total, named*100.0/total);
            }

            realizeClass(cls);
            return cls;
        }
    }

    // try secondary table
    {
        Class cls = (Class)NXMapGet(nonMetaClasses(), metacls);
        if (cls) {
            secondary++;
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: %d/%d (%g%%) "
                             "successful secondary metaclass lookups",
                             secondary, total, secondary*100.0/total);
            }

            assert(cls->ISA() == metacls);            
            realizeClass(cls);
            return cls;
        }
    }

    // try any duplicates in the dyld shared cache
    {
        Class cls = nil;

        int count;
        Class *classes = copyPreoptimizedClasses(metacls->mangledName(),&count);
        if (classes) {
            for (int i = 0; i < count; i++) {
                if (classes[i]->ISA() == metacls) {
                    cls = classes[i];
                    break;
                }
            }
            free(classes);
        }

        if (cls) {
            sharedcache++;
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: %d/%d (%g%%) "
                             "successful shared cache metaclass lookups",
                             sharedcache, total, sharedcache*100.0/total);
            }

            realizeClass(cls);
            return cls;
        }
    }

    _objc_fatal("no class for metaclass %p", (void*)metacls);
}


/***********************************************************************
* _class_getNonMetaClass
* Return the ordinary class for this class or metaclass. 
* Used by +initialize. 
* Locking: acquires runtimeLock
**********************************************************************/
Class _class_getNonMetaClass(Class cls, id obj)
{
    rwlock_writer_t lock(runtimeLock);
    cls = getNonMetaClass(cls, obj);
    assert(cls->isRealized());
    return cls;
}


/***********************************************************************
* addSubclass
* Adds subcls as a subclass of supercls.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void addSubclass(Class supercls, Class subcls)
{
    runtimeLock.assertWriting();

    if (supercls  &&  subcls) {
        assert(supercls->isRealized());
        assert(subcls->isRealized());
        subcls->data()->nextSiblingClass = supercls->data()->firstSubclass;
        supercls->data()->firstSubclass = subcls;

        if (supercls->hasCxxCtor()) {
            subcls->setHasCxxCtor();
        }

        if (supercls->hasCxxDtor()) {
            subcls->setHasCxxDtor();
        }

        if (supercls->hasCustomRR()) {
            subcls->setHasCustomRR(true);
        }

        if (supercls->hasCustomAWZ()) {
            subcls->setHasCustomAWZ(true);
        }

        if (supercls->requiresRawIsa()) {
            subcls->setRequiresRawIsa(true);
        }
    }
}


/***********************************************************************
* removeSubclass
* Removes subcls as a subclass of supercls.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void removeSubclass(Class supercls, Class subcls)
{
    runtimeLock.assertWriting();
    assert(supercls->isRealized());
    assert(subcls->isRealized());
    assert(subcls->superclass == supercls);

    Class *cp;
    for (cp = &supercls->data()->firstSubclass; 
         *cp  &&  *cp != subcls; 
         cp = &(*cp)->data()->nextSiblingClass)
        ;
    assert(*cp == subcls);
    *cp = subcls->data()->nextSiblingClass;
}



/***********************************************************************
* protocols
* Returns the protocol name => protocol map for protocols.
* Locking: runtimeLock must read- or write-locked by the caller
**********************************************************************/
static NXMapTable *protocols(void)
{
    static NXMapTable *protocol_map = nil;
    
    runtimeLock.assertLocked();

    INIT_ONCE_PTR(protocol_map, 
                  NXCreateMapTable(NXStrValueMapPrototype, 16), 
                  NXFreeMapTable(v) );

    return protocol_map;
}


/***********************************************************************
* getProtocol
* Looks up a protocol by name. Demangled Swift names are recognized.
* Locking: runtimeLock must be read- or write-locked by the caller.
**********************************************************************/
static Protocol *getProtocol(const char *name)
{
    runtimeLock.assertLocked();

    // Try name as-is.
    Protocol *result = (Protocol *)NXMapGet(protocols(), name);
    if (result) return result;

    // Try Swift-mangled equivalent of the given name.
    if (char *swName = copySwiftV1MangledName(name, true/*isProtocol*/)) {
        result = (Protocol *)NXMapGet(protocols(), swName);
        free(swName);
        return result;
    }

    return nil;
}


/***********************************************************************
* remapProtocol
* Returns the live protocol pointer for proto, which may be pointing to 
* a protocol struct that has been reallocated.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static protocol_t *remapProtocol(protocol_ref_t proto)
{
    runtimeLock.assertLocked();

    protocol_t *newproto = (protocol_t *)
        getProtocol(((protocol_t *)proto)->mangledName);
    return newproto ? newproto : (protocol_t *)proto;
}


/***********************************************************************
* remapProtocolRef
* Fix up a protocol ref, in case the protocol referenced has been reallocated.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static size_t UnfixedProtocolReferences;
static void remapProtocolRef(protocol_t **protoref)
{
    runtimeLock.assertLocked();

    protocol_t *newproto = remapProtocol((protocol_ref_t)*protoref);
    if (*protoref != newproto) {
        *protoref = newproto;
        UnfixedProtocolReferences++;
    }
}


/***********************************************************************
* moveIvars
* Slides a class's ivars to accommodate the given superclass size.
* Also slides ivar and weak GC layouts if provided.
* Ivars are NOT compacted to compensate for a superclass that shrunk.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void moveIvars(class_ro_t *ro, uint32_t superSize, 
                      layout_bitmap *ivarBitmap, layout_bitmap *weakBitmap)
{
    runtimeLock.assertWriting();

    uint32_t diff;

    assert(superSize > ro->instanceStart);
    diff = superSize - ro->instanceStart;

    if (ro->ivars) {
        // Find maximum alignment in this class's ivars
        uint32_t maxAlignment = 1;
        for (const auto& ivar : *ro->ivars) {
            if (!ivar.offset) continue;  // anonymous bitfield

            uint32_t alignment = ivar.alignment();
            if (alignment > maxAlignment) maxAlignment = alignment;
        }

        // Compute a slide value that preserves that alignment
        uint32_t alignMask = maxAlignment - 1;
        if (diff & alignMask) diff = (diff + alignMask) & ~alignMask;

        // Slide all of this class's ivars en masse
        for (const auto& ivar : *ro->ivars) {
            if (!ivar.offset) continue;  // anonymous bitfield

            uint32_t oldOffset = (uint32_t)*ivar.offset;
            uint32_t newOffset = oldOffset + diff;
            *ivar.offset = newOffset;

            if (PrintIvars) {
                _objc_inform("IVARS:    offset %u -> %u for %s "
                             "(size %u, align %u)", 
                             oldOffset, newOffset, ivar.name, 
                             ivar.size, ivar.alignment());
            }
        }

        // Slide GC layouts
        uint32_t oldOffset = ro->instanceStart;
        uint32_t newOffset = ro->instanceStart + diff;

        if (ivarBitmap) {
            layout_bitmap_slide(ivarBitmap, 
                                oldOffset >> WORD_SHIFT, 
                                newOffset >> WORD_SHIFT);
        }
        if (weakBitmap) {
            layout_bitmap_slide(weakBitmap, 
                                oldOffset >> WORD_SHIFT, 
                                newOffset >> WORD_SHIFT);
        }
    }

    *(uint32_t *)&ro->instanceStart += diff;
    *(uint32_t *)&ro->instanceSize += diff;

    if (!ro->ivars) {
        // No ivars slid, but superclass changed size. 
        // Expand bitmap in preparation for layout_bitmap_splat().
        if (ivarBitmap) layout_bitmap_grow(ivarBitmap, ro->instanceSize >> WORD_SHIFT);
        if (weakBitmap) layout_bitmap_grow(weakBitmap, ro->instanceSize >> WORD_SHIFT);
    }
}


/***********************************************************************
* getIvar
* Look up an ivar by name.
* Locking: runtimeLock must be read- or write-locked by the caller.
**********************************************************************/
static ivar_t *getIvar(Class cls, const char *name)
{
    runtimeLock.assertLocked();

    const ivar_list_t *ivars;
    assert(cls->isRealized());
    if ((ivars = cls->data()->ro->ivars)) {
        for (auto& ivar : *ivars) {
            if (!ivar.offset) continue;  // anonymous bitfield

            // ivar.name may be nil for anonymous bitfields etc.
            if (ivar.name  &&  0 == strcmp(name, ivar.name)) {
                return &ivar;
            }
        }
    }

    return nil;
}


static void reconcileInstanceVariables(Class cls, Class supercls, const class_ro_t*& ro) 
{
    class_rw_t *rw = cls->data();

    assert(supercls);
    assert(!cls->isMetaClass());

    /* debug: print them all before sliding
    if (ro->ivars) {
        for (const auto& ivar : *ro->ivars) {
            if (!ivar.offset) continue;  // anonymous bitfield

            _objc_inform("IVARS: %s.%s (offset %u, size %u, align %u)", 
                         ro->name, ivar.name, 
                         *ivar.offset, ivar.size, ivar.alignment());
        }
    }
    */

    // Non-fragile ivars - reconcile this class with its superclass
    layout_bitmap ivarBitmap;
    layout_bitmap weakBitmap;
    bool layoutsChanged = NO;
    bool mergeLayouts = UseGC;
    const class_ro_t *super_ro = supercls->data()->ro;
    
    if (DebugNonFragileIvars) {
        // Debugging: Force non-fragile ivars to slide.
        // Intended to find compiler, runtime, and program bugs.
        // If it fails with this and works without, you have a problem.
        
        // Operation: Reset everything to 0 + misalignment. 
        // Then force the normal sliding logic to push everything back.
        
        // Exceptions: root classes, metaclasses, *NSCF* classes, 
        // __CF* classes, NSConstantString, NSSimpleCString
        
        // (already know it's not root because supercls != nil)
        const char *clsname = cls->mangledName();
        if (!strstr(clsname, "NSCF")  &&  
            0 != strncmp(clsname, "__CF", 4)  &&  
            0 != strcmp(clsname, "NSConstantString")  &&  
            0 != strcmp(clsname, "NSSimpleCString")) 
        {
            uint32_t oldStart = ro->instanceStart;
            uint32_t oldSize = ro->instanceSize;
            class_ro_t *ro_w = make_ro_writeable(rw);
            ro = rw->ro;
            
            // Find max ivar alignment in class.
            // default to word size to simplify ivar update
            uint32_t alignment = 1<<WORD_SHIFT;
            if (ro->ivars) {
                for (const auto& ivar : *ro->ivars) {
                    if (ivar.alignment() > alignment) {
                        alignment = ivar.alignment();
                    }
                }
            }
            uint32_t misalignment = ro->instanceStart % alignment;
            uint32_t delta = ro->instanceStart - misalignment;
            ro_w->instanceStart = misalignment;
            ro_w->instanceSize -= delta;
            
            if (PrintIvars) {
                _objc_inform("IVARS: DEBUG: forcing ivars for class '%s' "
                             "to slide (instanceStart %zu -> %zu)", 
                             cls->nameForLogging(), (size_t)oldStart, 
                             (size_t)ro->instanceStart);
            }
            
            if (ro->ivars) {
                for (const auto& ivar : *ro->ivars) {
                    if (!ivar.offset) continue;  // anonymous bitfield
                    *ivar.offset -= delta;
                }
            }
            
            if (mergeLayouts) {
                layout_bitmap layout;
                if (ro->ivarLayout) {
                    layout = layout_bitmap_create(ro->ivarLayout, 
                                                  oldSize, oldSize, NO);
                    layout_bitmap_slide_anywhere(&layout, 
                                                 delta >> WORD_SHIFT, 0);
                    ro_w->ivarLayout = layout_string_create(layout);
                    layout_bitmap_free(layout);
                }
                if (ro->weakIvarLayout) {
                    layout = layout_bitmap_create(ro->weakIvarLayout, 
                                                  oldSize, oldSize, YES);
                    layout_bitmap_slide_anywhere(&layout, 
                                                 delta >> WORD_SHIFT, 0);
                    ro_w->weakIvarLayout = layout_string_create(layout);
                    layout_bitmap_free(layout);
                }
            }
        }
    }

    if (ro->instanceStart >= super_ro->instanceSize  &&  !mergeLayouts) {
        // Superclass has not overgrown its space, and we don't 
        // need to rebuild GC layouts. We're done here.
        return;
    }
    // fixme can optimize for "class has no new ivars", etc

    if (mergeLayouts) {
        // WARNING: gcc c++ sets instanceStart/Size=0 for classes with  
        //   no local ivars, but does provide a layout bitmap. 
        //   Handle that case specially so layout_bitmap_create doesn't die
        //   The other ivar sliding code below still works fine, and 
        //   the final result is a good class.
        if (ro->instanceStart == 0  &&  ro->instanceSize == 0) {
            // We can't use ro->ivarLayout because we don't know
            // how long it is. Force a new layout to be created.
            if (PrintIvars) {
                _objc_inform("IVARS: instanceStart/Size==0 for class %s; "
                             "disregarding ivar layout", cls->nameForLogging());
            }
            ivarBitmap = layout_bitmap_create_empty(super_ro->instanceSize, NO);
            weakBitmap = layout_bitmap_create_empty(super_ro->instanceSize, YES);
            layoutsChanged = YES;
        } 
        else {
            ivarBitmap = 
                layout_bitmap_create(ro->ivarLayout, 
                                     ro->instanceSize, 
                                     ro->instanceSize, NO);
            weakBitmap = 
                layout_bitmap_create(ro->weakIvarLayout, 
                                     ro->instanceSize,
                                     ro->instanceSize, YES);
        }
    }

    if (ro->instanceStart < super_ro->instanceSize) {
        // Superclass has changed size. This class's ivars must move.
        // Also slide layout bits in parallel.
        // This code is incapable of compacting the subclass to 
        //   compensate for a superclass that shrunk, so don't do that.
        if (PrintIvars) {
            _objc_inform("IVARS: sliding ivars for class %s "
                         "(superclass was %u bytes, now %u)", 
                         cls->nameForLogging(), ro->instanceStart, 
                         super_ro->instanceSize);
        }
        class_ro_t *ro_w = make_ro_writeable(rw);
        ro = rw->ro;
        moveIvars(ro_w, super_ro->instanceSize, 
                  mergeLayouts ? &ivarBitmap : nil, 
                  mergeLayouts ? &weakBitmap : nil);
        gdb_objc_class_changed(cls, OBJC_CLASS_IVARS_CHANGED, ro->name);
        layoutsChanged = YES;
    } 
    
    if (mergeLayouts) {
        // Check superclass's layout against this class's layout.
        // This needs to be done even if the superclass is not bigger.
        layout_bitmap superBitmap;
        
        superBitmap = layout_bitmap_create(super_ro->ivarLayout, 
                                           super_ro->instanceSize, 
                                           super_ro->instanceSize, NO);
        layoutsChanged |= layout_bitmap_splat(ivarBitmap, superBitmap, 
                                              ro->instanceStart);
        layout_bitmap_free(superBitmap);
        
        // check the superclass' weak layout.
        superBitmap = layout_bitmap_create(super_ro->weakIvarLayout, 
                                           super_ro->instanceSize, 
                                           super_ro->instanceSize, YES);
        layoutsChanged |= layout_bitmap_splat(weakBitmap, superBitmap, 
                                              ro->instanceStart);
        layout_bitmap_free(superBitmap);
        
        // Rebuild layout strings if necessary.
        if (layoutsChanged) {
            if (PrintIvars) {
                _objc_inform("IVARS: gc layout changed for class %s", 
                             cls->nameForLogging());
            }
            class_ro_t *ro_w = make_ro_writeable(rw);
            ro = rw->ro;
            if (DebugNonFragileIvars) {
                try_free(ro_w->ivarLayout);
                try_free(ro_w->weakIvarLayout);
            }
            ro_w->ivarLayout = layout_string_create(ivarBitmap);
            ro_w->weakIvarLayout = layout_string_create(weakBitmap);
        }
        
        layout_bitmap_free(ivarBitmap);
        layout_bitmap_free(weakBitmap);
    }
}


/***********************************************************************
* realizeClass
* Performs first-time initialization on class cls, 
* including allocating its read-write data.
* Returns the real class structure for the class. 
* Locking: runtimeLock must be write-locked by the caller
**********************************************************************/
static Class realizeClass(Class cls)
{
    runtimeLock.assertWriting();

    const class_ro_t *ro;
    class_rw_t *rw;
    Class supercls;
    Class metacls;
    bool isMeta;

    if (!cls) return nil;
    if (cls->isRealized()) return cls;
    assert(cls == remapClass(cls));

    // fixme verify class is not in an un-dlopened part of the shared cache?

    ro = (const class_ro_t *)cls->data();
    if (ro->flags & RO_FUTURE) {
        // This was a future class. rw data is already allocated.
        rw = cls->data();
        ro = cls->data()->ro;
        cls->changeInfo(RW_REALIZED|RW_REALIZING, RW_FUTURE);
    } else {
        // Normal class. Allocate writeable class data.
        rw = (class_rw_t *)calloc(sizeof(class_rw_t), 1);
        rw->ro = ro;
        rw->flags = RW_REALIZED|RW_REALIZING;
        cls->setData(rw);
    }

    isMeta = ro->flags & RO_META;

    rw->version = isMeta ? 7 : 0;  // old runtime went up to 6

    if (PrintConnecting) {
        _objc_inform("CLASS: realizing class '%s' %s %p %p", 
                     cls->nameForLogging(), isMeta ? "(meta)" : "", 
                     (void*)cls, ro);
    }

    // Realize superclass and metaclass, if they aren't already.
    // This needs to be done after RW_REALIZED is set above, for root classes.
    supercls = realizeClass(remapClass(cls->superclass));
    metacls = realizeClass(remapClass(cls->ISA()));

    // Update superclass and metaclass in case of remapping
    cls->superclass = supercls;
    cls->initClassIsa(metacls);

    // Reconcile instance variable offsets / layout.
    // This may reallocate class_ro_t, updating our ro variable.
    if (supercls  &&  !isMeta) reconcileInstanceVariables(cls, supercls, ro);

    // Set fastInstanceSize if it wasn't set already.
    cls->setInstanceSize(ro->instanceSize);

    // Copy some flags from ro to rw
    if (ro->flags & RO_HAS_CXX_STRUCTORS) {
        cls->setHasCxxDtor();
        if (! (ro->flags & RO_HAS_CXX_DTOR_ONLY)) {
            cls->setHasCxxCtor();
        }
    }

    // Disable non-pointer isa for some classes and/or platforms.
#if SUPPORT_NONPOINTER_ISA
    {
        bool disable = false;
        static bool hackedDispatch = false;
        
        if (DisableIndexedIsa) {
            // Non-pointer isa disabled by environment or GC or app SDK version
            disable = true;
        }
        else if (!hackedDispatch  &&  !(ro->flags & RO_META)  &&  
                 0 == strcmp(ro->name, "OS_object")) 
        {
            // hack for libdispatch et al - isa also acts as vtable pointer
            hackedDispatch = true;
            disable = true;
        }
        
        if (disable) {
            cls->setRequiresRawIsa(false/*inherited*/);
        }
    }
#endif

    // Connect this class to its superclass's subclass lists
    if (supercls) {
        addSubclass(supercls, cls);
    }

    // Attach categories
    methodizeClass(cls);

    if (!isMeta) {
        addRealizedClass(cls);
    } else {
        addRealizedMetaclass(cls);
    }

    return cls;
}


/***********************************************************************
* missingWeakSuperclass
* Return YES if some superclass of cls was weak-linked and is missing.
**********************************************************************/
static bool 
missingWeakSuperclass(Class cls)
{
    assert(!cls->isRealized());

    if (!cls->superclass) {
        // superclass nil. This is normal for root classes only.
        return (!(cls->data()->flags & RO_ROOT));
    } else {
        // superclass not nil. Check if a higher superclass is missing.
        Class supercls = remapClass(cls->superclass);
        assert(cls != cls->superclass);
        assert(cls != supercls);
        if (!supercls) return YES;
        if (supercls->isRealized()) return NO;
        return missingWeakSuperclass(supercls);
    }
}


/***********************************************************************
* realizeAllClassesInImage
* Non-lazily realizes all unrealized classes in the given image.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void realizeAllClassesInImage(header_info *hi)
{
    runtimeLock.assertWriting();

    size_t count, i;
    classref_t *classlist;

    if (hi->allClassesRealized) return;

    classlist = _getObjc2ClassList(hi, &count);

    for (i = 0; i < count; i++) {
        realizeClass(remapClass(classlist[i]));
    }

    hi->allClassesRealized = YES;
}


/***********************************************************************
* realizeAllClasses
* Non-lazily realizes all unrealized classes in all known images.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void realizeAllClasses(void)
{
    runtimeLock.assertWriting();

    header_info *hi;
    for (hi = FirstHeader; hi; hi = hi->next) {
        realizeAllClassesInImage(hi);
    }
}


/***********************************************************************
* _objc_allocateFutureClass
* Allocate an unresolved future class for the given class name.
* Returns any existing allocation if one was already made.
* Assumes the named class doesn't exist yet.
* Locking: acquires runtimeLock
**********************************************************************/
Class _objc_allocateFutureClass(const char *name)
{
    rwlock_writer_t lock(runtimeLock);

    Class cls;
    NXMapTable *map = futureNamedClasses();

    if ((cls = (Class)NXMapGet(map, name))) {
        // Already have a future class for this name.
        return cls;
    }

    cls = _calloc_class(sizeof(objc_class));
    addFutureNamedClass(name, cls);

    return cls;
}


/***********************************************************************
* objc_getFutureClass.  Return the id of the named class.
* If the class does not exist, return an uninitialized class 
* structure that will be used for the class when and if it 
* does get loaded.
* Not thread safe. 
**********************************************************************/
Class objc_getFutureClass(const char *name)
{
    Class cls;

    // YES unconnected, NO class handler
    // (unconnected is OK because it will someday be the real class)
    cls = look_up_class(name, YES, NO);
    if (cls) {
        if (PrintFuture) {
            _objc_inform("FUTURE: found %p already in use for %s", 
                         (void*)cls, name);
        }

        return cls;
    }
    
    // No class or future class with that name yet. Make one.
    // fixme not thread-safe with respect to 
    // simultaneous library load or getFutureClass.
    return _objc_allocateFutureClass(name);
}


BOOL _class_isFutureClass(Class cls)
{
    return cls  &&  cls->isFuture();
}


/***********************************************************************
* _objc_flush_caches
* Flushes all caches.
* (Historical behavior: flush caches for cls, its metaclass, 
* and subclasses thereof. Nil flushes all classes.)
* Locking: acquires runtimeLock
**********************************************************************/
static void flushCaches(Class cls)
{
    runtimeLock.assertWriting();

    mutex_locker_t lock(cacheUpdateLock);

    if (cls) {
        foreach_realized_class_and_subclass(cls, ^(Class c){
            cache_erase_nolock(c);
        });

        if (!cls->superclass) {
            // root; metaclasses are subclasses and were flushed above
        } else {
            foreach_realized_class_and_subclass(cls->ISA(), ^(Class c){
                cache_erase_nolock(c);
            });
        }
    }
    else {
        Class c;
        NXHashTable *classes = realizedClasses();
        NXHashState state = NXInitHashState(classes);
        while (NXNextHashState(classes, &state, (void **)&c)) {
            cache_erase_nolock(c);
        }
        classes = realizedMetaclasses();
        state = NXInitHashState(classes);
        while (NXNextHashState(classes, &state, (void **)&c)) {
            cache_erase_nolock(c);
        }
    }
}


void _objc_flush_caches(Class cls)
{
    {
        rwlock_writer_t lock(runtimeLock);
        flushCaches(cls);
    }

    if (!cls) {
        mutex_locker_t lock(cacheUpdateLock);
        // collectALot if cls==nil
        cache_collect(true);
    }
}


/***********************************************************************
* map_images
* Process the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
*
* Locking: write-locks runtimeLock
**********************************************************************/
const char *
map_2_images(enum dyld_image_states state, uint32_t infoCount,
             const struct dyld_image_info infoList[])
{
    rwlock_writer_t lock(runtimeLock);
    return map_images_nolock(state, infoCount, infoList);
}


/***********************************************************************
* load_images
* Process +load in the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
*
* Locking: write-locks runtimeLock and loadMethodLock
**********************************************************************/
const char *
load_images(enum dyld_image_states state, uint32_t infoCount,
            const struct dyld_image_info infoList[])
{
    bool found;

    // Return without taking locks if there are no +load methods here.
    found = false;
    for (uint32_t i = 0; i < infoCount; i++) {
        if (hasLoadMethods((const headerType *)infoList[i].imageLoadAddress)) {
            found = true;
            break;
        }
    }
    if (!found) return nil;

    recursive_mutex_locker_t lock(loadMethodLock);

    // Discover load methods
    {
        rwlock_writer_t lock2(runtimeLock);
        found = load_images_nolock(state, infoCount, infoList);
    }

    // Call +load methods (without runtimeLock - re-entrant)
    if (found) {
        call_load_methods();
    }

    return nil;
}


/***********************************************************************
* unmap_image
* Process the given image which is about to be unmapped by dyld.
* mh is mach_header instead of headerType because that's what 
*   dyld_priv.h says even for 64-bit.
*
* Locking: write-locks runtimeLock and loadMethodLock
**********************************************************************/
void 
unmap_image(const struct mach_header *mh, intptr_t vmaddr_slide)
{
    recursive_mutex_locker_t lock(loadMethodLock);
    rwlock_writer_t lock2(runtimeLock);
    unmap_image_nolock(mh);
}




/***********************************************************************
* readClass
* Read a class and metaclass as written by a compiler.
* Returns the new class pointer. This could be: 
* - cls
* - nil  (cls has a missing weak-linked superclass)
* - something else (space for this class was reserved by a future class)
*
* Locking: runtimeLock acquired by map_images or objc_readClassPair
**********************************************************************/
Class readClass(Class cls, bool headerIsBundle, bool headerIsPreoptimized)
{
    const char *mangledName = cls->mangledName();
    
    if (missingWeakSuperclass(cls)) {
        // No superclass (probably weak-linked). 
        // Disavow any knowledge of this subclass.
        if (PrintConnecting) {
            _objc_inform("CLASS: IGNORING class '%s' with "
                         "missing weak-linked superclass", 
                         cls->nameForLogging());
        }
        addRemappedClass(cls, nil);
        cls->superclass = nil;
        return nil;
    }
    
    // Note: Class __ARCLite__'s hack does not go through here. 
    // Class structure fixups that apply to it also need to be 
    // performed in non-lazy realization below.
    
    // These fields should be set to zero because of the 
    // binding of _objc_empty_vtable, but OS X 10.8's dyld 
    // does not bind shared cache absolute symbols as expected.
    // This (and the __ARCLite__ hack below) can be removed 
    // once the simulator drops 10.8 support.
#if TARGET_IPHONE_SIMULATOR
    if (cls->cache._mask) cls->cache._mask = 0;
    if (cls->cache._occupied) cls->cache._occupied = 0;
    if (cls->ISA()->cache._mask) cls->ISA()->cache._mask = 0;
    if (cls->ISA()->cache._occupied) cls->ISA()->cache._occupied = 0;
#endif

    Class replacing = nil;
    if (Class newCls = popFutureNamedClass(mangledName)) {
        // This name was previously allocated as a future class.
        // Copy objc_class to future class's struct.
        // Preserve future's rw data block.
        
        if (newCls->isSwift()) {
            _objc_fatal("Can't complete future class request for '%s' "
                        "because the real class is too big.", 
                        cls->nameForLogging());
        }
        
        class_rw_t *rw = newCls->data();
        const class_ro_t *old_ro = rw->ro;
        memcpy(newCls, cls, sizeof(objc_class));
        rw->ro = (class_ro_t *)newCls->data();
        newCls->setData(rw);
        free((void *)old_ro->name);
        free((void *)old_ro);
        
        addRemappedClass(cls, newCls);
        
        replacing = cls;
        cls = newCls;
    }
    
    if (headerIsPreoptimized  &&  !replacing) {
        // class list built in shared cache
        // fixme strict assert doesn't work because of duplicates
        // assert(cls == getClass(name));
        assert(getClass(mangledName));
    } else {
        addNamedClass(cls, mangledName, replacing);
    }
    
    // for future reference: shared cache never contains MH_BUNDLEs
    if (headerIsBundle) {
        cls->data()->flags |= RO_FROM_BUNDLE;
        cls->ISA()->data()->flags |= RO_FROM_BUNDLE;
    }
    
    return cls;
}


/***********************************************************************
* readProtocol
* Read a protocol as written by a compiler.
**********************************************************************/
static void
readProtocol(protocol_t *newproto, Class protocol_class,
             NXMapTable *protocol_map, 
             bool headerIsPreoptimized, bool headerIsBundle)
{
    // This is not enough to make protocols in unloaded bundles safe, 
    // but it does prevent crashes when looking up unrelated protocols.
    auto insertFn = headerIsBundle ? NXMapKeyCopyingInsert : NXMapInsert;

    protocol_t *oldproto = (protocol_t *)getProtocol(newproto->mangledName);

    if (oldproto) {
        // Some other definition already won.
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s  "
                         "(duplicate of %p)",
                         newproto, oldproto->nameForLogging(), oldproto);
        }
    }
    else if (headerIsPreoptimized) {
        // Shared cache initialized the protocol object itself, 
        // but in order to allow out-of-cache replacement we need 
        // to add it to the protocol table now.

        protocol_t *cacheproto = (protocol_t *)
            getPreoptimizedProtocol(newproto->mangledName);
        protocol_t *installedproto;
        if (cacheproto  &&  cacheproto != newproto) {
            // Another definition in the shared cache wins (because 
            // everything in the cache was fixed up to point to it).
            installedproto = cacheproto;
        }
        else {
            // This definition wins.
            installedproto = newproto;
        }
        
        assert(installedproto->getIsa() == protocol_class);
        assert(installedproto->size >= sizeof(protocol_t));
        insertFn(protocol_map, installedproto->mangledName, 
                 installedproto);
        
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s", 
                         installedproto, installedproto->nameForLogging());
            if (newproto != installedproto) {
                _objc_inform("PROTOCOLS: protocol at %p is %s  "
                             "(duplicate of %p)", 
                             newproto, installedproto->nameForLogging(), 
                             installedproto);
            }
        }
    }
    else if (newproto->size >= sizeof(protocol_t)) {
        // New protocol from an un-preoptimized image
        // with sufficient storage. Fix it up in place.
        // fixme duplicate protocols from unloadable bundle
        newproto->initIsa(protocol_class);  // fixme pinned
        insertFn(protocol_map, newproto->mangledName, newproto);
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s",
                         newproto, newproto->nameForLogging());
        }
    }
    else {
        // New protocol from an un-preoptimized image 
        // with insufficient storage. Reallocate it.
        // fixme duplicate protocols from unloadable bundle
        size_t size = max(sizeof(protocol_t), (size_t)newproto->size);
        protocol_t *installedproto = (protocol_t *)calloc(size, 1);
        memcpy(installedproto, newproto, newproto->size);
        installedproto->size = (__typeof__(installedproto->size))size;
        
        installedproto->initIsa(protocol_class);  // fixme pinned
        insertFn(protocol_map, installedproto->mangledName, installedproto);
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s  ", 
                         installedproto, installedproto->nameForLogging());
            _objc_inform("PROTOCOLS: protocol at %p is %s  "
                         "(reallocated to %p)", 
                         newproto, installedproto->nameForLogging(), 
                         installedproto);
        }
    }
}

/***********************************************************************
* _read_images
* Perform initial processing of the headers in the linked 
* list beginning with headerList. 
*
* Called by: map_images_nolock
*
* Locking: runtimeLock acquired by map_images
**********************************************************************/

extern "C" int dyld_get_program_sdk_version();
#define DYLD_MACOSX_VERSION_10_11 MAC_OS_X_VERSION_10_11

void _read_images(header_info **hList, uint32_t hCount)
{
    header_info *hi;
    uint32_t hIndex;
    size_t count;
    size_t i;
    Class *resolvedFutureClasses = nil;
    size_t resolvedFutureClassCount = 0;
    static bool doneOnce;
    TimeLogger ts(PrintImageTimes);

    runtimeLock.assertWriting();

#define EACH_HEADER \
    hIndex = 0;         \
    crashlog_header_name(nil) && hIndex < hCount && (hi = hList[hIndex]) && crashlog_header_name(hi); \
    hIndex++

    if (!doneOnce) {
        doneOnce = YES;

#if SUPPORT_NONPOINTER_ISA

# if TARGET_OS_MAC  &&  !TARGET_OS_IPHONE
        // Disable non-pointer isa if the app is too old
        // (linked before OS X 10.11)
        if (dyld_get_program_sdk_version() < DYLD_MACOSX_VERSION_10_11) {
            DisableIndexedIsa = true;
            if (PrintRawIsa) {
                _objc_inform("RAW ISA: disabling non-pointer isa because "
                             "the app is too old (SDK version " SDK_FORMAT ")",
                             FORMAT_SDK(dyld_get_program_sdk_version()));
            }
        }

        // Disable non-pointer isa if the app has a __DATA,__objc_rawisa section
        // New apps that load old extensions may need this.
        for (EACH_HEADER) {
            if (hi->mhdr->filetype != MH_EXECUTE) continue;
            unsigned long size;
            if (getsectiondata(hi->mhdr, "__DATA", "__objc_rawisa", &size)) {
                DisableIndexedIsa = true;
                if (PrintRawIsa) {
                    _objc_inform("RAW ISA: disabling non-pointer isa because "
                                 "the app has a __DATA,__objc_rawisa section");
                }
            }
            break;  // assume only one MH_EXECUTE image
        }
# endif

        // Disable non-pointer isa for all GC apps.
        if (UseGC) {
            DisableIndexedIsa = true;
            if (PrintRawIsa) {
                _objc_inform("RAW ISA: disabling non-pointer isa because "
                             "the app is GC");
            }
        }

#endif

        if (DisableTaggedPointers) {
            disableTaggedPointers();
        }
        
        // Count classes. Size various table based on the total.
        int total = 0;
        int unoptimizedTotal = 0;
        for (EACH_HEADER) {
            if (_getObjc2ClassList(hi, &count)) {
                total += (int)count;
                if (!hi->inSharedCache) unoptimizedTotal += count;
            }
        }
        
        if (PrintConnecting) {
            _objc_inform("CLASS: found %d classes during launch", total);
        }

        // namedClasses (NOT realizedClasses)
        // Preoptimized classes don't go in this table.
        // 4/3 is NXMapTable's load factor
        int namedClassesSize = 
            (isPreoptimized() ? unoptimizedTotal : total) * 4 / 3;
        gdb_objc_realized_classes =
            NXCreateMapTable(NXStrValueMapPrototype, namedClassesSize);
        
        // realizedClasses and realizedMetaclasses - less than the full total
        realized_class_hash = 
            NXCreateHashTable(NXPtrPrototype, total / 8, nil);
        realized_metaclass_hash = 
            NXCreateHashTable(NXPtrPrototype, total / 8, nil);

        ts.log("IMAGE TIMES: first time tasks");
    }


    // Discover classes. Fix up unresolved future classes. Mark bundle classes.

    for (EACH_HEADER) {
        bool headerIsBundle = hi->isBundle();
        bool headerIsPreoptimized = hi->isPreoptimized();

        classref_t *classlist = _getObjc2ClassList(hi, &count);
        for (i = 0; i < count; i++) {
            Class cls = (Class)classlist[i];
            Class newCls = readClass(cls, headerIsBundle, headerIsPreoptimized);

            if (newCls != cls  &&  newCls) {
                // Class was moved but not deleted. Currently this occurs 
                // only when the new class resolved a future class.
                // Non-lazily realize the class below.
                resolvedFutureClasses = (Class *)
                    realloc(resolvedFutureClasses, 
                                      (resolvedFutureClassCount+1) 
                                      * sizeof(Class));
                resolvedFutureClasses[resolvedFutureClassCount++] = newCls;
            }
        }
    }

    ts.log("IMAGE TIMES: discover classes");

    // Fix up remapped classes
    // Class list and nonlazy class list remain unremapped.
    // Class refs and super refs are remapped for message dispatching.
    
    if (!noClassesRemapped()) {
        for (EACH_HEADER) {
            Class *classrefs = _getObjc2ClassRefs(hi, &count);
            for (i = 0; i < count; i++) {
                remapClassRef(&classrefs[i]);
            }
            // fixme why doesn't test future1 catch the absence of this?
            classrefs = _getObjc2SuperRefs(hi, &count);
            for (i = 0; i < count; i++) {
                remapClassRef(&classrefs[i]);
            }
        }
    }

    ts.log("IMAGE TIMES: remap classes");

    // Fix up @selector references
    static size_t UnfixedSelectors;
    sel_lock();
    for (EACH_HEADER) {
        if (hi->isPreoptimized()) continue;

        bool isBundle = hi->isBundle();
        SEL *sels = _getObjc2SelectorRefs(hi, &count);
        UnfixedSelectors += count;
        for (i = 0; i < count; i++) {
            const char *name = sel_cname(sels[i]);
            sels[i] = sel_registerNameNoLock(name, isBundle);
        }
    }
    sel_unlock();

    ts.log("IMAGE TIMES: fix up selector references");

#if SUPPORT_FIXUP
    // Fix up old objc_msgSend_fixup call sites
    for (EACH_HEADER) {
        message_ref_t *refs = _getObjc2MessageRefs(hi, &count);
        if (count == 0) continue;

        if (PrintVtables) {
            _objc_inform("VTABLES: repairing %zu unsupported vtable dispatch "
                         "call sites in %s", count, hi->fname);
        }
        for (i = 0; i < count; i++) {
            fixupMessageRef(refs+i);
        }
    }

    ts.log("IMAGE TIMES: fix up objc_msgSend_fixup");
#endif

    // Discover protocols. Fix up protocol refs.
    for (EACH_HEADER) {
        extern objc_class OBJC_CLASS_$_Protocol;
        Class cls = (Class)&OBJC_CLASS_$_Protocol;
        assert(cls);
        NXMapTable *protocol_map = protocols();
        bool isPreoptimized = hi->isPreoptimized();
        bool isBundle = hi->isBundle();

        protocol_t **protolist = _getObjc2ProtocolList(hi, &count);
        for (i = 0; i < count; i++) {
            readProtocol(protolist[i], cls, protocol_map, 
                         isPreoptimized, isBundle);
        }
    }

    ts.log("IMAGE TIMES: discover protocols");

    // Fix up @protocol references
    // Preoptimized images may have the right 
    // answer already but we don't know for sure.
    for (EACH_HEADER) {
        protocol_t **protolist = _getObjc2ProtocolRefs(hi, &count);
        for (i = 0; i < count; i++) {
            remapProtocolRef(&protolist[i]);
        }
    }

    ts.log("IMAGE TIMES: fix up @protocol references");

    // Realize non-lazy classes (for +load methods and static instances)
    for (EACH_HEADER) {
        classref_t *classlist = 
            _getObjc2NonlazyClassList(hi, &count);
        for (i = 0; i < count; i++) {
            Class cls = remapClass(classlist[i]);
            if (!cls) continue;

            // hack for class __ARCLite__, which didn't get this above
#if TARGET_IPHONE_SIMULATOR
            if (cls->cache._buckets == (void*)&_objc_empty_cache  &&  
                (cls->cache._mask  ||  cls->cache._occupied)) 
            {
                cls->cache._mask = 0;
                cls->cache._occupied = 0;
            }
            if (cls->ISA()->cache._buckets == (void*)&_objc_empty_cache  &&  
                (cls->ISA()->cache._mask  ||  cls->ISA()->cache._occupied)) 
            {
                cls->ISA()->cache._mask = 0;
                cls->ISA()->cache._occupied = 0;
            }
#endif

            realizeClass(cls);
        }
    }

    ts.log("IMAGE TIMES: realize non-lazy classes");

    // Realize newly-resolved future classes, in case CF manipulates them
    if (resolvedFutureClasses) {
        for (i = 0; i < resolvedFutureClassCount; i++) {
            realizeClass(resolvedFutureClasses[i]);
            resolvedFutureClasses[i]->setRequiresRawIsa(false/*inherited*/);
        }
        free(resolvedFutureClasses);
    }    

    ts.log("IMAGE TIMES: realize future classes");

    // Discover categories. 
    for (EACH_HEADER) {
        category_t **catlist = 
            _getObjc2CategoryList(hi, &count);
        for (i = 0; i < count; i++) {
            category_t *cat = catlist[i];
            Class cls = remapClass(cat->cls);

            if (!cls) {
                // Category's target class is missing (probably weak-linked).
                // Disavow any knowledge of this category.
                catlist[i] = nil;
                if (PrintConnecting) {
                    _objc_inform("CLASS: IGNORING category \?\?\?(%s) %p with "
                                 "missing weak-linked target class", 
                                 cat->name, cat);
                }
                continue;
            }

            // Process this category. 
            // First, register the category with its target class. 
            // Then, rebuild the class's method lists (etc) if 
            // the class is realized. 
            bool classExists = NO;
            if (cat->instanceMethods ||  cat->protocols  
                ||  cat->instanceProperties) 
            {
                addUnattachedCategoryForClass(cat, cls, hi);
                if (cls->isRealized()) {
                    remethodizeClass(cls);
                    classExists = YES;
                }
                if (PrintConnecting) {
                    _objc_inform("CLASS: found category -%s(%s) %s", 
                                 cls->nameForLogging(), cat->name, 
                                 classExists ? "on existing class" : "");
                }
            }

            if (cat->classMethods  ||  cat->protocols  
                /* ||  cat->classProperties */) 
            {
                addUnattachedCategoryForClass(cat, cls->ISA(), hi);
                if (cls->ISA()->isRealized()) {
                    remethodizeClass(cls->ISA());
                }
                if (PrintConnecting) {
                    _objc_inform("CLASS: found category +%s(%s)", 
                                 cls->nameForLogging(), cat->name);
                }
            }
        }
    }

    ts.log("IMAGE TIMES: discover categories");

    // Category discovery MUST BE LAST to avoid potential races 
    // when other threads call the new category code before 
    // this thread finishes its fixups.

    // +load handled by prepare_load_methods()

    if (DebugNonFragileIvars) {
        realizeAllClasses();
    }


    // Print preoptimization statistics
    if (PrintPreopt) {
        static unsigned int PreoptTotalMethodLists;
        static unsigned int PreoptOptimizedMethodLists;
        static unsigned int PreoptTotalClasses;
        static unsigned int PreoptOptimizedClasses;

        for (EACH_HEADER) {
            if (hi->isPreoptimized()) {
                _objc_inform("PREOPTIMIZATION: honoring preoptimized selectors "
                             "in %s", hi->fname);
            }
            else if (_objcHeaderOptimizedByDyld(hi)) {
                _objc_inform("PREOPTIMIZATION: IGNORING preoptimized selectors "
                             "in %s", hi->fname);
            }

            classref_t *classlist = _getObjc2ClassList(hi, &count);
            for (i = 0; i < count; i++) {
                Class cls = remapClass(classlist[i]);
                if (!cls) continue;

                PreoptTotalClasses++;
                if (hi->isPreoptimized()) {
                    PreoptOptimizedClasses++;
                }
                
                const method_list_t *mlist;
                if ((mlist = ((class_ro_t *)cls->data())->baseMethods())) {
                    PreoptTotalMethodLists++;
                    if (mlist->isFixedUp()) {
                        PreoptOptimizedMethodLists++;
                    }
                }
                if ((mlist=((class_ro_t *)cls->ISA()->data())->baseMethods())) {
                    PreoptTotalMethodLists++;
                    if (mlist->isFixedUp()) {
                        PreoptOptimizedMethodLists++;
                    }
                }
            }
        }

        _objc_inform("PREOPTIMIZATION: %zu selector references not "
                     "pre-optimized", UnfixedSelectors);
        _objc_inform("PREOPTIMIZATION: %u/%u (%.3g%%) method lists pre-sorted",
                     PreoptOptimizedMethodLists, PreoptTotalMethodLists, 
                     PreoptTotalMethodLists
                     ? 100.0*PreoptOptimizedMethodLists/PreoptTotalMethodLists 
                     : 0.0);
        _objc_inform("PREOPTIMIZATION: %u/%u (%.3g%%) classes pre-registered",
                     PreoptOptimizedClasses, PreoptTotalClasses, 
                     PreoptTotalClasses 
                     ? 100.0*PreoptOptimizedClasses/PreoptTotalClasses
                     : 0.0);
        _objc_inform("PREOPTIMIZATION: %zu protocol references not "
                     "pre-optimized", UnfixedProtocolReferences);
    }

#undef EACH_HEADER
}


/***********************************************************************
* prepare_load_methods
* Schedule +load for classes in this image, any un-+load-ed 
* superclasses in other images, and any categories in this image.
**********************************************************************/
// Recursively schedule +load for cls and any un-+load-ed superclasses.
// cls must already be connected.
static void schedule_class_load(Class cls)
{
    if (!cls) return;
    assert(cls->isRealized());  // _read_images should realize

    if (cls->data()->flags & RW_LOADED) return;

    // Ensure superclass-first ordering
    schedule_class_load(cls->superclass);

    add_class_to_loadable_list(cls);
    cls->setInfo(RW_LOADED); 
}

// Quick scan for +load methods that doesn't take a lock.
bool hasLoadMethods(const headerType *mhdr)
{
    size_t count;
    if (_getObjc2NonlazyClassList(mhdr, &count)  &&  count > 0) return true;
    if (_getObjc2NonlazyCategoryList(mhdr, &count)  &&  count > 0) return true;
    return false;
}

void prepare_load_methods(const headerType *mhdr)
{
    size_t count, i;

    runtimeLock.assertWriting();

    classref_t *classlist = 
        _getObjc2NonlazyClassList(mhdr, &count);
    for (i = 0; i < count; i++) {
        schedule_class_load(remapClass(classlist[i]));
    }

    category_t **categorylist = _getObjc2NonlazyCategoryList(mhdr, &count);
    for (i = 0; i < count; i++) {
        category_t *cat = categorylist[i];
        Class cls = remapClass(cat->cls);
        if (!cls) continue;  // category for ignored weak-linked class
        realizeClass(cls);
        assert(cls->ISA()->isRealized());
        add_category_to_loadable_list(cat);
    }
}


/***********************************************************************
* _unload_image
* Only handles MH_BUNDLE for now.
* Locking: write-lock and loadMethodLock acquired by unmap_image
**********************************************************************/
void _unload_image(header_info *hi)
{
    size_t count, i;

    loadMethodLock.assertLocked();
    runtimeLock.assertWriting();

    // Unload unattached categories and categories waiting for +load.

    category_t **catlist = _getObjc2CategoryList(hi, &count);
    for (i = 0; i < count; i++) {
        category_t *cat = catlist[i];
        if (!cat) continue;  // category for ignored weak-linked class
        Class cls = remapClass(cat->cls);
        assert(cls);  // shouldn't have live category for dead class

        // fixme for MH_DYLIB cat's class may have been unloaded already

        // unattached list
        removeUnattachedCategoryForClass(cat, cls);

        // +load queue
        remove_category_from_loadable_list(cat);
    }

    // Unload classes.

    classref_t *classlist = _getObjc2ClassList(hi, &count);

    // First detach classes from each other. Then free each class.
    // This avoid bugs where this loop unloads a subclass before its superclass

    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        if (cls) {
            remove_class_from_loadable_list(cls);
            detach_class(cls->ISA(), YES);
            detach_class(cls, NO);
        }
    }
    
    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        if (cls) {
            free_class(cls->ISA());
            free_class(cls);
        }
    }
    
    // XXX FIXME -- Clean up protocols:
    // <rdar://problem/9033191> Support unloading protocols at dylib/image unload time

    // fixme DebugUnload
}


/***********************************************************************
* method_getDescription
* Returns a pointer to this method's objc_method_description.
* Locking: none
**********************************************************************/
struct objc_method_description *
method_getDescription(Method m)
{
    if (!m) return nil;
    return (struct objc_method_description *)m;
}


IMP 
method_getImplementation(Method m)
{
    return m ? m->imp : nil;
}


/***********************************************************************
* method_getName
* Returns this method's selector.
* The method must not be nil.
* The method must already have been fixed-up.
* Locking: none
**********************************************************************/
SEL 
method_getName(Method m)
{
    if (!m) return nil;

    assert(m->name == sel_registerName(sel_getName(m->name)));
    return m->name;
}


/***********************************************************************
* method_getTypeEncoding
* Returns this method's old-style type encoding string.
* The method must not be nil.
* Locking: none
**********************************************************************/
const char *
method_getTypeEncoding(Method m)
{
    if (!m) return nil;
    return m->types;
}


/***********************************************************************
* method_setImplementation
* Sets this method's implementation to imp.
* The previous implementation is returned.
**********************************************************************/
static IMP 
_method_setImplementation(Class cls, method_t *m, IMP imp)
{
    runtimeLock.assertWriting();

    if (!m) return nil;
    if (!imp) return nil;

    if (ignoreSelector(m->name)) {
        // Ignored methods stay ignored
        return m->imp;
    }

    IMP old = m->imp;
    m->imp = imp;

    // Cache updates are slow if cls is nil (i.e. unknown)
    // RR/AWZ updates are slow if cls is nil (i.e. unknown)
    // fixme build list of classes whose Methods are known externally?

    flushCaches(cls);

    updateCustomRR_AWZ(cls, m);

    return old;
}

IMP 
method_setImplementation(Method m, IMP imp)
{
    // Don't know the class - will be slow if RR/AWZ are affected
    // fixme build list of classes whose Methods are known externally?
    rwlock_writer_t lock(runtimeLock);
    return _method_setImplementation(Nil, m, imp);
}


void method_exchangeImplementations(Method m1, Method m2)
{
    if (!m1  ||  !m2) return;

    rwlock_writer_t lock(runtimeLock);

    if (ignoreSelector(m1->name)  ||  ignoreSelector(m2->name)) {
        // Ignored methods stay ignored. Now they're both ignored.
        m1->imp = (IMP)&_objc_ignored_method;
        m2->imp = (IMP)&_objc_ignored_method;
        return;
    }

    IMP m1_imp = m1->imp;
    m1->imp = m2->imp;
    m2->imp = m1_imp;


    // RR/AWZ updates are slow because class is unknown
    // Cache updates are slow because class is unknown
    // fixme build list of classes whose Methods are known externally?

    flushCaches(nil);

    updateCustomRR_AWZ(nil, m1);
    updateCustomRR_AWZ(nil, m2);
}


/***********************************************************************
* ivar_getOffset
* fixme
* Locking: none
**********************************************************************/
ptrdiff_t
ivar_getOffset(Ivar ivar)
{
    if (!ivar) return 0;
    return *ivar->offset;
}


/***********************************************************************
* ivar_getName
* fixme
* Locking: none
**********************************************************************/
const char *
ivar_getName(Ivar ivar)
{
    if (!ivar) return nil;
    return ivar->name;
}


/***********************************************************************
* ivar_getTypeEncoding
* fixme
* Locking: none
**********************************************************************/
const char *
ivar_getTypeEncoding(Ivar ivar)
{
    if (!ivar) return nil;
    return ivar->type;
}



const char *property_getName(objc_property_t prop)
{
    return prop->name;
}

const char *property_getAttributes(objc_property_t prop)
{
    return prop->attributes;
}

objc_property_attribute_t *property_copyAttributeList(objc_property_t prop, 
                                                      unsigned int *outCount)
{
    if (!prop) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);
    return copyPropertyAttributeList(prop->attributes,outCount);
}

char * property_copyAttributeValue(objc_property_t prop, const char *name)
{
    if (!prop  ||  !name  ||  *name == '\0') return nil;
    
    rwlock_reader_t lock(runtimeLock);
    return copyPropertyAttributeValue(prop->attributes, name);
}


/***********************************************************************
* getExtendedTypesIndexesForMethod
* Returns:
* a is the count of methods in all method lists before m's method list
* b is the index of m in m's method list
* a+b is the index of m's extended types in the extended types array
**********************************************************************/
static void getExtendedTypesIndexesForMethod(protocol_t *proto, const method_t *m, bool isRequiredMethod, bool isInstanceMethod, uint32_t& a, uint32_t &b)
{
    a = 0;

    if (proto->instanceMethods) {
        if (isRequiredMethod && isInstanceMethod) {
            b = proto->instanceMethods->indexOfMethod(m);
            return;
        }
        a += proto->instanceMethods->count;
    }

    if (proto->classMethods) {
        if (isRequiredMethod && !isInstanceMethod) {
            b = proto->classMethods->indexOfMethod(m);
            return;
        }
        a += proto->classMethods->count;
    }

    if (proto->optionalInstanceMethods) {
        if (!isRequiredMethod && isInstanceMethod) {
            b = proto->optionalInstanceMethods->indexOfMethod(m);
            return;
        }
        a += proto->optionalInstanceMethods->count;
    }

    if (proto->optionalClassMethods) {
        if (!isRequiredMethod && !isInstanceMethod) {
            b = proto->optionalClassMethods->indexOfMethod(m);
            return;
        }
        a += proto->optionalClassMethods->count;
    }
}


/***********************************************************************
* getExtendedTypesIndexForMethod
* Returns the index of m's extended types in proto's extended types array.
**********************************************************************/
static uint32_t getExtendedTypesIndexForMethod(protocol_t *proto, const method_t *m, bool isRequiredMethod, bool isInstanceMethod)
{
    uint32_t a;
    uint32_t b;
    getExtendedTypesIndexesForMethod(proto, m, isRequiredMethod, 
                                     isInstanceMethod, a, b);
    return a + b;
}


/***********************************************************************
* fixupProtocolMethodList
* Fixes up a single method list in a protocol.
**********************************************************************/
static void
fixupProtocolMethodList(protocol_t *proto, method_list_t *mlist,  
                        bool required, bool instance)
{
    runtimeLock.assertWriting();

    if (!mlist) return;
    if (mlist->isFixedUp()) return;

    bool hasExtendedMethodTypes = proto->hasExtendedMethodTypes();
    fixupMethodList(mlist, true/*always copy for simplicity*/,
                    !hasExtendedMethodTypes/*sort if no ext*/);
    
    if (hasExtendedMethodTypes) {
        // Sort method list and extended method types together.
        // fixupMethodList() can't do this.
        // fixme COW stomp
        uint32_t count = mlist->count;
        uint32_t prefix;
        uint32_t junk;
        getExtendedTypesIndexesForMethod(proto, &mlist->get(0), 
                                         required, instance, prefix, junk);
        const char **types = proto->extendedMethodTypes;
        for (uint32_t i = 0; i < count; i++) {
            for (uint32_t j = i+1; j < count; j++) {
                method_t& mi = mlist->get(i);
                method_t& mj = mlist->get(j);
                if (mi.name > mj.name) {
                    std::swap(mi, mj);
                    std::swap(types[prefix+i], types[prefix+j]);
                }
            }
        }
    }
}


/***********************************************************************
* fixupProtocol
* Fixes up all of a protocol's method lists.
**********************************************************************/
static void 
fixupProtocol(protocol_t *proto)
{
    runtimeLock.assertWriting();

    if (proto->protocols) {
        for (uintptr_t i = 0; i < proto->protocols->count; i++) {
            protocol_t *sub = remapProtocol(proto->protocols->list[i]);
            if (!sub->isFixedUp()) fixupProtocol(sub);
        }
    }

    fixupProtocolMethodList(proto, proto->instanceMethods, YES, YES);
    fixupProtocolMethodList(proto, proto->classMethods, YES, NO);
    fixupProtocolMethodList(proto, proto->optionalInstanceMethods, NO, YES);
    fixupProtocolMethodList(proto, proto->optionalClassMethods, NO, NO);

    // fixme memory barrier so we can check this with no lock
    proto->setFixedUp();
}


/***********************************************************************
* fixupProtocolIfNeeded
* Fixes up all of a protocol's method lists if they aren't fixed up already.
* Locking: write-locks runtimeLock.
**********************************************************************/
static void 
fixupProtocolIfNeeded(protocol_t *proto)
{
    runtimeLock.assertUnlocked();
    assert(proto);

    if (!proto->isFixedUp()) {
        rwlock_writer_t lock(runtimeLock);
        fixupProtocol(proto);
    }
}


static method_list_t *
getProtocolMethodList(protocol_t *proto, bool required, bool instance)
{
    method_list_t **mlistp = nil;
    if (required) {
        if (instance) {
            mlistp = &proto->instanceMethods;
        } else {
            mlistp = &proto->classMethods;
        }
    } else {
        if (instance) {
            mlistp = &proto->optionalInstanceMethods;
        } else {
            mlistp = &proto->optionalClassMethods;
        }
    }

    return *mlistp;
}


/***********************************************************************
* protocol_getMethod_nolock
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static method_t *
protocol_getMethod_nolock(protocol_t *proto, SEL sel, 
                          bool isRequiredMethod, bool isInstanceMethod, 
                          bool recursive)
{
    runtimeLock.assertLocked();

    if (!proto  ||  !sel) return nil;

    assert(proto->isFixedUp());

    method_list_t *mlist = 
        getProtocolMethodList(proto, isRequiredMethod, isInstanceMethod);
    if (mlist) {
        method_t *m = search_method_list(mlist, sel);
        if (m) return m;
    }

    if (recursive  &&  proto->protocols) {
        method_t *m;
        for (uint32_t i = 0; i < proto->protocols->count; i++) {
            protocol_t *realProto = remapProtocol(proto->protocols->list[i]);
            m = protocol_getMethod_nolock(realProto, sel, 
                                          isRequiredMethod, isInstanceMethod, 
                                          true);
            if (m) return m;
        }
    }

    return nil;
}


/***********************************************************************
* protocol_getMethod
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
Method 
protocol_getMethod(protocol_t *proto, SEL sel, bool isRequiredMethod, bool isInstanceMethod, bool recursive)
{
    if (!proto) return nil;
    fixupProtocolIfNeeded(proto);

    rwlock_reader_t lock(runtimeLock);
    return protocol_getMethod_nolock(proto, sel, isRequiredMethod, 
                                     isInstanceMethod, recursive);
}


/***********************************************************************
* protocol_getMethodTypeEncoding_nolock
* Return the @encode string for the requested protocol method.
* Returns nil if the compiler did not emit any extended @encode data.
* Locking: runtimeLock must be held for writing by the caller
**********************************************************************/
const char * 
protocol_getMethodTypeEncoding_nolock(protocol_t *proto, SEL sel, 
                                      bool isRequiredMethod, 
                                      bool isInstanceMethod)
{
    runtimeLock.assertLocked();

    if (!proto) return nil;
    if (!proto->hasExtendedMethodTypes()) return nil;

    assert(proto->isFixedUp());

    method_t *m = 
        protocol_getMethod_nolock(proto, sel, 
                                  isRequiredMethod, isInstanceMethod, false);
    if (m) {
        uint32_t i = getExtendedTypesIndexForMethod(proto, m, 
                                                    isRequiredMethod, 
                                                    isInstanceMethod);
        return proto->extendedMethodTypes[i];
    }

    // No method with that name. Search incorporated protocols.
    if (proto->protocols) {
        for (uintptr_t i = 0; i < proto->protocols->count; i++) {
            const char *enc = 
                protocol_getMethodTypeEncoding_nolock(remapProtocol(proto->protocols->list[i]), sel, isRequiredMethod, isInstanceMethod);
            if (enc) return enc;
        }
    }

    return nil;
}

/***********************************************************************
* _protocol_getMethodTypeEncoding
* Return the @encode string for the requested protocol method.
* Returns nil if the compiler did not emit any extended @encode data.
* Locking: acquires runtimeLock
**********************************************************************/
const char * 
_protocol_getMethodTypeEncoding(Protocol *proto_gen, SEL sel, 
                                BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    protocol_t *proto = newprotocol(proto_gen);

    if (!proto) return nil;
    fixupProtocolIfNeeded(proto);

    rwlock_reader_t lock(runtimeLock);
    return protocol_getMethodTypeEncoding_nolock(proto, sel, 
                                                 isRequiredMethod, 
                                                 isInstanceMethod);
}


/***********************************************************************
* protocol_t::demangledName
* Returns the (Swift-demangled) name of the given protocol.
* Locking: none
**********************************************************************/
const char *
protocol_t::demangledName() 
{
    assert(size >= offsetof(protocol_t, _demangledName)+sizeof(_demangledName));
    
    if (! _demangledName) {
        char *de = copySwiftV1DemangledName(mangledName, true/*isProtocol*/);
        if (! OSAtomicCompareAndSwapPtrBarrier(nil, (void*)(de ?: mangledName), 
                                               (void**)&_demangledName)) 
        {
            if (de) free(de);
        }
    }
    return _demangledName;
}

/***********************************************************************
* protocol_getName
* Returns the (Swift-demangled) name of the given protocol.
* Locking: runtimeLock must not be held by the caller
**********************************************************************/
const char *
protocol_getName(Protocol *proto)
{
    if (!proto) return "nil";
    else return newprotocol(proto)->demangledName();
}


/***********************************************************************
* protocol_getInstanceMethodDescription
* Returns the description of a named instance method.
* Locking: runtimeLock must not be held by the caller
**********************************************************************/
struct objc_method_description 
protocol_getMethodDescription(Protocol *p, SEL aSel, 
                              BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    Method m = 
        protocol_getMethod(newprotocol(p), aSel, 
                           isRequiredMethod, isInstanceMethod, true);
    if (m) return *method_getDescription(m);
    else return (struct objc_method_description){nil, nil};
}


/***********************************************************************
* protocol_conformsToProtocol_nolock
* Returns YES if self conforms to other.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static bool 
protocol_conformsToProtocol_nolock(protocol_t *self, protocol_t *other)
{
    runtimeLock.assertLocked();

    if (!self  ||  !other) {
        return NO;
    }

    // protocols need not be fixed up

    if (0 == strcmp(self->mangledName, other->mangledName)) {
        return YES;
    }

    if (self->protocols) {
        uintptr_t i;
        for (i = 0; i < self->protocols->count; i++) {
            protocol_t *proto = remapProtocol(self->protocols->list[i]);
            if (0 == strcmp(other->mangledName, proto->mangledName)) {
                return YES;
            }
            if (protocol_conformsToProtocol_nolock(proto, other)) {
                return YES;
            }
        }
    }

    return NO;
}


/***********************************************************************
* protocol_conformsToProtocol
* Returns YES if self conforms to other.
* Locking: acquires runtimeLock
**********************************************************************/
BOOL protocol_conformsToProtocol(Protocol *self, Protocol *other)
{
    rwlock_reader_t lock(runtimeLock);
    return protocol_conformsToProtocol_nolock(newprotocol(self), 
                                              newprotocol(other));
}


/***********************************************************************
* protocol_isEqual
* Return YES if two protocols are equal (i.e. conform to each other)
* Locking: acquires runtimeLock
**********************************************************************/
BOOL protocol_isEqual(Protocol *self, Protocol *other)
{
    if (self == other) return YES;
    if (!self  ||  !other) return NO;

    if (!protocol_conformsToProtocol(self, other)) return NO;
    if (!protocol_conformsToProtocol(other, self)) return NO;

    return YES;
}


/***********************************************************************
* protocol_copyMethodDescriptionList
* Returns descriptions of a protocol's methods.
* Locking: acquires runtimeLock
**********************************************************************/
struct objc_method_description *
protocol_copyMethodDescriptionList(Protocol *p, 
                                   BOOL isRequiredMethod,BOOL isInstanceMethod,
                                   unsigned int *outCount)
{
    protocol_t *proto = newprotocol(p);
    struct objc_method_description *result = nil;
    unsigned int count = 0;

    if (!proto) {
        if (outCount) *outCount = 0;
        return nil;
    }

    fixupProtocolIfNeeded(proto);

    rwlock_reader_t lock(runtimeLock);

    method_list_t *mlist = 
        getProtocolMethodList(proto, isRequiredMethod, isInstanceMethod);

    if (mlist) {
        result = (struct objc_method_description *)
            calloc(mlist->count + 1, sizeof(struct objc_method_description));
        for (const auto& meth : *mlist) {
            result[count].name = meth.name;
            result[count].types = (char *)meth.types;
            count++;
        }
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* protocol_getProperty
* fixme
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static property_t * 
protocol_getProperty_nolock(protocol_t *proto, const char *name, 
                            bool isRequiredProperty, bool isInstanceProperty)
{
    runtimeLock.assertLocked();

    if (!isRequiredProperty  ||  !isInstanceProperty) {
        // Only required instance properties are currently supported
        return nil;
    }

    property_list_t *plist;
    if ((plist = proto->instanceProperties)) {
        for (auto& prop : *plist) {
            if (0 == strcmp(name, prop.name)) {
                return &prop;
            }
        }
    }

    if (proto->protocols) {
        uintptr_t i;
        for (i = 0; i < proto->protocols->count; i++) {
            protocol_t *p = remapProtocol(proto->protocols->list[i]);
            property_t *prop = 
                protocol_getProperty_nolock(p, name, 
                                            isRequiredProperty, 
                                            isInstanceProperty);
            if (prop) return prop;
        }
    }

    return nil;
}

objc_property_t protocol_getProperty(Protocol *p, const char *name, 
                              BOOL isRequiredProperty, BOOL isInstanceProperty)
{
    if (!p  ||  !name) return nil;

    rwlock_reader_t lock(runtimeLock);
    return (objc_property_t)
        protocol_getProperty_nolock(newprotocol(p), name, 
                                    isRequiredProperty, isInstanceProperty);
}


/***********************************************************************
* protocol_copyPropertyList
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
static property_t **
copyPropertyList(property_list_t *plist, unsigned int *outCount)
{
    property_t **result = nil;
    unsigned int count = 0;

    if (plist) {
        count = plist->count;
    }

    if (count > 0) {
        result = (property_t **)malloc((count+1) * sizeof(property_t *));

        count = 0;
        for (auto& prop : *plist) {
            result[count++] = &prop;
        }
        result[count] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}

objc_property_t *protocol_copyPropertyList(Protocol *proto, unsigned int *outCount)
{
    if (!proto) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);

    property_list_t *plist = newprotocol(proto)->instanceProperties;
    return (objc_property_t *)copyPropertyList(plist, outCount);
}


/***********************************************************************
* protocol_copyProtocolList
* Copies this protocol's incorporated protocols. 
* Does not copy those protocol's incorporated protocols in turn.
* Locking: acquires runtimeLock
**********************************************************************/
Protocol * __unsafe_unretained * 
protocol_copyProtocolList(Protocol *p, unsigned int *outCount)
{
    unsigned int count = 0;
    Protocol **result = nil;
    protocol_t *proto = newprotocol(p);
    
    if (!proto) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);

    if (proto->protocols) {
        count = (unsigned int)proto->protocols->count;
    }
    if (count > 0) {
        result = (Protocol **)malloc((count+1) * sizeof(Protocol *));

        unsigned int i;
        for (i = 0; i < count; i++) {
            result[i] = (Protocol *)remapProtocol(proto->protocols->list[i]);
        }
        result[i] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* objc_allocateProtocol
* Creates a new protocol. The protocol may not be used until 
* objc_registerProtocol() is called.
* Returns nil if a protocol with the same name already exists.
* Locking: acquires runtimeLock
**********************************************************************/
Protocol *
objc_allocateProtocol(const char *name)
{
    rwlock_writer_t lock(runtimeLock);

    if (getProtocol(name)) {
        return nil;
    }

    protocol_t *result = (protocol_t *)calloc(sizeof(protocol_t), 1);

    extern objc_class OBJC_CLASS_$___IncompleteProtocol;
    Class cls = (Class)&OBJC_CLASS_$___IncompleteProtocol;
    result->initProtocolIsa(cls);
    result->size = sizeof(protocol_t);
    // fixme mangle the name if it looks swift-y?
    result->mangledName = strdup(name);

    // fixme reserve name without installing

    return (Protocol *)result;
}


/***********************************************************************
* objc_registerProtocol
* Registers a newly-constructed protocol. The protocol is now 
* ready for use and immutable.
* Locking: acquires runtimeLock
**********************************************************************/
void objc_registerProtocol(Protocol *proto_gen) 
{
    protocol_t *proto = newprotocol(proto_gen);

    rwlock_writer_t lock(runtimeLock);

    extern objc_class OBJC_CLASS_$___IncompleteProtocol;
    Class oldcls = (Class)&OBJC_CLASS_$___IncompleteProtocol;
    extern objc_class OBJC_CLASS_$_Protocol;
    Class cls = (Class)&OBJC_CLASS_$_Protocol;

    if (proto->ISA() == cls) {
        _objc_inform("objc_registerProtocol: protocol '%s' was already "
                     "registered!", proto->nameForLogging());
        return;
    }
    if (proto->ISA() != oldcls) {
        _objc_inform("objc_registerProtocol: protocol '%s' was not allocated "
                     "with objc_allocateProtocol!", proto->nameForLogging());
        return;
    }

    // NOT initProtocolIsa(). The protocol object may already 
    // have been retained and we must preserve that count.
    proto->changeIsa(cls);

    NXMapKeyCopyingInsert(protocols(), proto->mangledName, proto);
}


/***********************************************************************
* protocol_addProtocol
* Adds an incorporated protocol to another protocol.
* No method enforcement is performed.
* `proto` must be under construction. `addition` must not.
* Locking: acquires runtimeLock
**********************************************************************/
void 
protocol_addProtocol(Protocol *proto_gen, Protocol *addition_gen) 
{
    protocol_t *proto = newprotocol(proto_gen);
    protocol_t *addition = newprotocol(addition_gen);

    extern objc_class OBJC_CLASS_$___IncompleteProtocol;
    Class cls = (Class)&OBJC_CLASS_$___IncompleteProtocol;

    if (!proto_gen) return;
    if (!addition_gen) return;

    rwlock_writer_t lock(runtimeLock);

    if (proto->ISA() != cls) {
        _objc_inform("protocol_addProtocol: modified protocol '%s' is not "
                     "under construction!", proto->nameForLogging());
        return;
    }
    if (addition->ISA() == cls) {
        _objc_inform("protocol_addProtocol: added protocol '%s' is still "
                     "under construction!", addition->nameForLogging());
        return;        
    }
    
    protocol_list_t *protolist = proto->protocols;
    if (!protolist) {
        protolist = (protocol_list_t *)
            calloc(1, sizeof(protocol_list_t) 
                             + sizeof(protolist->list[0]));
    } else {
        protolist = (protocol_list_t *)
            realloc(protolist, protocol_list_size(protolist) 
                              + sizeof(protolist->list[0]));
    }

    protolist->list[protolist->count++] = (protocol_ref_t)addition;
    proto->protocols = protolist;
}


/***********************************************************************
* protocol_addMethodDescription
* Adds a method to a protocol. The protocol must be under construction.
* Locking: acquires runtimeLock
**********************************************************************/
static void
protocol_addMethod_nolock(method_list_t*& list, SEL name, const char *types)
{
    if (!list) {
        list = (method_list_t *)calloc(sizeof(method_list_t), 1);
        list->entsizeAndFlags = sizeof(list->first);
        list->setFixedUp();
    } else {
        size_t size = list->byteSize() + list->entsize();
        list = (method_list_t *)realloc(list, size);
    }

    method_t& meth = list->get(list->count++);
    meth.name = name;
    meth.types = strdup(types ? types : "");
    meth.imp = nil;
}

void 
protocol_addMethodDescription(Protocol *proto_gen, SEL name, const char *types,
                              BOOL isRequiredMethod, BOOL isInstanceMethod) 
{
    protocol_t *proto = newprotocol(proto_gen);

    extern objc_class OBJC_CLASS_$___IncompleteProtocol;
    Class cls = (Class)&OBJC_CLASS_$___IncompleteProtocol;

    if (!proto_gen) return;

    rwlock_writer_t lock(runtimeLock);

    if (proto->ISA() != cls) {
        _objc_inform("protocol_addMethodDescription: protocol '%s' is not "
                     "under construction!", proto->nameForLogging());
        return;
    }

    if (isRequiredMethod  &&  isInstanceMethod) {
        protocol_addMethod_nolock(proto->instanceMethods, name, types);
    } else if (isRequiredMethod  &&  !isInstanceMethod) {
        protocol_addMethod_nolock(proto->classMethods, name, types);
    } else if (!isRequiredMethod  &&  isInstanceMethod) {
        protocol_addMethod_nolock(proto->optionalInstanceMethods, name,types);
    } else /*  !isRequiredMethod  &&  !isInstanceMethod) */ {
        protocol_addMethod_nolock(proto->optionalClassMethods, name, types);
    }
}


/***********************************************************************
* protocol_addProperty
* Adds a property to a protocol. The protocol must be under construction.
* Locking: acquires runtimeLock
**********************************************************************/
static void 
protocol_addProperty_nolock(property_list_t *&plist, const char *name, 
                            const objc_property_attribute_t *attrs, 
                            unsigned int count)
{
    if (!plist) {
        plist = (property_list_t *)calloc(sizeof(property_list_t), 1);
        plist->entsizeAndFlags = sizeof(property_t);
    } else {
        plist = (property_list_t *)
            realloc(plist, sizeof(property_list_t) 
                    + plist->count * plist->entsize());
    }

    property_t& prop = plist->get(plist->count++);
    prop.name = strdup(name);
    prop.attributes = copyPropertyAttributeString(attrs, count);
}

void 
protocol_addProperty(Protocol *proto_gen, const char *name, 
                     const objc_property_attribute_t *attrs, 
                     unsigned int count,
                     BOOL isRequiredProperty, BOOL isInstanceProperty)
{
    protocol_t *proto = newprotocol(proto_gen);

    extern objc_class OBJC_CLASS_$___IncompleteProtocol;
    Class cls = (Class)&OBJC_CLASS_$___IncompleteProtocol;

    if (!proto) return;
    if (!name) return;

    rwlock_writer_t lock(runtimeLock);

    if (proto->ISA() != cls) {
        _objc_inform("protocol_addProperty: protocol '%s' is not "
                     "under construction!", proto->nameForLogging());
        return;
    }

    if (isRequiredProperty  &&  isInstanceProperty) {
        protocol_addProperty_nolock(proto->instanceProperties, name, attrs, count);
    }
    //else if (isRequiredProperty  &&  !isInstanceProperty) {
    //    protocol_addProperty_nolock(proto->classProperties, name, attrs, count);
    //} else if (!isRequiredProperty  &&  isInstanceProperty) {
    //    protocol_addProperty_nolock(proto->optionalInstanceProperties, name, attrs, count);
    //} else /*  !isRequiredProperty  &&  !isInstanceProperty) */ {
    //    protocol_addProperty_nolock(proto->optionalClassProperties, name, attrs, count);
    //}
}


/***********************************************************************
* objc_getClassList
* Returns pointers to all classes.
* This requires all classes be realized, which is regretfully non-lazy.
* Locking: acquires runtimeLock
**********************************************************************/
int 
objc_getClassList(Class *buffer, int bufferLen) 
{
    rwlock_writer_t lock(runtimeLock);

    realizeAllClasses();

    int count;
    Class cls;
    NXHashState state;
    NXHashTable *classes = realizedClasses();
    int allCount = NXCountHashTable(classes);

    if (!buffer) {
        return allCount;
    }

    count = 0;
    state = NXInitHashState(classes);
    while (count < bufferLen  &&  
           NXNextHashState(classes, &state, (void **)&cls))
    {
        buffer[count++] = cls;
    }

    return allCount;
}


/***********************************************************************
* objc_copyClassList
* Returns pointers to all classes.
* This requires all classes be realized, which is regretfully non-lazy.
* 
* outCount may be nil. *outCount is the number of classes returned. 
* If the returned array is not nil, it is nil-terminated and must be 
* freed with free().
* Locking: write-locks runtimeLock
**********************************************************************/
Class *
objc_copyClassList(unsigned int *outCount)
{
    rwlock_writer_t lock(runtimeLock);

    realizeAllClasses();

    Class *result = nil;
    NXHashTable *classes = realizedClasses();
    unsigned int count = NXCountHashTable(classes);

    if (count > 0) {
        Class cls;
        NXHashState state = NXInitHashState(classes);
        result = (Class *)malloc((1+count) * sizeof(Class));
        count = 0;
        while (NXNextHashState(classes, &state, (void **)&cls)) {
            result[count++] = cls;
        }
        result[count] = nil;
    }
        
    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* objc_copyProtocolList
* Returns pointers to all protocols.
* Locking: read-locks runtimeLock
**********************************************************************/
Protocol * __unsafe_unretained * 
objc_copyProtocolList(unsigned int *outCount) 
{
    rwlock_reader_t lock(runtimeLock);

    NXMapTable *protocol_map = protocols();

    unsigned int count = NXCountMapTable(protocol_map);
    if (count == 0) {
        if (outCount) *outCount = 0;
        return nil;
    }

    Protocol **result = (Protocol **)malloc((count+1) * sizeof(Protocol*));

    unsigned int i = 0;
    Protocol *proto;
    const char *name;
    NXMapState state = NXInitMapState(protocol_map);
    while (NXNextMapState(protocol_map, &state, 
                          (const void **)&name, (const void **)&proto))
    {
        result[i++] = proto;
    }
    
    result[i++] = nil;
    assert(i == count+1);

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* objc_getProtocol
* Get a protocol by name, or return nil
* Locking: read-locks runtimeLock
**********************************************************************/
Protocol *objc_getProtocol(const char *name)
{
    rwlock_reader_t lock(runtimeLock); 
    return getProtocol(name);
}


/***********************************************************************
* class_copyMethodList
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
Method *
class_copyMethodList(Class cls, unsigned int *outCount)
{
    unsigned int count = 0;
    Method *result = nil;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);
    
    assert(cls->isRealized());

    count = cls->data()->methods.count();

    if (count > 0) {
        result = (Method *)malloc((count + 1) * sizeof(Method));
        
        count = 0;
        for (auto& meth : cls->data()->methods) {
            if (! ignoreSelector(meth.name)) {
                result[count++] = &meth;
            }
        }
        result[count] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* class_copyIvarList
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
Ivar *
class_copyIvarList(Class cls, unsigned int *outCount)
{
    const ivar_list_t *ivars;
    Ivar *result = nil;
    unsigned int count = 0;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);

    assert(cls->isRealized());
    
    if ((ivars = cls->data()->ro->ivars)  &&  ivars->count) {
        result = (Ivar *)malloc((ivars->count+1) * sizeof(Ivar));
        
        for (auto& ivar : *ivars) {
            if (!ivar.offset) continue;  // anonymous bitfield
            result[count++] = &ivar;
        }
        result[count] = nil;
    }
    
    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* class_copyPropertyList. Returns a heap block containing the 
* properties declared in the class, or nil if the class 
* declares no properties. Caller must free the block.
* Does not copy any superclass's properties.
* Locking: read-locks runtimeLock
**********************************************************************/
objc_property_t *
class_copyPropertyList(Class cls, unsigned int *outCount)
{
    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);

    assert(cls->isRealized());
    auto rw = cls->data();

    property_t **result = nil;
    unsigned int count = rw->properties.count();
    if (count > 0) {
        result = (property_t **)malloc((count + 1) * sizeof(property_t *));

        count = 0;
        for (auto& prop : rw->properties) {
            result[count++] = &prop;
        }
        result[count] = nil;
    }

    if (outCount) *outCount = count;
    return (objc_property_t *)result;
}


/***********************************************************************
* objc_class::getLoadMethod
* fixme
* Called only from add_class_to_loadable_list.
* Locking: runtimeLock must be read- or write-locked by the caller.
**********************************************************************/
IMP 
objc_class::getLoadMethod()
{
    runtimeLock.assertLocked();

    const method_list_t *mlist;

    assert(isRealized());
    assert(ISA()->isRealized());
    assert(!isMetaClass());
    assert(ISA()->isMetaClass());

    mlist = ISA()->data()->ro->baseMethods();
    if (mlist) {
        for (const auto& meth : *mlist) {
            const char *name = sel_cname(meth.name);
            if (0 == strcmp(name, "load")) {
                return meth.imp;
            }
        }
    }

    return nil;
}


/***********************************************************************
* _category_getName
* Returns a category's name.
* Locking: none
**********************************************************************/
const char *
_category_getName(Category cat)
{
    return cat->name;
}


/***********************************************************************
* _category_getClassName
* Returns a category's class's name
* Called only from add_category_to_loadable_list and 
* remove_category_from_loadable_list for logging purposes.
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
const char *
_category_getClassName(Category cat)
{
    runtimeLock.assertLocked();
    return remapClass(cat->cls)->nameForLogging();
}


/***********************************************************************
* _category_getClass
* Returns a category's class
* Called only by call_category_loads.
* Locking: read-locks runtimeLock
**********************************************************************/
Class 
_category_getClass(Category cat)
{
    rwlock_reader_t lock(runtimeLock);
    Class result = remapClass(cat->cls);
    assert(result->isRealized());  // ok for call_category_loads' usage
    return result;
}


/***********************************************************************
* _category_getLoadMethod
* fixme
* Called only from add_category_to_loadable_list
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
IMP 
_category_getLoadMethod(Category cat)
{
    runtimeLock.assertLocked();

    const method_list_t *mlist;

    mlist = cat->classMethods;
    if (mlist) {
        for (const auto& meth : *mlist) {
            const char *name = sel_cname(meth.name);
            if (0 == strcmp(name, "load")) {
                return meth.imp;
            }
        }
    }

    return nil;
}


/***********************************************************************
* class_copyProtocolList
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
Protocol * __unsafe_unretained * 
class_copyProtocolList(Class cls, unsigned int *outCount)
{
    unsigned int count = 0;
    Protocol **result = nil;
    
    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    rwlock_reader_t lock(runtimeLock);

    assert(cls->isRealized());
    
    count = cls->data()->protocols.count();

    if (count > 0) {
        result = (Protocol **)malloc((count+1) * sizeof(Protocol *));

        count = 0;
        for (const auto& proto : cls->data()->protocols) {
            result[count++] = (Protocol *)remapProtocol(proto);
        }
        result[count] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* _objc_copyClassNamesForImage
* fixme
* Locking: write-locks runtimeLock
**********************************************************************/
const char **
_objc_copyClassNamesForImage(header_info *hi, unsigned int *outCount)
{
    size_t count, i, shift;
    classref_t *classlist;
    const char **names;
    
    // Need to write-lock in case demangledName() needs to realize a class.
    rwlock_writer_t lock(runtimeLock);
    
    classlist = _getObjc2ClassList(hi, &count);
    names = (const char **)malloc((count+1) * sizeof(const char *));
    
    shift = 0;
    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        if (cls) {
            names[i-shift] = cls->demangledName(true/*realize*/);
        } else {
            shift++;  // ignored weak-linked class
        }
    }
    count -= shift;
    names[count] = nil;

    if (outCount) *outCount = (unsigned int)count;
    return names;
}


/***********************************************************************
 * _class_getInstanceStart
 * Uses alignedInstanceStart() to ensure that ARR layout strings are
 * interpreted relative to the first word aligned ivar of an object.
 * Locking: none
 **********************************************************************/

static uint32_t
alignedInstanceStart(Class cls)
{
    assert(cls);
    assert(cls->isRealized());
    return (uint32_t)word_align(cls->data()->ro->instanceStart);
}

uint32_t _class_getInstanceStart(Class cls) {
    return alignedInstanceStart(cls);
}


/***********************************************************************
* saveTemporaryString
* Save a string in a thread-local FIFO buffer. 
* This is suitable for temporary strings generated for logging purposes.
**********************************************************************/
static void
saveTemporaryString(char *str)
{
    // Fixed-size FIFO. We free the first string, shift 
    // the rest, and add the new string to the end.
    _objc_pthread_data *data = _objc_fetch_pthread_data(true);
    if (data->printableNames[0]) {
        free(data->printableNames[0]);
    }
    int last = countof(data->printableNames) - 1;
    for (int i = 0; i < last; i++) {
        data->printableNames[i] = data->printableNames[i+1];
    }
    data->printableNames[last] = str;
}


/***********************************************************************
* objc_class::nameForLogging
* Returns the class's name, suitable for display.
* The returned memory is TEMPORARY. Print it or copy it immediately.
* Locking: none
**********************************************************************/
const char *
objc_class::nameForLogging()
{
    // Handle the easy case directly.
    if (isRealized()  ||  isFuture()) {
        if (data()->demangledName) return data()->demangledName;
    }

    char *result;

    const char *name = mangledName();
    char *de = copySwiftV1DemangledName(name);
    if (de) result = de;
    else result = strdup(name);

    saveTemporaryString(result);
    return result;
}


/***********************************************************************
* objc_class::demangledName
* If realize=false, the class must already be realized or future.
* Locking: If realize=true, runtimeLock must be held for writing by the caller.
**********************************************************************/
const char *
objc_class::demangledName(bool realize)
{
    // Return previously demangled name if available.
    if (isRealized()  ||  isFuture()) {
        if (data()->demangledName) return data()->demangledName;
    }

    // Try demangling the mangled name.
    const char *mangled = mangledName();
    char *de = copySwiftV1DemangledName(mangled);
    if (isRealized()  ||  isFuture()) {
        // Class is already realized or future. 
        // Save demangling result in rw data.
        // We may not own rwlock for writing so use an atomic operation instead.
        if (! OSAtomicCompareAndSwapPtrBarrier(nil, (void*)(de ?: mangled), 
                                               (void**)&data()->demangledName)) 
        {
            if (de) free(de);
        }
        return data()->demangledName;
    }

    // Class is not yet realized.
    if (!de) {
        // Name is not mangled. Return it without caching.
        return mangled;
    }

    // Class is not yet realized and name is mangled. Realize the class.
    // Only objc_copyClassNamesForImage() should get here.
    runtimeLock.assertWriting();
    assert(realize);
    if (realize) {
        realizeClass((Class)this);
        data()->demangledName = de;
        return de;
    } else {
        return de;  // bug - just leak
    }
}


/***********************************************************************
* class_getName
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
const char *class_getName(Class cls)
{
    if (!cls) return "nil";
    assert(cls->isRealized()  ||  cls->isFuture());
    return cls->demangledName();
}


/***********************************************************************
* class_getVersion
* fixme
* Locking: none
**********************************************************************/
int 
class_getVersion(Class cls)
{
    if (!cls) return 0;
    assert(cls->isRealized());
    return cls->data()->version;
}


/***********************************************************************
* class_setVersion
* fixme
* Locking: none
**********************************************************************/
void 
class_setVersion(Class cls, int version)
{
    if (!cls) return;
    assert(cls->isRealized());
    cls->data()->version = version;
}


static method_t *findMethodInSortedMethodList(SEL key, const method_list_t *list)
{
    assert(list);

    const method_t * const first = &list->first;
    const method_t *base = first;
    const method_t *probe;
    uintptr_t keyValue = (uintptr_t)key;
    uint32_t count;
    
    for (count = list->count; count != 0; count >>= 1) {
        probe = base + (count >> 1);
        
        uintptr_t probeValue = (uintptr_t)probe->name;
        
        if (keyValue == probeValue) {
            // `probe` is a match.
            // Rewind looking for the *first* occurrence of this value.
            // This is required for correct category overrides.
            while (probe > first && keyValue == (uintptr_t)probe[-1].name) {
                probe--;
            }
            return (method_t *)probe;
        }
        
        if (keyValue > probeValue) {
            base = probe + 1;
            count--;
        }
    }
    
    return nil;
}

/***********************************************************************
* getMethodNoSuper_nolock
* fixme
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static method_t *search_method_list(const method_list_t *mlist, SEL sel)
{
    int methodListIsFixedUp = mlist->isFixedUp();
    int methodListHasExpectedSize = mlist->entsize() == sizeof(method_t);
    
    if (__builtin_expect(methodListIsFixedUp && methodListHasExpectedSize, 1)) {
        return findMethodInSortedMethodList(sel, mlist);
    } else {
        // Linear search of unsorted method list
        for (auto& meth : *mlist) {
            if (meth.name == sel) return &meth;
        }
    }

#if DEBUG
    // sanity-check negative results
    if (mlist->isFixedUp()) {
        for (auto& meth : *mlist) {
            if (meth.name == sel) {
                _objc_fatal("linear search worked when binary search did not");
            }
        }
    }
#endif

    return nil;
}

static method_t *
getMethodNoSuper_nolock(Class cls, SEL sel)
{
    runtimeLock.assertLocked();

    assert(cls->isRealized());
    // fixme nil cls? 
    // fixme nil sel?

    for (auto mlists = cls->data()->methods.beginLists(), 
              end = cls->data()->methods.endLists(); 
         mlists != end;
         ++mlists)
    {
        method_t *m = search_method_list(*mlists, sel);
        if (m) return m;
    }

    return nil;
}


/***********************************************************************
* getMethod_nolock
* fixme
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static method_t *
getMethod_nolock(Class cls, SEL sel)
{
    method_t *m = nil;

    runtimeLock.assertLocked();

    // fixme nil cls?
    // fixme nil sel?

    assert(cls->isRealized());

    while (cls  &&  ((m = getMethodNoSuper_nolock(cls, sel))) == nil) {
        cls = cls->superclass;
    }

    return m;
}


/***********************************************************************
* _class_getMethod
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
static Method _class_getMethod(Class cls, SEL sel)
{
    rwlock_reader_t lock(runtimeLock);
    return getMethod_nolock(cls, sel);
}


/***********************************************************************
* class_getInstanceMethod.  Return the instance method for the
* specified class and selector.
**********************************************************************/
Method class_getInstanceMethod(Class cls, SEL sel)
{
    if (!cls  ||  !sel) return nil;

    // This deliberately avoids +initialize because it historically did so.

    // This implementation is a bit weird because it's the only place that 
    // wants a Method instead of an IMP.

#warning fixme build and search caches
        
    // Search method lists, try method resolver, etc.
    lookUpImpOrNil(cls, sel, nil, 
                   NO/*initialize*/, NO/*cache*/, YES/*resolver*/);

#warning fixme build and search caches

    return _class_getMethod(cls, sel);
}


/***********************************************************************
* log_and_fill_cache
* Log this method call. If the logger permits it, fill the method cache.
* cls is the method whose cache should be filled. 
* implementer is the class that owns the implementation in question.
**********************************************************************/
static void
log_and_fill_cache(Class cls, IMP imp, SEL sel, id receiver, Class implementer)
{
#if SUPPORT_MESSAGE_LOGGING
    if (objcMsgLogEnabled) {
        bool cacheIt = logMessageSend(implementer->isMetaClass(), 
                                      cls->nameForLogging(),
                                      implementer->nameForLogging(), 
                                      sel);
        if (!cacheIt) return;
    }
#endif
    cache_fill (cls, sel, imp, receiver);
}


/***********************************************************************
* _class_lookupMethodAndLoadCache.
* Method lookup for dispatchers ONLY. OTHER CODE SHOULD USE lookUpImp().
* This lookup avoids optimistic cache scan because the dispatcher 
* already tried that.
**********************************************************************/
IMP _class_lookupMethodAndLoadCache3(id obj, SEL sel, Class cls)
{
    return lookUpImpOrForward(cls, sel, obj, 
                              YES/*initialize*/, NO/*cache*/, YES/*resolver*/);
}


/***********************************************************************
* lookUpImpOrForward.
* The standard IMP lookup. 
* initialize==NO tries to avoid +initialize (but sometimes fails)
* cache==NO skips optimistic unlocked lookup (but uses cache elsewhere)
* Most callers should use initialize==YES and cache==YES.
* inst is an instance of cls or a subclass thereof, or nil if none is known. 
*   If cls is an un-initialized metaclass then a non-nil inst is faster.
* May return _objc_msgForward_impcache. IMPs destined for external use 
*   must be converted to _objc_msgForward or _objc_msgForward_stret.
*   If you don't want forwarding at all, use lookUpImpOrNil() instead.
**********************************************************************/
IMP lookUpImpOrForward(Class cls, SEL sel, id inst, 
                       bool initialize, bool cache, bool resolver)
{
    Class curClass;
    IMP imp = nil;
    Method meth;
    bool triedResolver = NO;

    runtimeLock.assertUnlocked();

    // Optimistic cache lookup
    if (cache) {
        imp = cache_getImp(cls, sel);
        if (imp) return imp;
    }

    if (!cls->isRealized()) {
        rwlock_writer_t lock(runtimeLock);
        realizeClass(cls);
    }

    if (initialize  &&  !cls->isInitialized()) {
        _class_initialize (_class_getNonMetaClass(cls, inst));
        // If sel == initialize, _class_initialize will send +initialize and 
        // then the messenger will send +initialize again after this 
        // procedure finishes. Of course, if this is not being called 
        // from the messenger then it won't happen. 2778172
    }

    // The lock is held to make method-lookup + cache-fill atomic 
    // with respect to method addition. Otherwise, a category could 
    // be added but ignored indefinitely because the cache was re-filled 
    // with the old value after the cache flush on behalf of the category.
 retry:
    runtimeLock.read();

    // Ignore GC selectors
    if (ignoreSelector(sel)) {
        imp = _objc_ignored_method;
        cache_fill(cls, sel, imp, inst);
        goto done;
    }

    // Try this class's cache.

    imp = cache_getImp(cls, sel);
    if (imp) goto done;

    // Try this class's method lists.

    meth = getMethodNoSuper_nolock(cls, sel);
    if (meth) {
        log_and_fill_cache(cls, meth->imp, sel, inst, cls);
        imp = meth->imp;
        goto done;
    }

    // Try superclass caches and method lists.

    curClass = cls;
    while ((curClass = curClass->superclass)) {
        // Superclass cache.
        imp = cache_getImp(curClass, sel);
        if (imp) {
            if (imp != (IMP)_objc_msgForward_impcache) {
                // Found the method in a superclass. Cache it in this class.
                log_and_fill_cache(cls, imp, sel, inst, curClass);
                goto done;
            }
            else {
                // Found a forward:: entry in a superclass.
                // Stop searching, but don't cache yet; call method 
                // resolver for this class first.
                break;
            }
        }

        // Superclass method list.
        meth = getMethodNoSuper_nolock(curClass, sel);
        if (meth) {
            log_and_fill_cache(cls, meth->imp, sel, inst, curClass);
            imp = meth->imp;
            goto done;
        }
    }

    // No implementation found. Try method resolver once.

    if (resolver  &&  !triedResolver) {
        runtimeLock.unlockRead();
        _class_resolveMethod(cls, sel, inst);
        // Don't cache the result; we don't hold the lock so it may have 
        // changed already. Re-do the search from scratch instead.
        triedResolver = YES;
        goto retry;
    }

    // No implementation found, and method resolver didn't help. 
    // Use forwarding.

    imp = (IMP)_objc_msgForward_impcache;
    cache_fill(cls, sel, imp, inst);

 done:
    runtimeLock.unlockRead();

    // paranoia: look for ignored selectors with non-ignored implementations
    assert(!(ignoreSelector(sel)  &&  imp != (IMP)&_objc_ignored_method));

    // paranoia: never let uncached leak out
    assert(imp != _objc_msgSend_uncached_impcache);

    return imp;
}


/***********************************************************************
* lookUpImpOrNil.
* Like lookUpImpOrForward, but returns nil instead of _objc_msgForward_impcache
**********************************************************************/
IMP lookUpImpOrNil(Class cls, SEL sel, id inst, 
                   bool initialize, bool cache, bool resolver)
{
    IMP imp = lookUpImpOrForward(cls, sel, inst, initialize, cache, resolver);
    if (imp == _objc_msgForward_impcache) return nil;
    else return imp;
}


/***********************************************************************
* lookupMethodInClassAndLoadCache.
* Like _class_lookupMethodAndLoadCache, but does not search superclasses.
* Caches and returns objc_msgForward if the method is not found in the class.
**********************************************************************/
IMP lookupMethodInClassAndLoadCache(Class cls, SEL sel)
{
    Method meth;
    IMP imp;

    // fixme this is incomplete - no resolver, +initialize, GC - 
    // but it's only used for .cxx_construct/destruct so we don't care
    assert(sel == SEL_cxx_construct  ||  sel == SEL_cxx_destruct);

    // Search cache first.
    imp = cache_getImp(cls, sel);
    if (imp) return imp;

    // Cache miss. Search method list.

    rwlock_reader_t lock(runtimeLock);

    meth = getMethodNoSuper_nolock(cls, sel);

    if (meth) {
        // Hit in method list. Cache it.
        cache_fill(cls, sel, meth->imp, nil);
        return meth->imp;
    } else {
        // Miss in method list. Cache objc_msgForward.
        cache_fill(cls, sel, _objc_msgForward_impcache, nil);
        return _objc_msgForward_impcache;
    }
}


/***********************************************************************
* class_getProperty
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
objc_property_t class_getProperty(Class cls, const char *name)
{
    if (!cls  ||  !name) return nil;

    rwlock_reader_t lock(runtimeLock);

    assert(cls->isRealized());

    for ( ; cls; cls = cls->superclass) {
        for (auto& prop : cls->data()->properties) {
            if (0 == strcmp(name, prop.name)) {
                return (objc_property_t)&prop;
            }
        }
    }
    
    return nil;
}


/***********************************************************************
* Locking: fixme
**********************************************************************/

Class gdb_class_getClass(Class cls)
{
    const char *className = cls->mangledName();
    if(!className || !strlen(className)) return Nil;
    Class rCls = look_up_class(className, NO, NO);
    return rCls;
}

Class gdb_object_getClass(id obj)
{
    if (!obj) return nil;
    return gdb_class_getClass(obj->getIsa());
}


/***********************************************************************
* Locking: write-locks runtimeLock
**********************************************************************/
void 
objc_class::setInitialized()
{
    Class metacls;
    Class cls;

    assert(!isMetaClass());

    cls = (Class)this;
    metacls = cls->ISA();

    rwlock_reader_t lock(runtimeLock);

    // Scan metaclass for custom AWZ.
    // Scan metaclass for custom RR.
    // Scan class for custom RR.
    // Also print custom RR/AWZ because we probably haven't done it yet.

    // Special cases:
    // GC's RR and AWZ are never default.
    // NSObject AWZ class methods are default.
    // NSObject RR instance methods are default.
    // updateCustomRR_AWZ() also knows these special cases.
    // attachMethodLists() also knows these special cases.

    bool inherited;
    bool metaCustomAWZ = NO;
    if (UseGC) {
        // GC is always custom AWZ
        metaCustomAWZ = YES;
        inherited = NO;
    }
    else if (MetaclassNSObjectAWZSwizzled) {
        // Somebody already swizzled NSObject's methods
        metaCustomAWZ = YES;
        inherited = NO;
    }
    else if (metacls == classNSObject()->ISA()) {
        // NSObject's metaclass AWZ is default, but we still need to check cats
        auto& methods = metacls->data()->methods;
        for (auto mlists = methods.beginCategoryMethodLists(), 
                  end = methods.endCategoryMethodLists(metacls); 
             mlists != end;
             ++mlists)
        {
            if (methodListImplementsAWZ(*mlists)) {
                metaCustomAWZ = YES;
                inherited = NO;
                break;
            }
        }
    }
    else if (metacls->superclass->hasCustomAWZ()) {
        // Superclass is custom AWZ, therefore we are too.
        metaCustomAWZ = YES;
        inherited = YES;
    } 
    else {
        // Not metaclass NSObject.
        auto& methods = metacls->data()->methods;
        for (auto mlists = methods.beginLists(),
                  end = methods.endLists(); 
             mlists != end;
             ++mlists)
        {
            if (methodListImplementsAWZ(*mlists)) {
                metaCustomAWZ = YES;
                inherited = NO;
                break;
            }
        }
    }
    if (!metaCustomAWZ) metacls->setHasDefaultAWZ();

    if (PrintCustomAWZ  &&  metaCustomAWZ) metacls->printCustomAWZ(inherited);
    // metacls->printCustomRR();


    bool clsCustomRR = NO;
    if (UseGC) {
        // GC is always custom RR
        clsCustomRR = YES;
        inherited = NO;
    }
    else if (ClassNSObjectRRSwizzled) {
        // Somebody already swizzled NSObject's methods
        clsCustomRR = YES;
        inherited = NO;
    }
    if (cls == classNSObject()) {
        // NSObject's RR is default, but we still need to check categories
        auto& methods = cls->data()->methods;
        for (auto mlists = methods.beginCategoryMethodLists(), 
                  end = methods.endCategoryMethodLists(cls); 
             mlists != end;
             ++mlists)
        {
            if (methodListImplementsRR(*mlists)) {
                clsCustomRR = YES;
                inherited = NO;
                break;
            }
        }
    }
    else if (!cls->superclass) {
        // Custom root class
        clsCustomRR = YES;
        inherited = NO;
    } 
    else if (cls->superclass->hasCustomRR()) {
        // Superclass is custom RR, therefore we are too.
        clsCustomRR = YES;
        inherited = YES;
    } 
    else {
        // Not class NSObject.
        auto& methods = cls->data()->methods;
        for (auto mlists = methods.beginLists(), 
                  end = methods.endLists(); 
             mlists != end;
             ++mlists)
        {
            if (methodListImplementsRR(*mlists)) {
                clsCustomRR = YES;
                inherited = NO;
                break;
            }
        }
    }
    if (!clsCustomRR) cls->setHasDefaultRR();

    // cls->printCustomAWZ();
    if (PrintCustomRR  &&  clsCustomRR) cls->printCustomRR(inherited);

    // Update the +initialize flags.
    // Do this last.
    metacls->changeInfo(RW_INITIALIZED, RW_INITIALIZING);
}


/***********************************************************************
 * _class_usesAutomaticRetainRelease
 * Returns YES if class was compiled with -fobjc-arc
 **********************************************************************/
BOOL _class_usesAutomaticRetainRelease(Class cls)
{
    return bool(cls->data()->ro->flags & RO_IS_ARR);
}


/***********************************************************************
* Return YES if sel is used by retain/release implementors
**********************************************************************/
static bool 
isRRSelector(SEL sel)
{
    return (sel == SEL_retain          ||  sel == SEL_release              ||  
            sel == SEL_autorelease     ||  sel == SEL_retainCount          ||  
            sel == SEL_tryRetain       ||  sel == SEL_retainWeakReference  ||  
            sel == SEL_isDeallocating  ||  sel == SEL_allowsWeakReference);
}


/***********************************************************************
* Return YES if mlist implements one of the isRRSelector() methods
**********************************************************************/
static bool 
methodListImplementsRR(const method_list_t *mlist)
{
    return (search_method_list(mlist, SEL_retain)               ||  
            search_method_list(mlist, SEL_release)              ||  
            search_method_list(mlist, SEL_autorelease)          ||  
            search_method_list(mlist, SEL_retainCount)          ||  
            search_method_list(mlist, SEL_tryRetain)            ||  
            search_method_list(mlist, SEL_isDeallocating)       ||  
            search_method_list(mlist, SEL_retainWeakReference)  ||  
            search_method_list(mlist, SEL_allowsWeakReference));
}


/***********************************************************************
* Return YES if sel is used by alloc or allocWithZone implementors
**********************************************************************/
static bool 
isAWZSelector(SEL sel)
{
    return (sel == SEL_allocWithZone  ||  sel == SEL_alloc);
}


/***********************************************************************
* Return YES if mlist implements one of the isAWZSelector() methods
**********************************************************************/
static bool 
methodListImplementsAWZ(const method_list_t *mlist)
{
    return (search_method_list(mlist, SEL_allocWithZone)  ||
            search_method_list(mlist, SEL_alloc));
}


void 
objc_class::printCustomRR(bool inherited)
{
    assert(PrintCustomRR);
    assert(hasCustomRR());
    _objc_inform("CUSTOM RR:  %s%s%s", nameForLogging(), 
                 isMetaClass() ? " (meta)" : "", 
                 inherited ? " (inherited)" : "");
}

void 
objc_class::printCustomAWZ(bool inherited)
{
    assert(PrintCustomAWZ);
    assert(hasCustomAWZ());
    _objc_inform("CUSTOM AWZ:  %s%s%s", nameForLogging(), 
                 isMetaClass() ? " (meta)" : "", 
                 inherited ? " (inherited)" : "");
}

void 
objc_class::printRequiresRawIsa(bool inherited)
{
    assert(PrintRawIsa);
    assert(requiresRawIsa());
    _objc_inform("RAW ISA:  %s%s%s", nameForLogging(), 
                 isMetaClass() ? " (meta)" : "", 
                 inherited ? " (inherited)" : "");
}


/***********************************************************************
* Mark this class and all of its subclasses as implementors or 
* inheritors of custom RR (retain/release/autorelease/retainCount)
**********************************************************************/
void objc_class::setHasCustomRR(bool inherited) 
{
    Class cls = (Class)this;
    runtimeLock.assertWriting();

    if (hasCustomRR()) return;
    
    foreach_realized_class_and_subclass(cls, ^(Class c){
        if (c != cls  &&  !c->isInitialized()) {
            // Subclass not yet initialized. Wait for setInitialized() to do it
            // fixme short circuit recursion?
            return;
        }
        if (c->hasCustomRR()) {
            // fixme short circuit recursion?
            return;
        }

        c->bits.setHasCustomRR();

        if (PrintCustomRR) c->printCustomRR(inherited  ||  c != cls);
    });
}

/***********************************************************************
* Mark this class and all of its subclasses as implementors or 
* inheritors of custom alloc/allocWithZone:
**********************************************************************/
void objc_class::setHasCustomAWZ(bool inherited) 
{
    Class cls = (Class)this;
    runtimeLock.assertWriting();

    if (hasCustomAWZ()) return;
    
    foreach_realized_class_and_subclass(cls, ^(Class c){
        if (c != cls  &&  !c->isInitialized()) {
            // Subclass not yet initialized. Wait for setInitialized() to do it
            // fixme short circuit recursion?
            return;
        }
        if (c->hasCustomAWZ()) {
            // fixme short circuit recursion?
            return;
        }

        c->bits.setHasCustomAWZ();

        if (PrintCustomAWZ) c->printCustomAWZ(inherited  ||  c != cls);
    });
}


/***********************************************************************
* Mark this class and all of its subclasses as requiring raw isa pointers
**********************************************************************/
void objc_class::setRequiresRawIsa(bool inherited) 
{
    Class cls = (Class)this;
    runtimeLock.assertWriting();

    if (requiresRawIsa()) return;
    
    foreach_realized_class_and_subclass(cls, ^(Class c){
        if (c->isInitialized()) {
            _objc_fatal("too late to require raw isa");
            return;
        }
        if (c->requiresRawIsa()) {
            // fixme short circuit recursion?
            return;
        }

        c->bits.setRequiresRawIsa();

        if (PrintRawIsa) c->printRequiresRawIsa(inherited  ||  c != cls);
    });
}


/***********************************************************************
* Update custom RR and AWZ when a method changes its IMP
**********************************************************************/
static void
updateCustomRR_AWZ(Class cls, method_t *meth)
{
    // In almost all cases, IMP swizzling does not affect custom RR/AWZ bits. 
    // Custom RR/AWZ search will already find the method whether or not 
    // it is swizzled, so it does not transition from non-custom to custom.
    // 
    // The only cases where IMP swizzling can affect the RR/AWZ bits is 
    // if the swizzled method is one of the methods that is assumed to be 
    // non-custom. These special cases are listed in setInitialized().
    // We look for such cases here.

    if (isRRSelector(meth->name)) {
        
        if ((classNSObject()->isInitialized() && 
             classNSObject()->hasCustomRR())  
            ||  
            ClassNSObjectRRSwizzled) 
        {
            // already custom, nothing would change
            return;
        }

        bool swizzlingNSObject = NO;
        if (cls == classNSObject()) {
            swizzlingNSObject = YES;
        } else {
            // Don't know the class. 
            // The only special case is class NSObject.
            for (const auto& meth2 : classNSObject()->data()->methods) {
                if (meth == &meth2) {
                    swizzlingNSObject = YES;
                    break;
                }
            }
        }
        if (swizzlingNSObject) {
            if (classNSObject()->isInitialized()) {
                classNSObject()->setHasCustomRR();
            } else {
                // NSObject not yet +initialized, so custom RR has not yet 
                // been checked, and setInitialized() will not notice the 
                // swizzle. 
                ClassNSObjectRRSwizzled = YES;
            }
        }
    }
    else if (isAWZSelector(meth->name)) {
        Class metaclassNSObject = classNSObject()->ISA();

        if ((metaclassNSObject->isInitialized() && 
             metaclassNSObject->hasCustomAWZ())  
            ||  
            MetaclassNSObjectAWZSwizzled) 
        {
            // already custom, nothing would change
            return;
        }

        bool swizzlingNSObject = NO;
        if (cls == metaclassNSObject) {
            swizzlingNSObject = YES;
        } else {
            // Don't know the class. 
            // The only special case is metaclass NSObject.
            for (const auto& meth2 : metaclassNSObject->data()->methods) {
                if (meth == &meth2) {
                    swizzlingNSObject = YES;
                    break;
                }
            }
        }
        if (swizzlingNSObject) {
            if (metaclassNSObject->isInitialized()) {
                metaclassNSObject->setHasCustomAWZ();
            } else {
                // NSObject not yet +initialized, so custom RR has not yet 
                // been checked, and setInitialized() will not notice the 
                // swizzle. 
                MetaclassNSObjectAWZSwizzled = YES;
            }
        }
    }
}


/***********************************************************************
* class_getIvarLayout
* Called by the garbage collector. 
* The class must be nil or already realized. 
* Locking: none
**********************************************************************/
const uint8_t *
class_getIvarLayout(Class cls)
{
    if (cls) return cls->data()->ro->ivarLayout;
    else return nil;
}


/***********************************************************************
* class_getWeakIvarLayout
* Called by the garbage collector. 
* The class must be nil or already realized. 
* Locking: none
**********************************************************************/
const uint8_t *
class_getWeakIvarLayout(Class cls)
{
    if (cls) return cls->data()->ro->weakIvarLayout;
    else return nil;
}


/***********************************************************************
* class_setIvarLayout
* Changes the class's GC scan layout.
* nil layout means no unscanned ivars
* The class must be under construction.
* fixme: sanity-check layout vs instance size?
* fixme: sanity-check layout vs superclass?
* Locking: acquires runtimeLock
**********************************************************************/
void
class_setIvarLayout(Class cls, const uint8_t *layout)
{
    if (!cls) return;

    rwlock_writer_t lock(runtimeLock);
    
    // Can only change layout of in-construction classes.
    // note: if modifications to post-construction classes were 
    //   allowed, there would be a race below (us vs. concurrent GC scan)
    if (!(cls->data()->flags & RW_CONSTRUCTING)) {
        _objc_inform("*** Can't set ivar layout for already-registered "
                     "class '%s'", cls->nameForLogging());
        return;
    }

    class_ro_t *ro_w = make_ro_writeable(cls->data());

    try_free(ro_w->ivarLayout);
    ro_w->ivarLayout = ustrdupMaybeNil(layout);
}

// SPI:  Instance-specific object layout.

void
_class_setIvarLayoutAccessor(Class cls, const uint8_t* (*accessor) (id object)) {
    if (!cls) return;

    rwlock_writer_t lock(runtimeLock);

    class_ro_t *ro_w = make_ro_writeable(cls->data());

    // FIXME:  this really isn't safe to free if there are instances of this class already.
    if (!(cls->data()->flags & RW_HAS_INSTANCE_SPECIFIC_LAYOUT)) try_free(ro_w->ivarLayout);
    ro_w->ivarLayout = (uint8_t *)accessor;
    cls->setInfo(RW_HAS_INSTANCE_SPECIFIC_LAYOUT);
}

const uint8_t *
_object_getIvarLayout(Class cls, id object) 
{
    if (cls) {
        const uint8_t* layout = cls->data()->ro->ivarLayout;
        if (cls->data()->flags & RW_HAS_INSTANCE_SPECIFIC_LAYOUT) {
            const uint8_t* (*accessor) (id object) = (const uint8_t* (*)(id))layout;
            layout = accessor(object);
        }
        return layout;
    }
    return nil;
}

/***********************************************************************
* class_setWeakIvarLayout
* Changes the class's GC weak layout.
* nil layout means no weak ivars
* The class must be under construction.
* fixme: sanity-check layout vs instance size?
* fixme: sanity-check layout vs superclass?
* Locking: acquires runtimeLock
**********************************************************************/
void
class_setWeakIvarLayout(Class cls, const uint8_t *layout)
{
    if (!cls) return;

    rwlock_writer_t lock(runtimeLock);
    
    // Can only change layout of in-construction classes.
    // note: if modifications to post-construction classes were 
    //   allowed, there would be a race below (us vs. concurrent GC scan)
    if (!(cls->data()->flags & RW_CONSTRUCTING)) {
        _objc_inform("*** Can't set weak ivar layout for already-registered "
                     "class '%s'", cls->nameForLogging());
        return;
    }

    class_ro_t *ro_w = make_ro_writeable(cls->data());

    try_free(ro_w->weakIvarLayout);
    ro_w->weakIvarLayout = ustrdupMaybeNil(layout);
}


/***********************************************************************
* _class_getVariable
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
Ivar 
_class_getVariable(Class cls, const char *name, Class *memberOf)
{
    rwlock_reader_t lock(runtimeLock);

    for ( ; cls; cls = cls->superclass) {
        ivar_t *ivar = getIvar(cls, name);
        if (ivar) {
            if (memberOf) *memberOf = cls;
            return ivar;
        }
    }

    return nil;
}


/***********************************************************************
* class_conformsToProtocol
* fixme
* Locking: read-locks runtimeLock
**********************************************************************/
BOOL class_conformsToProtocol(Class cls, Protocol *proto_gen)
{
    protocol_t *proto = newprotocol(proto_gen);
    
    if (!cls) return NO;
    if (!proto_gen) return NO;

    rwlock_reader_t lock(runtimeLock);

    assert(cls->isRealized());

    for (const auto& proto_ref : cls->data()->protocols) {
        protocol_t *p = remapProtocol(proto_ref);
        if (p == proto || protocol_conformsToProtocol_nolock(p, proto)) {
            return YES;
        }
    }

    return NO;
}


/**********************************************************************
* addMethod
* fixme
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static IMP 
addMethod(Class cls, SEL name, IMP imp, const char *types, bool replace)
{
    IMP result = nil;

    runtimeLock.assertWriting();

    assert(types);
    assert(cls->isRealized());

    method_t *m;
    if ((m = getMethodNoSuper_nolock(cls, name))) {
        // already exists
        if (!replace) {
            result = m->imp;
        } else {
            result = _method_setImplementation(cls, m, imp);
        }
    } else {
        // fixme optimize
        method_list_t *newlist;
        newlist = (method_list_t *)calloc(sizeof(*newlist), 1);
        newlist->entsizeAndFlags = 
            (uint32_t)sizeof(method_t) | fixed_up_method_list;
        newlist->count = 1;
        newlist->first.name = name;
        newlist->first.types = strdup(types);
        if (!ignoreSelector(name)) {
            newlist->first.imp = imp;
        } else {
            newlist->first.imp = (IMP)&_objc_ignored_method;
        }

        prepareMethodLists(cls, &newlist, 1, NO, NO);
        cls->data()->methods.attachLists(&newlist, 1);
        flushCaches(cls);

        result = nil;
    }

    return result;
}


BOOL 
class_addMethod(Class cls, SEL name, IMP imp, const char *types)
{
    if (!cls) return NO;

    rwlock_writer_t lock(runtimeLock);
    return ! addMethod(cls, name, imp, types ?: "", NO);
}


IMP 
class_replaceMethod(Class cls, SEL name, IMP imp, const char *types)
{
    if (!cls) return nil;

    rwlock_writer_t lock(runtimeLock);
    return addMethod(cls, name, imp, types ?: "", YES);
}


/***********************************************************************
* class_addIvar
* Adds an ivar to a class.
* Locking: acquires runtimeLock
**********************************************************************/
BOOL 
class_addIvar(Class cls, const char *name, size_t size, 
              uint8_t alignment, const char *type)
{
    if (!cls) return NO;

    if (!type) type = "";
    if (name  &&  0 == strcmp(name, "")) name = nil;

    rwlock_writer_t lock(runtimeLock);

    assert(cls->isRealized());

    // No class variables
    if (cls->isMetaClass()) {
        return NO;
    }

    // Can only add ivars to in-construction classes.
    if (!(cls->data()->flags & RW_CONSTRUCTING)) {
        return NO;
    }

    // Check for existing ivar with this name, unless it's anonymous.
    // Check for too-big ivar.
    // fixme check for superclass ivar too?
    if ((name  &&  getIvar(cls, name))  ||  size > UINT32_MAX) {
        return NO;
    }

    class_ro_t *ro_w = make_ro_writeable(cls->data());

    // fixme allocate less memory here
    
    ivar_list_t *oldlist, *newlist;
    if ((oldlist = (ivar_list_t *)cls->data()->ro->ivars)) {
        size_t oldsize = oldlist->byteSize();
        newlist = (ivar_list_t *)calloc(oldsize + oldlist->entsize(), 1);
        memcpy(newlist, oldlist, oldsize);
        free(oldlist);
    } else {
        newlist = (ivar_list_t *)calloc(sizeof(ivar_list_t), 1);
        newlist->entsizeAndFlags = (uint32_t)sizeof(ivar_t);
    }

    uint32_t offset = cls->unalignedInstanceSize();
    uint32_t alignMask = (1<<alignment)-1;
    offset = (offset + alignMask) & ~alignMask;

    ivar_t& ivar = newlist->get(newlist->count++);
#if __x86_64__
    // Deliberately over-allocate the ivar offset variable. 
    // Use calloc() to clear all 64 bits. See the note in struct ivar_t.
    ivar.offset = (int32_t *)(int64_t *)calloc(sizeof(int64_t), 1);
#else
    ivar.offset = (int32_t *)malloc(sizeof(int32_t));
#endif
    *ivar.offset = offset;
    ivar.name = name ? strdup(name) : nil;
    ivar.type = strdup(type);
    ivar.alignment_raw = alignment;
    ivar.size = (uint32_t)size;

    ro_w->ivars = newlist;
    cls->setInstanceSize((uint32_t)(offset + size));

    // Ivar layout updated in registerClass.

    return YES;
}


/***********************************************************************
* class_addProtocol
* Adds a protocol to a class.
* Locking: acquires runtimeLock
**********************************************************************/
BOOL class_addProtocol(Class cls, Protocol *protocol_gen)
{
    protocol_t *protocol = newprotocol(protocol_gen);

    if (!cls) return NO;
    if (class_conformsToProtocol(cls, protocol_gen)) return NO;

    rwlock_writer_t lock(runtimeLock);

    assert(cls->isRealized());
    
    // fixme optimize
    protocol_list_t *protolist = (protocol_list_t *)
        malloc(sizeof(protocol_list_t) + sizeof(protocol_t *));
    protolist->count = 1;
    protolist->list[0] = (protocol_ref_t)protocol;

    cls->data()->protocols.attachLists(&protolist, 1);

    // fixme metaclass?

    return YES;
}


/***********************************************************************
* class_addProperty
* Adds a property to a class.
* Locking: acquires runtimeLock
**********************************************************************/
static bool 
_class_addProperty(Class cls, const char *name, 
                   const objc_property_attribute_t *attrs, unsigned int count, 
                   bool replace)
{
    if (!cls) return NO;
    if (!name) return NO;

    property_t *prop = class_getProperty(cls, name);
    if (prop  &&  !replace) {
        // already exists, refuse to replace
        return NO;
    } 
    else if (prop) {
        // replace existing
        rwlock_writer_t lock(runtimeLock);
        try_free(prop->attributes);
        prop->attributes = copyPropertyAttributeString(attrs, count);
        return YES;
    }
    else {
        rwlock_writer_t lock(runtimeLock);
        
        assert(cls->isRealized());
        
        property_list_t *proplist = (property_list_t *)
            malloc(sizeof(*proplist));
        proplist->count = 1;
        proplist->entsizeAndFlags = sizeof(proplist->first);
        proplist->first.name = strdup(name);
        proplist->first.attributes = copyPropertyAttributeString(attrs, count);
        
        cls->data()->properties.attachLists(&proplist, 1);
        
        return YES;
    }
}

BOOL 
class_addProperty(Class cls, const char *name, 
                  const objc_property_attribute_t *attrs, unsigned int n)
{
    return _class_addProperty(cls, name, attrs, n, NO);
}

void 
class_replaceProperty(Class cls, const char *name, 
                      const objc_property_attribute_t *attrs, unsigned int n)
{
    _class_addProperty(cls, name, attrs, n, YES);
}


/***********************************************************************
* look_up_class
* Look up a class by name, and realize it.
* Locking: acquires runtimeLock
**********************************************************************/
Class 
look_up_class(const char *name, 
              bool includeUnconnected __attribute__((unused)), 
              bool includeClassHandler __attribute__((unused)))
{
    if (!name) return nil;

    Class result;
    bool unrealized;
    {
        rwlock_reader_t lock(runtimeLock);
        result = getClass(name);
        unrealized = result  &&  !result->isRealized();
    }
    if (unrealized) {
        rwlock_writer_t lock(runtimeLock);
        realizeClass(result);
    }
    return result;
}


/***********************************************************************
* objc_duplicateClass
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
Class 
objc_duplicateClass(Class original, const char *name, 
                    size_t extraBytes)
{
    Class duplicate;

    rwlock_writer_t lock(runtimeLock);

    assert(original->isRealized());
    assert(!original->isMetaClass());

    duplicate = alloc_class_for_subclass(original, extraBytes);

    duplicate->initClassIsa(original->ISA());
    duplicate->superclass = original->superclass;

    duplicate->cache.initializeToEmpty();

    class_rw_t *rw = (class_rw_t *)calloc(sizeof(*original->data()), 1);
    rw->flags = (original->data()->flags | RW_COPIED_RO | RW_REALIZING);
    rw->version = original->data()->version;
    rw->firstSubclass = nil;
    rw->nextSiblingClass = nil;

    duplicate->bits = original->bits;
    duplicate->setData(rw);

    rw->ro = (class_ro_t *)
        memdup(original->data()->ro, sizeof(*original->data()->ro));
    *(char **)&rw->ro->name = strdup(name);

    rw->methods = original->data()->methods.duplicate();

    // fixme dies when categories are added to the base
    rw->properties = original->data()->properties;
    rw->protocols = original->data()->protocols;

    if (duplicate->superclass) {
        addSubclass(duplicate->superclass, duplicate);
    }

    // Don't methodize class - construction above is correct

    addNamedClass(duplicate, duplicate->data()->ro->name);
    addRealizedClass(duplicate);
    // no: duplicate->ISA == original->ISA
    // addRealizedMetaclass(duplicate->ISA);

    if (PrintConnecting) {
        _objc_inform("CLASS: realizing class '%s' (duplicate of %s) %p %p", 
                     name, original->nameForLogging(), 
                     (void*)duplicate, duplicate->data()->ro);
    }

    duplicate->clearInfo(RW_REALIZING);

    return duplicate;
}

/***********************************************************************
* objc_initializeClassPair
* Locking: runtimeLock must be write-locked by the caller
**********************************************************************/

// &UnsetLayout is the default ivar layout during class construction
static const uint8_t UnsetLayout = 0;

static void objc_initializeClassPair_internal(Class superclass, const char *name, Class cls, Class meta)
{
    runtimeLock.assertWriting();

    class_ro_t *cls_ro_w, *meta_ro_w;

    cls->cache.initializeToEmpty();
    meta->cache.initializeToEmpty();
    
    cls->setData((class_rw_t *)calloc(sizeof(class_rw_t), 1));
    meta->setData((class_rw_t *)calloc(sizeof(class_rw_t), 1));
    cls_ro_w   = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
    meta_ro_w  = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
    cls->data()->ro = cls_ro_w;
    meta->data()->ro = meta_ro_w;

    // Set basic info

    cls->data()->flags = RW_CONSTRUCTING | RW_COPIED_RO | RW_REALIZED | RW_REALIZING;
    meta->data()->flags = RW_CONSTRUCTING | RW_COPIED_RO | RW_REALIZED | RW_REALIZING;
    cls->data()->version = 0;
    meta->data()->version = 7;

    cls_ro_w->flags = 0;
    meta_ro_w->flags = RO_META;
    if (!superclass) {
        cls_ro_w->flags |= RO_ROOT;
        meta_ro_w->flags |= RO_ROOT;
    }
    if (superclass) {
        cls_ro_w->instanceStart = superclass->unalignedInstanceSize();
        meta_ro_w->instanceStart = superclass->ISA()->unalignedInstanceSize();
        cls->setInstanceSize(cls_ro_w->instanceStart);
        meta->setInstanceSize(meta_ro_w->instanceStart);
    } else {
        cls_ro_w->instanceStart = 0;
        meta_ro_w->instanceStart = (uint32_t)sizeof(objc_class);
        cls->setInstanceSize((uint32_t)sizeof(id));  // just an isa
        meta->setInstanceSize(meta_ro_w->instanceStart);
    }

    cls_ro_w->name = strdup(name);
    meta_ro_w->name = strdup(name);

    cls_ro_w->ivarLayout = &UnsetLayout;
    cls_ro_w->weakIvarLayout = &UnsetLayout;

    // Connect to superclasses and metaclasses
    cls->initClassIsa(meta);
    if (superclass) {
        meta->initClassIsa(superclass->ISA()->ISA());
        cls->superclass = superclass;
        meta->superclass = superclass->ISA();
        addSubclass(superclass, cls);
        addSubclass(superclass->ISA(), meta);
    } else {
        meta->initClassIsa(meta);
        cls->superclass = Nil;
        meta->superclass = cls;
        addSubclass(cls, meta);
    }
}


/***********************************************************************
* verifySuperclass
* Sanity-check the superclass provided to 
* objc_allocateClassPair, objc_initializeClassPair, or objc_readClassPair.
**********************************************************************/
bool
verifySuperclass(Class superclass, bool rootOK)
{
    if (!superclass) {
        // Superclass does not exist.
        // If subclass may be a root class, this is OK.
        // If subclass must not be a root class, this is bad.
        return rootOK;
    }

    // Superclass must be realized.
    if (! superclass->isRealized()) return false;

    // Superclass must not be under construction.
    if (superclass->data()->flags & RW_CONSTRUCTING) return false;

    return true;
}


/***********************************************************************
* objc_initializeClassPair
**********************************************************************/
Class objc_initializeClassPair(Class superclass, const char *name, Class cls, Class meta)
{
    rwlock_writer_t lock(runtimeLock);

    // Fail if the class name is in use.
    // Fail if the superclass isn't kosher.
    if (getClass(name)  ||  !verifySuperclass(superclass, true/*rootOK*/)) {
        return nil;
    }

    objc_initializeClassPair_internal(superclass, name, cls, meta);

    return cls;
}


/***********************************************************************
* objc_allocateClassPair
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
Class objc_allocateClassPair(Class superclass, const char *name, 
                             size_t extraBytes)
{
    Class cls, meta;

    rwlock_writer_t lock(runtimeLock);

    // Fail if the class name is in use.
    // Fail if the superclass isn't kosher.
    if (getClass(name)  ||  !verifySuperclass(superclass, true/*rootOK*/)) {
        return nil;
    }

    // Allocate new classes.
    cls  = alloc_class_for_subclass(superclass, extraBytes);
    meta = alloc_class_for_subclass(superclass, extraBytes);

    // fixme mangle the name if it looks swift-y?
    objc_initializeClassPair_internal(superclass, name, cls, meta);

    return cls;
}


/***********************************************************************
* objc_registerClassPair
* fixme
* Locking: acquires runtimeLock
**********************************************************************/
void objc_registerClassPair(Class cls)
{
    rwlock_writer_t lock(runtimeLock);

    if ((cls->data()->flags & RW_CONSTRUCTED)  ||  
        (cls->ISA()->data()->flags & RW_CONSTRUCTED)) 
    {
        _objc_inform("objc_registerClassPair: class '%s' was already "
                     "registered!", cls->data()->ro->name);
        return;
    }

    if (!(cls->data()->flags & RW_CONSTRUCTING)  ||  
        !(cls->ISA()->data()->flags & RW_CONSTRUCTING))
    {
        _objc_inform("objc_registerClassPair: class '%s' was not "
                     "allocated with objc_allocateClassPair!", 
                     cls->data()->ro->name);
        return;
    }

    // Build ivar layouts
    if (UseGC) {
        Class supercls = cls->superclass;
        class_ro_t *ro_w = (class_ro_t *)cls->data()->ro;

        if (ro_w->ivarLayout != &UnsetLayout) {
            // Class builder already called class_setIvarLayout.
        }
        else if (!supercls) {
            // Root class. Scan conservatively (should be isa ivar only).
            ro_w->ivarLayout = nil;
        }
        else if (ro_w->ivars == nil) {
            // No local ivars. Use superclass's layouts.
            ro_w->ivarLayout = 
                ustrdupMaybeNil(supercls->data()->ro->ivarLayout);
        }
        else {
            // Has local ivars. Build layouts based on superclass.
            layout_bitmap bitmap = 
                layout_bitmap_create(supercls->data()->ro->ivarLayout, 
                                     supercls->unalignedInstanceSize(), 
                                     cls->unalignedInstanceSize(), NO);
            for (const auto& ivar : *ro_w->ivars) {
                if (!ivar.offset) continue;  // anonymous bitfield

                layout_bitmap_set_ivar(bitmap, ivar.type, *ivar.offset);
            }
            ro_w->ivarLayout = layout_string_create(bitmap);
            layout_bitmap_free(bitmap);
        }

        if (ro_w->weakIvarLayout != &UnsetLayout) {
            // Class builder already called class_setWeakIvarLayout.
        }
        else if (!supercls) {
            // Root class. No weak ivars (should be isa ivar only).
            ro_w->weakIvarLayout = nil;
        }
        else if (ro_w->ivars == nil) {
            // No local ivars. Use superclass's layout.
            ro_w->weakIvarLayout = 
                ustrdupMaybeNil(supercls->data()->ro->weakIvarLayout);
        }
        else {
            // Has local ivars. Build layout based on superclass.
            // No way to add weak ivars yet.
            ro_w->weakIvarLayout = 
                ustrdupMaybeNil(supercls->data()->ro->weakIvarLayout);
        }
    }

    // Clear "under construction" bit, set "done constructing" bit
    cls->ISA()->changeInfo(RW_CONSTRUCTED, RW_CONSTRUCTING | RW_REALIZING);
    cls->changeInfo(RW_CONSTRUCTED, RW_CONSTRUCTING | RW_REALIZING);

    // Add to named and realized classes
    addNamedClass(cls, cls->data()->ro->name);
    addRealizedClass(cls);
    addRealizedMetaclass(cls->ISA());
}


/***********************************************************************
* objc_readClassPair()
* Read a class and metaclass as written by a compiler.
* Assumes the class and metaclass are not referenced by other things 
* that might need to be fixed up (such as categories and subclasses).
* Does not call +load.
* Returns the class pointer, or nil.
*
* Locking: runtimeLock acquired by map_images
**********************************************************************/
Class objc_readClassPair(Class bits, const struct objc_image_info *info)
{
    rwlock_writer_t lock(runtimeLock);

    // No info bits are significant yet.
    (void)info;

    // Fail if the class name is in use.
    // Fail if the superclass isn't kosher.
    const char *name = bits->mangledName();
    bool rootOK = bits->data()->flags & RO_ROOT;
    if (getClass(name) || !verifySuperclass(bits->superclass, rootOK)){
        return nil;
    }

    Class cls = readClass(bits, false/*bundle*/, false/*shared cache*/);
    if (cls != bits) {
        // This function isn't allowed to remap anything.
        _objc_fatal("objc_readClassPair for class %s changed %p to %p", 
                    cls->nameForLogging(), bits, cls);
    }
    realizeClass(cls);

    return cls;
}


/***********************************************************************
* detach_class
* Disconnect a class from other data structures.
* Exception: does not remove the class from the +load list
* Call this before free_class.
* Locking: runtimeLock must be held by the caller.
**********************************************************************/
static void detach_class(Class cls, bool isMeta)
{
    runtimeLock.assertWriting();

    // categories not yet attached to this class
    removeAllUnattachedCategoriesForClass(cls);

    // superclass's subclass list
    if (cls->isRealized()) {
        Class supercls = cls->superclass;
        if (supercls) {
            removeSubclass(supercls, cls);
        }
    }

    // class tables and +load queue
    if (!isMeta) {
        removeNamedClass(cls, cls->mangledName());
        removeRealizedClass(cls);
    } else {
        removeRealizedMetaclass(cls);
    }
}


/***********************************************************************
* free_class
* Frees a class's data structures.
* Call this after detach_class.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void free_class(Class cls)
{
    runtimeLock.assertWriting();

    if (! cls->isRealized()) return;

    auto rw = cls->data();
    auto ro = rw->ro;

    cache_delete(cls);
    
    for (auto& meth : rw->methods) {
        try_free(meth.types);
    }
    rw->methods.tryFree();
    
    const ivar_list_t *ivars = ro->ivars;
    if (ivars) {
        for (auto& ivar : *ivars) {
            try_free(ivar.offset);
            try_free(ivar.name);
            try_free(ivar.type);
        }
        try_free(ivars);
    }

    for (auto& prop : rw->properties) {
        try_free(prop.name);
        try_free(prop.attributes);
    }
    rw->properties.tryFree();

    rw->protocols.tryFree();
    
    try_free(ro->ivarLayout);
    try_free(ro->weakIvarLayout);
    try_free(ro->name);
    try_free(ro);
    try_free(rw);
    try_free(cls);
}


void objc_disposeClassPair(Class cls)
{
    rwlock_writer_t lock(runtimeLock);

    if (!(cls->data()->flags & (RW_CONSTRUCTED|RW_CONSTRUCTING))  ||  
        !(cls->ISA()->data()->flags & (RW_CONSTRUCTED|RW_CONSTRUCTING))) 
    {
        // class not allocated with objc_allocateClassPair
        // disposing still-unregistered class is OK!
        _objc_inform("objc_disposeClassPair: class '%s' was not "
                     "allocated with objc_allocateClassPair!", 
                     cls->data()->ro->name);
        return;
    }

    if (cls->isMetaClass()) {
        _objc_inform("objc_disposeClassPair: class '%s' is a metaclass, "
                     "not a class!", cls->data()->ro->name);
        return;
    }

    // Shouldn't have any live subclasses.
    if (cls->data()->firstSubclass) {
        _objc_inform("objc_disposeClassPair: class '%s' still has subclasses, "
                     "including '%s'!", cls->data()->ro->name, 
                     cls->data()->firstSubclass->nameForLogging());
    }
    if (cls->ISA()->data()->firstSubclass) {
        _objc_inform("objc_disposeClassPair: class '%s' still has subclasses, "
                     "including '%s'!", cls->data()->ro->name, 
                     cls->ISA()->data()->firstSubclass->nameForLogging());
    }

    // don't remove_class_from_loadable_list() 
    // - it's not there and we don't have the lock
    detach_class(cls->ISA(), YES);
    detach_class(cls, NO);
    free_class(cls->ISA());
    free_class(cls);
}


/***********************************************************************
* objc_constructInstance
* Creates an instance of `cls` at the location pointed to by `bytes`. 
* `bytes` must point to at least class_getInstanceSize(cls) bytes of 
*   well-aligned zero-filled memory.
* The new object's isa is set. Any C++ constructors are called.
* Returns `bytes` if successful. Returns nil if `cls` or `bytes` is 
*   nil, or if C++ constructors fail.
* Note: class_createInstance() and class_createInstances() preflight this.
**********************************************************************/
id 
objc_constructInstance(Class cls, void *bytes) 
{
    if (!cls  ||  !bytes) return nil;

    id obj = (id)bytes;

    // Read class's info bits all at once for performance
    bool hasCxxCtor = cls->hasCxxCtor();
    bool hasCxxDtor = cls->hasCxxDtor();
    bool fast = cls->canAllocIndexed();
    
    if (!UseGC  &&  fast) {
        obj->initInstanceIsa(cls, hasCxxDtor);
    } else {
        obj->initIsa(cls);
    }

    if (hasCxxCtor) {
        return object_cxxConstructFromClass(obj, cls);
    } else {
        return obj;
    }
}


/***********************************************************************
* class_createInstance
* fixme
* Locking: none
**********************************************************************/

static __attribute__((always_inline)) 
id
_class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone, 
                              bool cxxConstruct = true, 
                              size_t *outAllocatedSize = nil)
{
    if (!cls) return nil;

    assert(cls->isRealized());

    // Read class's info bits all at once for performance
    bool hasCxxCtor = cls->hasCxxCtor();
    bool hasCxxDtor = cls->hasCxxDtor();
    bool fast = cls->canAllocIndexed();

    size_t size = cls->instanceSize(extraBytes);
    if (outAllocatedSize) *outAllocatedSize = size;

    id obj;
    if (!UseGC  &&  !zone  &&  fast) {
        obj = (id)calloc(1, size);
        if (!obj) return nil;
        obj->initInstanceIsa(cls, hasCxxDtor);
    } 
    else {
#if SUPPORT_GC
        if (UseGC) {
            obj = (id)auto_zone_allocate_object(gc_zone, size,
                                                AUTO_OBJECT_SCANNED, 0, 1);
        } else 
#endif
        if (zone) {
            obj = (id)malloc_zone_calloc ((malloc_zone_t *)zone, 1, size);
        } else {
            obj = (id)calloc(1, size);
        }
        if (!obj) return nil;

        // Use non-indexed isa on the assumption that they might be 
        // doing something weird with the zone or RR.
        obj->initIsa(cls);
    }

    if (cxxConstruct && hasCxxCtor) {
        obj = _objc_constructOrFree(obj, cls);
    }

    return obj;
}


id 
class_createInstance(Class cls, size_t extraBytes)
{
    return _class_createInstanceFromZone(cls, extraBytes, nil);
}


/***********************************************************************
* class_createInstances
* fixme
* Locking: none
**********************************************************************/
#if SUPPORT_NONPOINTER_ISA
#warning fixme optimize class_createInstances
#endif
unsigned 
class_createInstances(Class cls, size_t extraBytes, 
                      id *results, unsigned num_requested)
{
    return _class_createInstancesFromZone(cls, extraBytes, nil, 
                                          results, num_requested);
}

static bool classOrSuperClassesUseARR(Class cls) {
    while (cls) {
        if (_class_usesAutomaticRetainRelease(cls)) return true;
        cls = cls->superclass;
    }
    return false;
}

static void arr_fixup_copied_references(id newObject, id oldObject)
{
    // use ARR layouts to correctly copy the references from old object to new, both strong and weak.
    Class cls = oldObject->ISA();
    for ( ; cls; cls = cls->superclass) {
        if (_class_usesAutomaticRetainRelease(cls)) {
            // FIXME:  align the instance start to nearest id boundary. This currently handles the case where
            // the the compiler folds a leading BOOL (char, short, etc.) into the alignment slop of a superclass.
            size_t instanceStart = _class_getInstanceStart(cls);
            const uint8_t *strongLayout = class_getIvarLayout(cls);
            if (strongLayout) {
                id *newPtr = (id *)((char*)newObject + instanceStart);
                unsigned char byte;
                while ((byte = *strongLayout++)) {
                    unsigned skips = (byte >> 4);
                    unsigned scans = (byte & 0x0F);
                    newPtr += skips;
                    while (scans--) {
                        // ensure strong references are properly retained.
                        id value = *newPtr++;
                        if (value) objc_retain(value);
                    }
                }
            }
            const uint8_t *weakLayout = class_getWeakIvarLayout(cls);
            // fix up weak references if any.
            if (weakLayout) {
                id *newPtr = (id *)((char*)newObject + instanceStart), *oldPtr = (id *)((char*)oldObject + instanceStart);
                unsigned char byte;
                while ((byte = *weakLayout++)) {
                    unsigned skips = (byte >> 4);
                    unsigned weaks = (byte & 0x0F);
                    newPtr += skips, oldPtr += skips;
                    while (weaks--) {
                        *newPtr = nil;
                        objc_storeWeak(newPtr, objc_loadWeak(oldPtr));
                        ++newPtr, ++oldPtr;
                    }
                }
            }
        }
    }
}

/***********************************************************************
* object_copyFromZone
* fixme
* Locking: none
**********************************************************************/
static id 
_object_copyFromZone(id oldObj, size_t extraBytes, void *zone)
{
    if (!oldObj) return nil;
    if (oldObj->isTaggedPointer()) return oldObj;

    // fixme this doesn't handle C++ ivars correctly (#4619414)

    Class cls = oldObj->ISA();
    size_t size;
    id obj = _class_createInstanceFromZone(cls, extraBytes, zone, false, &size);
    if (!obj) return nil;

    // Copy everything except the isa, which was already set above.
    uint8_t *copyDst = (uint8_t *)obj + sizeof(Class);
    uint8_t *copySrc = (uint8_t *)oldObj + sizeof(Class);
    size_t copySize = size - sizeof(Class);
#if SUPPORT_GC
    objc_memmove_collectable(copyDst, copySrc, copySize);
#else
    memmove(copyDst, copySrc, copySize);
#endif

#if SUPPORT_GC
    if (UseGC)
        gc_fixup_weakreferences(obj, oldObj);
    else
#endif
    if (classOrSuperClassesUseARR(cls))
        arr_fixup_copied_references(obj, oldObj);

    return obj;
}


/***********************************************************************
* object_copy
* fixme
* Locking: none
**********************************************************************/
id 
object_copy(id oldObj, size_t extraBytes)
{
    return _object_copyFromZone(oldObj, extraBytes, malloc_default_zone());
}


#if !(TARGET_OS_EMBEDDED  ||  TARGET_OS_IPHONE)

/***********************************************************************
* class_createInstanceFromZone
* fixme
* Locking: none
**********************************************************************/
id
class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone)
{
    return _class_createInstanceFromZone(cls, extraBytes, zone);
}

/***********************************************************************
* object_copyFromZone
* fixme
* Locking: none
**********************************************************************/
id 
object_copyFromZone(id oldObj, size_t extraBytes, void *zone)
{
    return _object_copyFromZone(oldObj, extraBytes, zone);
}

#endif


/***********************************************************************
* objc_destructInstance
* Destroys an instance without freeing memory. 
* Calls C++ destructors.
* Calls ARR ivar cleanup.
* Removes associative references.
* Returns `obj`. Does nothing if `obj` is nil.
* Be warned that GC DOES NOT CALL THIS. If you edit this, also edit finalize.
* CoreFoundation and other clients do call this under GC.
**********************************************************************/
void *objc_destructInstance(id obj) 
{
    if (obj) {
        // Read all of the flags at once for performance.
        bool cxx = obj->hasCxxDtor();
        bool assoc = !UseGC && obj->hasAssociatedObjects();
        bool dealloc = !UseGC;

        // This order is important.
        if (cxx) object_cxxDestruct(obj);
        if (assoc) _object_remove_assocations(obj);
        if (dealloc) obj->clearDeallocating();
    }

    return obj;
}


/***********************************************************************
* object_dispose
* fixme
* Locking: none
**********************************************************************/
id 
object_dispose(id obj)
{
    if (!obj) return nil;

    objc_destructInstance(obj);
    
#if SUPPORT_GC
    if (UseGC) {
        auto_zone_retain(gc_zone, obj); // gc free expects rc==1
    }
#endif

    free(obj);

    return nil;
}


/***********************************************************************
* _objc_getFreedObjectClass
* fixme
* Locking: none
**********************************************************************/
Class _objc_getFreedObjectClass (void)
{
    return nil;
}



/***********************************************************************
* Tagged pointer objects.
*
* Tagged pointer objects store the class and the object value in the 
* object pointer; the "pointer" does not actually point to anything.
* 
* Tagged pointer objects currently use this representation:
* (LSB)
*  1 bit   set if tagged, clear if ordinary object pointer
*  3 bits  tag index
* 60 bits  payload
* (MSB)
* The tag index defines the object's class. 
* The payload format is defined by the object's class.
*
* This representation is subject to change. Representation-agnostic SPI is:
* objc-internal.h for class implementers.
* objc-gdb.h for debuggers.
**********************************************************************/
#if !SUPPORT_TAGGED_POINTERS

// These variables are always provided for debuggers.
uintptr_t objc_debug_taggedpointer_mask = 0;
unsigned  objc_debug_taggedpointer_slot_shift = 0;
uintptr_t objc_debug_taggedpointer_slot_mask = 0;
unsigned  objc_debug_taggedpointer_payload_lshift = 0;
unsigned  objc_debug_taggedpointer_payload_rshift = 0;
Class objc_debug_taggedpointer_classes[1] = { nil };

static void
disableTaggedPointers() { }

#else

// The "slot" used in the class table and given to the debugger 
// includes the is-tagged bit. This makes objc_msgSend faster.

uintptr_t objc_debug_taggedpointer_mask = TAG_MASK;
unsigned  objc_debug_taggedpointer_slot_shift = TAG_SLOT_SHIFT;
uintptr_t objc_debug_taggedpointer_slot_mask = TAG_SLOT_MASK;
unsigned  objc_debug_taggedpointer_payload_lshift = TAG_PAYLOAD_LSHIFT;
unsigned  objc_debug_taggedpointer_payload_rshift = TAG_PAYLOAD_RSHIFT;
// objc_debug_taggedpointer_classes is defined in objc-msg-*.s

static void
disableTaggedPointers()
{
    objc_debug_taggedpointer_mask = 0;
    objc_debug_taggedpointer_slot_shift = 0;
    objc_debug_taggedpointer_slot_mask = 0;
    objc_debug_taggedpointer_payload_lshift = 0;
    objc_debug_taggedpointer_payload_rshift = 0;
}

static int 
tagSlotForTagIndex(objc_tag_index_t tag)
{
#if SUPPORT_MSB_TAGGED_POINTERS
    return 0x8 | tag;
#else
    return (tag << 1) | 1;
#endif
}


/***********************************************************************
* _objc_registerTaggedPointerClass
* Set the class to use for the given tagged pointer index.
* Aborts if the tag is out of range, or if the tag is already 
* used by some other class.
**********************************************************************/
void
_objc_registerTaggedPointerClass(objc_tag_index_t tag, Class cls)
{    
    if (objc_debug_taggedpointer_mask == 0) {
        _objc_fatal("tagged pointers are disabled");
    }

    if ((unsigned int)tag >= TAG_COUNT) {
        _objc_fatal("tag index %u is too large.", tag);
    }

    int slot = tagSlotForTagIndex(tag);
    Class oldCls = objc_tag_classes[slot];
    
    if (cls  &&  oldCls  &&  cls != oldCls) {
        _objc_fatal("tag index %u used for two different classes "
                    "(was %p %s, now %p %s)", tag, 
                    oldCls, oldCls->nameForLogging(), 
                    cls, cls->nameForLogging());
    }

    objc_tag_classes[slot] = cls;
}


// Deprecated name.
void _objc_insert_tagged_isa(unsigned char slotNumber, Class isa) 
{
    return _objc_registerTaggedPointerClass((objc_tag_index_t)slotNumber, isa);
}


/***********************************************************************
* _objc_getClassForTag
* Returns the class that is using the given tagged pointer tag.
* Returns nil if no class is using that tag or the tag is out of range.
**********************************************************************/
Class
_objc_getClassForTag(objc_tag_index_t tag)
{
    if ((unsigned int)tag >= TAG_COUNT) return nil;
    return objc_tag_classes[tagSlotForTagIndex(tag)];
}

#endif


#if SUPPORT_FIXUP

OBJC_EXTERN void objc_msgSend_fixup(void);
OBJC_EXTERN void objc_msgSendSuper2_fixup(void);
OBJC_EXTERN void objc_msgSend_stret_fixup(void);
OBJC_EXTERN void objc_msgSendSuper2_stret_fixup(void);
#if defined(__i386__)  ||  defined(__x86_64__)
OBJC_EXTERN void objc_msgSend_fpret_fixup(void);
#endif
#if defined(__x86_64__)
OBJC_EXTERN void objc_msgSend_fp2ret_fixup(void);
#endif

OBJC_EXTERN void objc_msgSend_fixedup(void);
OBJC_EXTERN void objc_msgSendSuper2_fixedup(void);
OBJC_EXTERN void objc_msgSend_stret_fixedup(void);
OBJC_EXTERN void objc_msgSendSuper2_stret_fixedup(void);
#if defined(__i386__)  ||  defined(__x86_64__)
OBJC_EXTERN void objc_msgSend_fpret_fixedup(void);
#endif
#if defined(__x86_64__)
OBJC_EXTERN void objc_msgSend_fp2ret_fixedup(void);
#endif

/***********************************************************************
* fixupMessageRef
* Repairs an old vtable dispatch call site. 
* vtable dispatch itself is not supported.
**********************************************************************/
static void 
fixupMessageRef(message_ref_t *msg)
{    
    msg->sel = sel_registerName((const char *)msg->sel);

    if (ignoreSelector(msg->sel)) {
        // ignored selector - bypass dispatcher
        msg->imp = (IMP)&_objc_ignored_method;
    }
    else if (msg->imp == &objc_msgSend_fixup) { 
        if (msg->sel == SEL_alloc) {
            msg->imp = (IMP)&objc_alloc;
        } else if (msg->sel == SEL_allocWithZone) {
            msg->imp = (IMP)&objc_allocWithZone;
        } else if (msg->sel == SEL_retain) {
            msg->imp = (IMP)&objc_retain;
        } else if (msg->sel == SEL_release) {
            msg->imp = (IMP)&objc_release;
        } else if (msg->sel == SEL_autorelease) {
            msg->imp = (IMP)&objc_autorelease;
        } else {
            msg->imp = &objc_msgSend_fixedup;
        }
    } 
    else if (msg->imp == &objc_msgSendSuper2_fixup) { 
        msg->imp = &objc_msgSendSuper2_fixedup;
    } 
    else if (msg->imp == &objc_msgSend_stret_fixup) { 
        msg->imp = &objc_msgSend_stret_fixedup;
    } 
    else if (msg->imp == &objc_msgSendSuper2_stret_fixup) { 
        msg->imp = &objc_msgSendSuper2_stret_fixedup;
    } 
#if defined(__i386__)  ||  defined(__x86_64__)
    else if (msg->imp == &objc_msgSend_fpret_fixup) { 
        msg->imp = &objc_msgSend_fpret_fixedup;
    } 
#endif
#if defined(__x86_64__)
    else if (msg->imp == &objc_msgSend_fp2ret_fixup) { 
        msg->imp = &objc_msgSend_fp2ret_fixedup;
    } 
#endif
}

// SUPPORT_FIXUP
#endif


// ProKit SPI
static Class setSuperclass(Class cls, Class newSuper)
{
    Class oldSuper;

    runtimeLock.assertWriting();

    assert(cls->isRealized());
    assert(newSuper->isRealized());

    oldSuper = cls->superclass;
    removeSubclass(oldSuper, cls);
    removeSubclass(oldSuper->ISA(), cls->ISA());

    cls->superclass = newSuper;
    cls->ISA()->superclass = newSuper->ISA();
    addSubclass(newSuper, cls);
    addSubclass(newSuper->ISA(), cls->ISA());

    // Flush subclass's method caches.
    flushCaches(cls);
    
    return oldSuper;
}


Class class_setSuperclass(Class cls, Class newSuper)
{
    rwlock_writer_t lock(runtimeLock);
    return setSuperclass(cls, newSuper);
}


// __OBJC2__
#endif
