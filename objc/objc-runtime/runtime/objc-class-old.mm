/*
 * Copyright (c) 1999-2009 Apple Inc.  All Rights Reserved.
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
* objc-class-old.m
* Support for old-ABI classes, methods, and categories.
**********************************************************************/

#if !__OBJC2__

#include "objc-private.h"
#include "objc-runtime-old.h"
#include "objc-file-old.h"
#include "objc-cache-old.h"

static Method _class_getMethod(Class cls, SEL sel);
static Method _class_getMethodNoSuper(Class cls, SEL sel);
static Method _class_getMethodNoSuper_nolock(Class cls, SEL sel);
static void flush_caches(Class cls, bool flush_meta);


// Freed objects have their isa set to point to this dummy class.
// This avoids the need to check for Nil classes in the messenger.
static const void* freedObjectClass[12] =
{
    Nil,				// isa
    Nil,				// superclass
    "FREED(id)",			// name
    0,				// version
    0,				// info
    0,				// instance_size
    nil,				// ivars
    nil,				// methodLists
    (Cache) &_objc_empty_cache,		// cache
    nil,				// protocols
    nil,			// ivar_layout;
    nil			// ext
};


/***********************************************************************
* _class_getFreedObjectClass.  Return a pointer to the dummy freed
* object class.  Freed objects get their isa pointers replaced with
* a pointer to the freedObjectClass, so that we can catch usages of
* the freed object.
**********************************************************************/
static Class _class_getFreedObjectClass(void)
{
    return (Class)freedObjectClass;
}


/***********************************************************************
* _objc_getFreedObjectClass.  Return a pointer to the dummy freed
* object class.  Freed objects get their isa pointers replaced with
* a pointer to the freedObjectClass, so that we can catch usages of
* the freed object.
**********************************************************************/
Class _objc_getFreedObjectClass(void)
{
    return _class_getFreedObjectClass();
}


static void allocateExt(Class cls)
{
    if (! (cls->info & CLS_EXT)) {
        _objc_inform("class '%s' needs to be recompiled", cls->name);
        return;
    } 
    if (!cls->ext) {
        uint32_t size = (uint32_t)sizeof(old_class_ext);
        cls->ext = (old_class_ext *)calloc(size, 1);
        cls->ext->size = size;
    }
}


static inline old_method *_findNamedMethodInList(old_method_list * mlist, const char *meth_name) {
    int i;
    if (!mlist) return nil;
    if (ignoreSelectorNamed(meth_name)) return nil;
    for (i = 0; i < mlist->method_count; i++) {
        old_method *m = &mlist->method_list[i];
        if (0 == strcmp((const char *)(m->method_name), meth_name)) {
            return m;
        }
    }
    return nil;
}


/***********************************************************************
* Method list fixup markers.
* mlist->obsolete == fixed_up_method_list marks method lists with real SELs 
*   versus method lists with un-uniqued char*.
* PREOPTIMIZED VERSION:
*   Fixed-up method lists get mlist->obsolete == OBJC_FIXED_UP 
*   dyld shared cache sets this for method lists it preoptimizes.
* UN-PREOPTIMIZED VERSION
*   Fixed-up method lists get mlist->obsolete == OBJC_FIXED_UP_outside_dyld
*   dyld shared cache uses OBJC_FIXED_UP, but those aren't trusted.
**********************************************************************/
#define OBJC_FIXED_UP ((void *)1771)
#define OBJC_FIXED_UP_outside_dyld ((void *)1773)
static void *fixed_up_method_list = OBJC_FIXED_UP;

// sel_init() decided that selectors in the dyld shared cache are untrustworthy
void disableSharedCacheOptimizations(void)
{
    fixed_up_method_list = OBJC_FIXED_UP_outside_dyld;
}

/***********************************************************************
* fixupSelectorsInMethodList
* Uniques selectors in the given method list.
* Also replaces imps for GC-ignored selectors
* The given method list must be non-nil and not already fixed-up.
* If the class was loaded from a bundle:
*   fixes up the given list in place with heap-allocated selector strings
* If the class was not from a bundle:
*   allocates a copy of the method list, fixes up the copy, and returns 
*   the copy. The given list is unmodified.
*
* If cls is already in use, methodListLock must be held by the caller.
**********************************************************************/
static old_method_list *fixupSelectorsInMethodList(Class cls, old_method_list *mlist)
{
    int i;
    size_t size;
    old_method *method;
    old_method_list *old_mlist; 
    
    if ( ! mlist ) return nil;
    if ( mlist->obsolete == fixed_up_method_list ) {
        // method list OK
    } else {
        bool isBundle = cls->info & CLS_FROM_BUNDLE;
        if (!isBundle) {
            old_mlist = mlist;
            size = sizeof(old_method_list) - sizeof(old_method) + old_mlist->method_count * sizeof(old_method);
            mlist = (old_method_list *)malloc(size);
            memmove(mlist, old_mlist, size);
        } else {
            // Mach-O bundles are fixed up in place. 
            // This prevents leaks when a bundle is unloaded.
        }
        sel_lock();
        for ( i = 0; i < mlist->method_count; i += 1 ) {
            method = &mlist->method_list[i];
            method->method_name =
                sel_registerNameNoLock((const char *)method->method_name, isBundle);  // Always copy selector data from bundles.

            if (ignoreSelector(method->method_name)) {
                method->method_imp = (IMP)&_objc_ignored_method;
            }
        }
        sel_unlock();
        mlist->obsolete = fixed_up_method_list;
    }
    return mlist;
}


/***********************************************************************
* nextMethodList
* Returns successive method lists from the given class.
* Method lists are returned in method search order (i.e. highest-priority 
* implementations first).
* All necessary method list fixups are performed, so the 
* returned method list is fully-constructed.
*
* If cls is already in use, methodListLock must be held by the caller.
* For full thread-safety, methodListLock must be continuously held by the 
* caller across all calls to nextMethodList(). If the lock is released, 
* the bad results listed in class_nextMethodList() may occur.
*
* void *iterator = nil;
* old_method_list *mlist;
* mutex_locker_t lock(methodListLock);
* while ((mlist = nextMethodList(cls, &iterator))) {
*     // do something with mlist
* }
**********************************************************************/
static old_method_list *nextMethodList(Class cls,
                                               void **it)
{
    uintptr_t index = *(uintptr_t *)it;
    old_method_list **resultp;

    if (index == 0) {
        // First call to nextMethodList.
        if (!cls->methodLists) {
            resultp = nil;
        } else if (cls->info & CLS_NO_METHOD_ARRAY) {
            resultp = (old_method_list **)&cls->methodLists;
        } else {
            resultp = &cls->methodLists[0];
            if (!*resultp  ||  *resultp == END_OF_METHODS_LIST) {
                resultp = nil;
            }
        }
    } else {
        // Subsequent call to nextMethodList.
        if (!cls->methodLists) {
            resultp = nil;
        } else if (cls->info & CLS_NO_METHOD_ARRAY) {
            resultp = nil;
        } else {
            resultp = &cls->methodLists[index];
            if (!*resultp  ||  *resultp == END_OF_METHODS_LIST) {
                resultp = nil;
            }
        }
    }

    // resultp now is nil, meaning there are no more method lists, 
    // OR the address of the method list pointer to fix up and return.
    
    if (resultp) {
        if (*resultp) {
            *resultp = fixupSelectorsInMethodList(cls, *resultp);
        }
        *it = (void *)(index + 1);
        return *resultp;
    } else {
        *it = 0;
        return nil;
    }
}


/* These next three functions are the heart of ObjC method lookup. 
 * If the class is currently in use, methodListLock must be held by the caller.
 */
static inline old_method *_findMethodInList(old_method_list * mlist, SEL sel) {
    int i;
    if (!mlist) return nil;
    for (i = 0; i < mlist->method_count; i++) {
        old_method *m = &mlist->method_list[i];
        if (m->method_name == sel) {
            return m;
        }
    }
    return nil;
}

static inline old_method * _findMethodInClass(Class cls, SEL sel) __attribute__((always_inline));
static inline old_method * _findMethodInClass(Class cls, SEL sel) {
    // Flattened version of nextMethodList(). The optimizer doesn't 
    // do a good job with hoisting the conditionals out of the loop.
    // Conceptually, this looks like:
    // while ((mlist = nextMethodList(cls, &iterator))) {
    //     old_method *m = _findMethodInList(mlist, sel);
    //     if (m) return m;
    // }

    if (!cls->methodLists) {
        // No method lists.
        return nil;
    }
    else if (cls->info & CLS_NO_METHOD_ARRAY) {
        // One method list.
        old_method_list **mlistp;
        mlistp = (old_method_list **)&cls->methodLists;
        *mlistp = fixupSelectorsInMethodList(cls, *mlistp);
        return _findMethodInList(*mlistp, sel);
    }
    else {
        // Multiple method lists.
        old_method_list **mlistp;
        for (mlistp = cls->methodLists; 
             *mlistp != nil  &&  *mlistp != END_OF_METHODS_LIST; 
             mlistp++) 
        {
            old_method *m;
            *mlistp = fixupSelectorsInMethodList(cls, *mlistp);
            m = _findMethodInList(*mlistp, sel);
            if (m) return m;
        }
        return nil;
    }
}

static inline old_method * _getMethod(Class cls, SEL sel) {
    for (; cls; cls = cls->superclass) {
        old_method *m;
        m = _findMethodInClass(cls, sel);
        if (m) return m;
    }
    return nil;
}


// fixme for gc debugging temporary use
IMP findIMPInClass(Class cls, SEL sel)
{
    old_method *m = _findMethodInClass(cls, sel);
    if (m) return m->method_imp;
    else return nil;
}


/***********************************************************************
* _freedHandler.
**********************************************************************/
static void _freedHandler(id obj, SEL sel)
{
    __objc_error (obj, "message %s sent to freed object=%p", 
                  sel_getName(sel), (void*)obj);
}


/***********************************************************************
* log_and_fill_cache
* Log this method call. If the logger permits it, fill the method cache.
* cls is the method whose cache should be filled. 
* implementer is the class that owns the implementation in question.
**********************************************************************/
static void
log_and_fill_cache(Class cls, Class implementer, Method meth, SEL sel)
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
    _cache_fill (cls, meth, sel);
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
    IMP methodPC = nil;
    Method meth;
    bool triedResolver = NO;

    methodListLock.assertUnlocked();

    // Optimistic cache lookup
    if (cache) {
        methodPC = _cache_getImp(cls, sel);
        if (methodPC) return methodPC;    
    }

    // Check for freed class
    if (cls == _class_getFreedObjectClass())
        return (IMP) _freedHandler;

    // Check for +initialize
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
    methodListLock.lock();

    // Ignore GC selectors
    if (ignoreSelector(sel)) {
        methodPC = _cache_addIgnoredEntry(cls, sel);
        goto done;
    }

    // Try this class's cache.

    methodPC = _cache_getImp(cls, sel);
    if (methodPC) goto done;

    // Try this class's method lists.

    meth = _class_getMethodNoSuper_nolock(cls, sel);
    if (meth) {
        log_and_fill_cache(cls, cls, meth, sel);
        methodPC = method_getImplementation(meth);
        goto done;
    }

    // Try superclass caches and method lists.

    curClass = cls;
    while ((curClass = curClass->superclass)) {
        // Superclass cache.
        meth = _cache_getMethod(curClass, sel, _objc_msgForward_impcache);
        if (meth) {
            if (meth != (Method)1) {
                // Found the method in a superclass. Cache it in this class.
                log_and_fill_cache(cls, curClass, meth, sel);
                methodPC = method_getImplementation(meth);
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
        meth = _class_getMethodNoSuper_nolock(curClass, sel);
        if (meth) {
            log_and_fill_cache(cls, curClass, meth, sel);
            methodPC = method_getImplementation(meth);
            goto done;
        }
    }

    // No implementation found. Try method resolver once.

    if (resolver  &&  !triedResolver) {
        methodListLock.unlock();
        _class_resolveMethod(cls, sel, inst);
        triedResolver = YES;
        goto retry;
    }

    // No implementation found, and method resolver didn't help. 
    // Use forwarding.

    _cache_addForwardEntry(cls, sel);
    methodPC = _objc_msgForward_impcache;

 done:
    methodListLock.unlock();

    // paranoia: look for ignored selectors with non-ignored implementations
    assert(!(ignoreSelector(sel)  &&  methodPC != (IMP)&_objc_ignored_method));

    return methodPC;
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

    // fixme this still has the method list vs method cache race 
    // because it doesn't hold a lock across lookup+cache_fill, 
    // but it's only used for .cxx_construct/destruct and we assume 
    // categories don't change them.

    // Search cache first.
    imp = _cache_getImp(cls, sel);
    if (imp) return imp;

    // Cache miss. Search method list.

    meth = _class_getMethodNoSuper(cls, sel);

    if (meth) {
        // Hit in method list. Cache it.
        _cache_fill(cls, meth, sel);
        return method_getImplementation(meth);
    } else {
        // Miss in method list. Cache objc_msgForward.
        _cache_addForwardEntry(cls, sel);
        return _objc_msgForward_impcache;
    }
}


/***********************************************************************
* class_getVariable.  Return the named instance variable.
**********************************************************************/

Ivar _class_getVariable(Class cls, const char *name, Class *memberOf)
{
    for (; cls != Nil; cls = cls->superclass) {
        int i;

        // Skip class having no ivars
        if (!cls->ivars) continue;

        for (i = 0; i < cls->ivars->ivar_count; i++) {
            // Check this ivar's name.  Be careful because the
            // compiler generates ivar entries with nil ivar_name
            // (e.g. for anonymous bit fields).
            old_ivar *ivar = &cls->ivars->ivar_list[i];
            if (ivar->ivar_name  &&  0 == strcmp(name, ivar->ivar_name)) {
                if (memberOf) *memberOf = cls;
                return (Ivar)ivar;
            }
        }
    }

    // Not found
    return nil;
}


old_property * 
property_list_nth(const old_property_list *plist, uint32_t i)
{
    return (old_property *)(i*plist->entsize + (char *)&plist->first);
}

old_property **
copyPropertyList(old_property_list *plist, unsigned int *outCount)
{
    old_property **result = nil;
    unsigned int count = 0;

    if (plist) {
        count = plist->count;
    }

    if (count > 0) {
        unsigned int i;
        result = (old_property **)malloc((count+1) * sizeof(old_property *));
        
        for (i = 0; i < count; i++) {
            result[i] = property_list_nth(plist, i);
        }
        result[i] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


static old_property_list *
nextPropertyList(Class cls, uintptr_t *indexp)
{
    old_property_list *result = nil;

    classLock.assertLocked();
    if (! ((cls->info & CLS_EXT)  &&  cls->ext)) {
        // No class ext
        result = nil;
    } else if (!cls->ext->propertyLists) {
        // No property lists
        result = nil;
    } else if (cls->info & CLS_NO_PROPERTY_ARRAY) {
        // Only one property list
        if (*indexp == 0) {
            result = (old_property_list *)cls->ext->propertyLists;
        } else {
            result = nil;
        }
    } else {
        // More than one property list
        result = cls->ext->propertyLists[*indexp];
    }

    if (result) {
        ++*indexp;
        return result;
    } else {
        *indexp = 0;
        return nil;
    }
}


/***********************************************************************
* class_getIvarLayout
* nil means all-scanned. "" means non-scanned.
**********************************************************************/
const uint8_t *
class_getIvarLayout(Class cls)
{
    if (cls  &&  (cls->info & CLS_EXT)) {
        return cls->ivar_layout;
    } else {
        return nil;  // conservative scan
    }
}


/***********************************************************************
* class_getWeakIvarLayout
* nil means no weak ivars.
**********************************************************************/
const uint8_t *
class_getWeakIvarLayout(Class cls)
{
    if (cls  &&  (cls->info & CLS_EXT)  &&  cls->ext) {
        return cls->ext->weak_ivar_layout;
    } else {
        return nil;  // no weak ivars
    }
}


/***********************************************************************
* class_setIvarLayout
* nil means all-scanned. "" means non-scanned.
**********************************************************************/
void class_setIvarLayout(Class cls, const uint8_t *layout)
{
    if (!cls) return;

    if (! (cls->info & CLS_EXT)) {
        _objc_inform("class '%s' needs to be recompiled", cls->name);
        return;
    } 

    // fixme leak
    cls->ivar_layout = ustrdupMaybeNil(layout);
}

// SPI:  Instance-specific object layout.

void _class_setIvarLayoutAccessor(Class cls, const uint8_t* (*accessor) (id object)) {
    if (!cls) return;

    if (! (cls->info & CLS_EXT)) {
        _objc_inform("class '%s' needs to be recompiled", cls->name);
        return;
    } 

    // fixme leak
    cls->ivar_layout = (const uint8_t *)accessor;
    cls->setInfo(CLS_HAS_INSTANCE_SPECIFIC_LAYOUT);
}

const uint8_t *_object_getIvarLayout(Class cls, id object) {
    if (cls && (cls->info & CLS_EXT)) {
        const uint8_t* layout = cls->ivar_layout;
        if (cls->info & CLS_HAS_INSTANCE_SPECIFIC_LAYOUT) {
            const uint8_t* (*accessor) (id object) = (const uint8_t* (*)(id))layout;
            layout = accessor(object);
        }
        return layout;
    } else {
        return nil;
    }
}

/***********************************************************************
* class_setWeakIvarLayout
* nil means no weak ivars.
**********************************************************************/
void class_setWeakIvarLayout(Class cls, const uint8_t *layout)
{
    if (!cls) return;

    mutex_locker_t lock(classLock);

    allocateExt(cls);
    
    // fixme leak
    cls->ext->weak_ivar_layout = ustrdupMaybeNil(layout);
}


/***********************************************************************
* class_setVersion.  Record the specified version with the class.
**********************************************************************/
void class_setVersion(Class cls, int version)
{
    if (!cls) return;
    cls->version = version;
}

/***********************************************************************
* class_getVersion.  Return the version recorded with the class.
**********************************************************************/
int class_getVersion(Class cls)
{
    if (!cls) return 0;
    return (int)cls->version;
}


/***********************************************************************
* class_getName.
**********************************************************************/
const char *class_getName(Class cls)
{
    if (!cls) return "nil";
    else return cls->demangledName();
}


/***********************************************************************
* _class_getNonMetaClass. 
* Return the ordinary class for this class or metaclass. 
* Used by +initialize. 
**********************************************************************/
Class _class_getNonMetaClass(Class cls, id obj)
{
    // fixme ick
    if (cls->isMetaClass()) {
        if (cls->info & CLS_CONSTRUCTING) {
            // Class is under construction and isn't in the class_hash, 
            // so objc_getClass doesn't work.
            cls = obj;  // fixme this may be nil in some paths
        }
        else if (strncmp(cls->name, "_%", 2) == 0) {
            // Posee's meta's name is smashed and isn't in the class_hash, 
            // so objc_getClass doesn't work.
            const char *baseName = strchr(cls->name, '%'); // get posee's real name
            cls = objc_getClass(baseName);
        }
        else {
            cls = objc_getClass(cls->name);
        }
        assert(cls);
    }

    return cls;
}


Cache _class_getCache(Class cls)
{
    return cls->cache;
}

void _class_setCache(Class cls, Cache cache)
{
    cls->cache = cache;
}

const char *_category_getName(Category cat)
{
    return oldcategory(cat)->category_name;
}

const char *_category_getClassName(Category cat)
{
    return oldcategory(cat)->class_name;
}

Class _category_getClass(Category cat)
{
    return objc_getClass(oldcategory(cat)->class_name);
}

IMP _category_getLoadMethod(Category cat)
{
    old_method_list *mlist = oldcategory(cat)->class_methods;
    if (mlist) {
        return lookupNamedMethodInMethodList(mlist, "load");
    } else {
        return nil;
    }
}



/***********************************************************************
* class_nextMethodList.
* External version of nextMethodList().
*
* This function is not fully thread-safe. A series of calls to 
* class_nextMethodList() may fail if methods are added to or removed 
* from the class between calls.
* If methods are added between calls to class_nextMethodList(), it may 
* return previously-returned method lists again, and may fail to return 
* newly-added lists. 
* If methods are removed between calls to class_nextMethodList(), it may 
* omit surviving method lists or simply crash.
**********************************************************************/
OBJC_EXPORT struct objc_method_list *class_nextMethodList(Class cls, void **it)
{
    OBJC_WARN_DEPRECATED;

    mutex_locker_t lock(methodListLock);
    return (struct objc_method_list *) nextMethodList(cls, it);
}


/***********************************************************************
* class_addMethods.
*
* Formerly class_addInstanceMethods ()
**********************************************************************/
OBJC_EXPORT void class_addMethods(Class cls, struct objc_method_list *meths)
{
    OBJC_WARN_DEPRECATED;

    // Add the methods.
    {
        mutex_locker_t lock(methodListLock);
        _objc_insertMethods(cls, (old_method_list *)meths, nil);
    }

    // Must flush when dynamically adding methods.  No need to flush
    // all the class method caches.  If cls is a meta class, though,
    // this will still flush it and any of its sub-meta classes.
    flush_caches (cls, NO);
}


/***********************************************************************
* class_removeMethods.
**********************************************************************/
OBJC_EXPORT void class_removeMethods(Class cls, struct objc_method_list *meths)
{
    OBJC_WARN_DEPRECATED;

    // Remove the methods
    {
        mutex_locker_t lock(methodListLock);
        _objc_removeMethods(cls, (old_method_list *)meths);
    }

    // Must flush when dynamically removing methods.  No need to flush
    // all the class method caches.  If cls is a meta class, though,
    // this will still flush it and any of its sub-meta classes.
    flush_caches (cls, NO);
}

/***********************************************************************
* lookupNamedMethodInMethodList
* Only called to find +load/-.cxx_construct/-.cxx_destruct methods, 
* without fixing up the entire method list.
* The class is not yet in use, so methodListLock is not taken.
**********************************************************************/
IMP lookupNamedMethodInMethodList(old_method_list *mlist, const char *meth_name)
{
    old_method *m;
    m = meth_name ? _findNamedMethodInList(mlist, meth_name) : nil;
    return (m ? m->method_imp : nil);
}

static Method _class_getMethod(Class cls, SEL sel)
{
    mutex_locker_t lock(methodListLock);
    return (Method)_getMethod(cls, sel);
}

static Method _class_getMethodNoSuper(Class cls, SEL sel)
{
    mutex_locker_t lock(methodListLock);
    return (Method)_findMethodInClass(cls, sel);
}

static Method _class_getMethodNoSuper_nolock(Class cls, SEL sel)
{
    methodListLock.assertLocked();
    return (Method)_findMethodInClass(cls, sel);
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

    Method meth;
    meth = _cache_getMethod(cls, sel, _objc_msgForward_impcache);
    if (meth == (Method)1) {
        // Cache contains forward:: . Stop searching.
        return nil;
    } else if (meth) {
        return meth;
    }
        
    // Search method lists, try method resolver, etc.
    lookUpImpOrNil(cls, sel, nil, 
                   NO/*initialize*/, NO/*cache*/, YES/*resolver*/);

    meth = _cache_getMethod(cls, sel, _objc_msgForward_impcache);
    if (meth == (Method)1) {
        // Cache contains forward:: . Stop searching.
        return nil;
    } else if (meth) {
        return meth;
    }

    return _class_getMethod(cls, sel);
}


BOOL class_conformsToProtocol(Class cls, Protocol *proto_gen)
{
    old_protocol *proto = oldprotocol(proto_gen);
    
    if (!cls) return NO;
    if (!proto) return NO;

    if (cls->ISA()->version >= 3) {
        old_protocol_list *list;
        for (list = cls->protocols; list != nil; list = list->next) {
            int i;
            for (i = 0; i < list->count; i++) {
                if (list->list[i] == proto) return YES;
                if (protocol_conformsToProtocol((Protocol *)list->list[i], proto_gen)) return YES;
            }
            if (cls->ISA()->version <= 4) break;
        }
    }
    return NO;
}


static NXMapTable *	posed_class_hash = nil;

/***********************************************************************
* objc_getOrigClass.
**********************************************************************/
extern "C" 
Class _objc_getOrigClass(const char *name)
{
    // Look for class among the posers
    {
        mutex_locker_t lock(classLock);
        if (posed_class_hash) {
            Class cls = (Class) NXMapGet (posed_class_hash, name);
            if (cls) return cls;
        }
    }

    // Not a poser.  Do a normal lookup.
    Class cls = objc_getClass (name);
    if (cls) return cls;

    _objc_inform ("class `%s' not linked into application", name);
    return nil;
}

Class objc_getOrigClass(const char *name)
{
    OBJC_WARN_DEPRECATED;
    return _objc_getOrigClass(name);
}

/***********************************************************************
* _objc_addOrigClass.  This function is only used from class_poseAs.
* Registers the original class names, before they get obscured by
* posing, so that [super ..] will work correctly from categories
* in posing classes and in categories in classes being posed for.
**********************************************************************/
static void	_objc_addOrigClass	   (Class origClass)
{
    mutex_locker_t lock(classLock);

    // Create the poser's hash table on first use
    if (!posed_class_hash)
    {
        posed_class_hash = NXCreateMapTable(NXStrValueMapPrototype, 8);
    }

    // Add the named class iff it is not already there (or collides?)
    if (NXMapGet (posed_class_hash, origClass->name) == 0)
        NXMapInsert (posed_class_hash, origClass->name, origClass);
}


/***********************************************************************
* change_class_references
* Change classrefs and superclass pointers from original to imposter
* But if copy!=nil, don't change copy->superclass.
* If changeSuperRefs==YES, also change [super message] classrefs. 
* Used by class_poseAs and objc_setFutureClass
* classLock must be locked.
**********************************************************************/
void change_class_references(Class imposter, 
                             Class original, 
                             Class copy, 
                             bool changeSuperRefs)
{
    header_info *hInfo;
    Class clsObject;
    NXHashState state;

    // Change all subclasses of the original to point to the imposter.
    state = NXInitHashState (class_hash);
    while (NXNextHashState (class_hash, &state, (void **) &clsObject))
    {
        while  ((clsObject) && (clsObject != imposter) &&
                (clsObject != copy))
        {
            if (clsObject->superclass == original)
            {
                clsObject->superclass = imposter;
                clsObject->ISA()->superclass = imposter->ISA();
                // We must flush caches here!
                break;
            }

            clsObject = clsObject->superclass;
        }
    }

    // Replace the original with the imposter in all class refs
    // Major loop - process all headers
    for (hInfo = FirstHeader; hInfo != nil; hInfo = hInfo->next)
    {
        Class *cls_refs;
        size_t	refCount;
        unsigned int	index;

        // Fix class refs associated with this header
        cls_refs = _getObjcClassRefs(hInfo, &refCount);
        if (cls_refs) {
            for (index = 0; index < refCount; index += 1) {
                if (cls_refs[index] == original) {
                    cls_refs[index] = imposter;
                }
            }
        }
    }
}


/***********************************************************************
* class_poseAs.
*
* !!! class_poseAs () does not currently flush any caches.
**********************************************************************/
Class class_poseAs(Class imposter, Class original)
{
    char *			imposterNamePtr;
    Class 			copy;

    OBJC_WARN_DEPRECATED;

    // Trivial case is easy
    if (imposter == original)
        return imposter;

    // Imposter must be an immediate subclass of the original
    if (imposter->superclass != original) {
        __objc_error(imposter, 
                     "[%s poseAs:%s]: target not immediate superclass", 
                     imposter->name, original->name);
    }

    // Can't pose when you have instance variables (how could it work?)
    if (imposter->ivars) {
        __objc_error(imposter, 
                     "[%s poseAs:%s]: %s defines new instance variables", 
                     imposter->name, original->name, imposter->name);
    }

    // Build a string to use to replace the name of the original class.
#if TARGET_OS_WIN32
#   define imposterNamePrefix "_%"
    imposterNamePtr = malloc(strlen(original->name) + strlen(imposterNamePrefix) + 1);
    strcpy(imposterNamePtr, imposterNamePrefix);
    strcat(imposterNamePtr, original->name);
#   undef imposterNamePrefix
#else
    asprintf(&imposterNamePtr, "_%%%s", original->name);
#endif

    // We lock the class hashtable, so we are thread safe with respect to
    // calls to objc_getClass ().  However, the class names are not
    // changed atomically, nor are all of the subclasses updated
    // atomically.  I have ordered the operations so that you will
    // never crash, but you may get inconsistent results....

    // Register the original class so that [super ..] knows
    // exactly which classes are the "original" classes.
    _objc_addOrigClass (original);
    _objc_addOrigClass (imposter);

    // Copy the imposter, so that the imposter can continue
    // its normal life in addition to changing the behavior of
    // the original.  As a hack we don't bother to copy the metaclass.
    // For some reason we modify the original rather than the copy.
    copy = (Class)malloc(sizeof(objc_class));
    memmove(copy, imposter, sizeof(objc_class));

    mutex_locker_t lock(classLock);

    // Remove both the imposter and the original class.
    NXHashRemove (class_hash, imposter);
    NXHashRemove (class_hash, original);

    NXHashInsert (class_hash, copy);
    objc_addRegisteredClass(copy);  // imposter & original will rejoin later, just track the new guy

    // Mark the imposter as such
    imposter->setInfo(CLS_POSING);
    imposter->ISA()->setInfo(CLS_POSING);

    // Change the name of the imposter to that of the original class.
    imposter->name      = original->name;
    imposter->ISA()->name = original->ISA()->name;

    // Also copy the version field to avoid archiving problems.
    imposter->version = original->version;

    // Change classrefs and superclass pointers
    // Don't change copy->superclass
    // Don't change [super ...] messages
    change_class_references(imposter, original, copy, NO);

    // Change the name of the original class.
    original->name      = imposterNamePtr + 1;
    original->ISA()->name = imposterNamePtr;

    // Restore the imposter and the original class with their new names.
    NXHashInsert (class_hash, imposter);
    NXHashInsert (class_hash, original);

    return imposter;
}


/***********************************************************************
* _objc_flush_caches.  Flush the instance and class method caches
* of cls and all its subclasses.
*
* Specifying Nil for the class "all classes."
**********************************************************************/
static void flush_caches(Class target, bool flush_meta)
{
    bool collectALot = (target == nil);
    NXHashState state;
    Class clsObject;
#ifdef OBJC_INSTRUMENTED
    unsigned int classesVisited;
    unsigned int subclassCount;
#endif

    mutex_locker_t lock(classLock);
    mutex_locker_t lock2(cacheUpdateLock);

    // Leaf classes are fastest because there are no subclass caches to flush.
    // fixme instrument
    if (target  &&  (target->info & CLS_LEAF)) {
        _cache_flush (target);
        
        if (target->ISA()  &&  (target->ISA()->info & CLS_LEAF)) {
            _cache_flush (target->ISA());
            return;  // done
        } else {
            // Reset target and handle it by one of the methods below.
            target = target->ISA();
            flush_meta = NO;
            // NOT done
        }
    }

    state = NXInitHashState(class_hash);

    // Handle nil and root instance class specially: flush all
    // instance and class method caches.  Nice that this
    // loop is linear vs the N-squared loop just below.
    if (!target  ||  !target->superclass)
    {
#ifdef OBJC_INSTRUMENTED
        LinearFlushCachesCount += 1;
        classesVisited = 0;
        subclassCount = 0;
#endif
        // Traverse all classes in the hash table
        while (NXNextHashState(class_hash, &state, (void**)&clsObject))
        {
            Class metaClsObject;
#ifdef OBJC_INSTRUMENTED
            classesVisited += 1;
#endif

            // Skip class that is known not to be a subclass of this root
            // (the isa pointer of any meta class points to the meta class
            // of the root).
            // NOTE: When is an isa pointer of a hash tabled class ever nil?
            metaClsObject = clsObject->ISA();
            if (target  &&  metaClsObject  &&  target->ISA() != metaClsObject->ISA()) {
                continue;
            }

#ifdef OBJC_INSTRUMENTED
            subclassCount += 1;
#endif

            _cache_flush (clsObject);
            if (flush_meta  &&  metaClsObject != nil) {
                _cache_flush (metaClsObject);
            }
        }
#ifdef OBJC_INSTRUMENTED
        LinearFlushCachesVisitedCount += classesVisited;
        if (classesVisited > MaxLinearFlushCachesVisitedCount)
            MaxLinearFlushCachesVisitedCount = classesVisited;
        IdealFlushCachesCount += subclassCount;
        if (subclassCount > MaxIdealFlushCachesCount)
            MaxIdealFlushCachesCount = subclassCount;
#endif

        goto done;
    }

    // Outer loop - flush any cache that could now get a method from
    // cls (i.e. the cache associated with cls and any of its subclasses).
#ifdef OBJC_INSTRUMENTED
    NonlinearFlushCachesCount += 1;
    classesVisited = 0;
    subclassCount = 0;
#endif
    while (NXNextHashState(class_hash, &state, (void**)&clsObject))
    {
        Class clsIter;

#ifdef OBJC_INSTRUMENTED
        NonlinearFlushCachesClassCount += 1;
#endif

        // Inner loop - Process a given class
        clsIter = clsObject;
        while (clsIter)
        {

#ifdef OBJC_INSTRUMENTED
            classesVisited += 1;
#endif
            // Flush clsObject instance method cache if
            // clsObject is a subclass of cls, or is cls itself
            // Flush the class method cache if that was asked for
            if (clsIter == target)
            {
#ifdef OBJC_INSTRUMENTED
                subclassCount += 1;
#endif
                _cache_flush (clsObject);
                if (flush_meta)
                    _cache_flush (clsObject->ISA());

                break;

            }

            // Flush clsObject class method cache if cls is
            // the meta class of clsObject or of one
            // of clsObject's superclasses
            else if (clsIter->ISA() == target)
            {
#ifdef OBJC_INSTRUMENTED
                subclassCount += 1;
#endif
                _cache_flush (clsObject->ISA());
                break;
            }

            // Move up superclass chain
            // else if (clsIter->isInitialized())
            clsIter = clsIter->superclass;

            // clsIter is not initialized, so its cache
            // must be empty.  This happens only when
            // clsIter == clsObject, because
            // superclasses are initialized before
            // subclasses, and this loop traverses
            // from sub- to super- classes.
            // else
                // break;
        }
    }
#ifdef OBJC_INSTRUMENTED
    NonlinearFlushCachesVisitedCount += classesVisited;
    if (classesVisited > MaxNonlinearFlushCachesVisitedCount)
        MaxNonlinearFlushCachesVisitedCount = classesVisited;
    IdealFlushCachesCount += subclassCount;
    if (subclassCount > MaxIdealFlushCachesCount)
        MaxIdealFlushCachesCount = subclassCount;
#endif


 done:
    if (collectALot) {
        _cache_collect(true);
    }
}


void _objc_flush_caches(Class target)
{
    flush_caches(target, YES);
}



/***********************************************************************
* flush_marked_caches. Flush the method cache of any class marked 
* CLS_FLUSH_CACHE (and all subclasses thereof)
* fixme instrument
**********************************************************************/
void flush_marked_caches(void)
{
    Class cls;
    Class supercls;
    NXHashState state;

    mutex_locker_t lock(classLock);
    mutex_locker_t lock2(cacheUpdateLock);

    state = NXInitHashState(class_hash);
    while (NXNextHashState(class_hash, &state, (void**)&cls)) {
        for (supercls = cls; supercls; supercls = supercls->superclass) {
            if (supercls->info & CLS_FLUSH_CACHE) {
                _cache_flush(cls);
                break;
            }
        }

        for (supercls = cls->ISA(); supercls; supercls = supercls->superclass) {
            if (supercls->info & CLS_FLUSH_CACHE) {
                _cache_flush(cls->ISA());
                break;
            }
        }
    }

    state = NXInitHashState(class_hash);
    while (NXNextHashState(class_hash, &state, (void**)&cls)) {
        if (cls->info & CLS_FLUSH_CACHE) {
            cls->clearInfo(CLS_FLUSH_CACHE);            
        }
        if (cls->ISA()->info & CLS_FLUSH_CACHE) {
            cls->ISA()->clearInfo(CLS_FLUSH_CACHE);
        }
    }
}


/***********************************************************************
* get_base_method_list
* Returns the method list containing the class's own methods, 
* ignoring any method lists added by categories or class_addMethods. 
* Called only by add_class_to_loadable_list. 
* Does not hold methodListLock because add_class_to_loadable_list 
* does not manipulate in-use classes.
**********************************************************************/
static old_method_list *get_base_method_list(Class cls) 
{
    old_method_list **ptr;

    if (!cls->methodLists) return nil;
    if (cls->info & CLS_NO_METHOD_ARRAY) return (old_method_list *)cls->methodLists;
    ptr = cls->methodLists;
    if (!*ptr  ||  *ptr == END_OF_METHODS_LIST) return nil;
    while ( *ptr != 0 && *ptr != END_OF_METHODS_LIST ) { ptr++; }
    --ptr;
    return *ptr;
}


static IMP _class_getLoadMethod_nocheck(Class cls)
{
    old_method_list *mlist;
    mlist = get_base_method_list(cls->ISA());
    if (mlist) {
        return lookupNamedMethodInMethodList (mlist, "load");
    }
    return nil;
}


bool _class_hasLoadMethod(Class cls)
{
    if (cls->ISA()->info & CLS_HAS_LOAD_METHOD) return YES;
    return _class_getLoadMethod_nocheck(cls);
}


/***********************************************************************
* objc_class::getLoadMethod
* Returns cls's +load implementation, or nil if it doesn't have one.
**********************************************************************/
IMP objc_class::getLoadMethod()
{
    if (ISA()->info & CLS_HAS_LOAD_METHOD) {
        return _class_getLoadMethod_nocheck((Class)this);
    }
    return nil;
}

BOOL _class_usesAutomaticRetainRelease(Class cls)
{
    return NO;
}

uint32_t _class_getInstanceStart(Class cls)
{
    _objc_fatal("_class_getInstanceStart() unimplemented for fragile instance variables");
    return 0;   // PCB:  never used just provided for ARR consistency.
}

ptrdiff_t ivar_getOffset(Ivar ivar)
{
    return oldivar(ivar)->ivar_offset;
}

const char *ivar_getName(Ivar ivar)
{
    return oldivar(ivar)->ivar_name;
}

const char *ivar_getTypeEncoding(Ivar ivar)
{
    return oldivar(ivar)->ivar_type;
}


IMP method_getImplementation(Method m)
{
    if (!m) return nil;
    return oldmethod(m)->method_imp;
}

SEL method_getName(Method m)
{
    if (!m) return nil;
    return oldmethod(m)->method_name;
}

const char *method_getTypeEncoding(Method m)
{
    if (!m) return nil;
    return oldmethod(m)->method_types;
}

unsigned int method_getSizeOfArguments(Method m)
{
    OBJC_WARN_DEPRECATED;
    if (!m) return 0;
    return encoding_getSizeOfArguments(method_getTypeEncoding(m));
}

unsigned int method_getArgumentInfo(Method m, int arg,
                                    const char **type, int *offset)
{
    OBJC_WARN_DEPRECATED;
    if (!m) return 0;
    return encoding_getArgumentInfo(method_getTypeEncoding(m), 
                                    arg, type, offset);
}


static spinlock_t impLock;

IMP method_setImplementation(Method m_gen, IMP imp)
{
    IMP old;
    old_method *m = oldmethod(m_gen);
    if (!m) return nil;
    if (!imp) return nil;
    
    if (ignoreSelector(m->method_name)) {
        // Ignored methods stay ignored
        return m->method_imp;
    }

    impLock.lock();
    old = m->method_imp;
    m->method_imp = imp;
    impLock.unlock();
    return old;
}


void method_exchangeImplementations(Method m1_gen, Method m2_gen)
{
    IMP m1_imp;
    old_method *m1 = oldmethod(m1_gen);
    old_method *m2 = oldmethod(m2_gen);
    if (!m1  ||  !m2) return;

    if (ignoreSelector(m1->method_name)  ||  ignoreSelector(m2->method_name)) {
        // Ignored methods stay ignored. Now they're both ignored.
        m1->method_imp = (IMP)&_objc_ignored_method;
        m2->method_imp = (IMP)&_objc_ignored_method;
        return;
    }

    impLock.lock();
    m1_imp = m1->method_imp;
    m1->method_imp = m2->method_imp;
    m2->method_imp = m1_imp;
    impLock.unlock();
}


struct objc_method_description * method_getDescription(Method m)
{
    if (!m) return nil;
    return (struct objc_method_description *)oldmethod(m);
}


const char *property_getName(objc_property_t prop)
{
    return oldproperty(prop)->name;
}

const char *property_getAttributes(objc_property_t prop)
{
    return oldproperty(prop)->attributes;
}

objc_property_attribute_t *property_copyAttributeList(objc_property_t prop, 
                                                      unsigned int *outCount)
{
    if (!prop) {
        if (outCount) *outCount = 0;
        return nil;
    }

    mutex_locker_t lock(classLock);
    return copyPropertyAttributeList(oldproperty(prop)->attributes,outCount);
}

char * property_copyAttributeValue(objc_property_t prop, const char *name)
{
    if (!prop  ||  !name  ||  *name == '\0') return nil;
    
    mutex_locker_t lock(classLock);
    return copyPropertyAttributeValue(oldproperty(prop)->attributes, name);
}


/***********************************************************************
* class_addMethod
**********************************************************************/
static IMP _class_addMethod(Class cls, SEL name, IMP imp, 
                            const char *types, bool replace)
{
    old_method *m;
    IMP result = nil;

    if (!types) types = "";

    mutex_locker_t lock(methodListLock);

    if ((m = _findMethodInClass(cls, name))) {
        // already exists
        // fixme atomic
        result = method_getImplementation((Method)m);
        if (replace) {
            method_setImplementation((Method)m, imp);
        }
    } else {
        // fixme could be faster
        old_method_list *mlist = 
            (old_method_list *)calloc(sizeof(old_method_list), 1);
        mlist->obsolete = fixed_up_method_list;
        mlist->method_count = 1;
        mlist->method_list[0].method_name = name;
        mlist->method_list[0].method_types = strdup(types);
        if (!ignoreSelector(name)) {
            mlist->method_list[0].method_imp = imp;
        } else {
            mlist->method_list[0].method_imp = (IMP)&_objc_ignored_method;
        }
        
        _objc_insertMethods(cls, mlist, nil);
        if (!(cls->info & CLS_CONSTRUCTING)) {
            flush_caches(cls, NO);
        } else {
            // in-construction class has no subclasses
            flush_cache(cls);
        }
        result = nil;
    }

    return result;
}


/***********************************************************************
* class_addMethod
**********************************************************************/
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types)
{
    IMP old;
    if (!cls) return NO;

    old = _class_addMethod(cls, name, imp, types, NO);
    return !old;
}


/***********************************************************************
* class_replaceMethod
**********************************************************************/
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types)
{
    if (!cls) return nil;

    return _class_addMethod(cls, name, imp, types, YES);
}


/***********************************************************************
* class_addIvar
**********************************************************************/
BOOL class_addIvar(Class cls, const char *name, size_t size, 
                   uint8_t alignment, const char *type)
{
    bool result = YES;

    if (!cls) return NO;
    if (ISMETA(cls)) return NO;
    if (!(cls->info & CLS_CONSTRUCTING)) return NO;

    if (!type) type = "";
    if (name  &&  0 == strcmp(name, "")) name = nil;
    
    mutex_locker_t lock(classLock);

    // Check for existing ivar with this name
    // fixme check superclasses?
    if (cls->ivars) {
        int i;
        for (i = 0; i < cls->ivars->ivar_count; i++) {
            if (0 == strcmp(cls->ivars->ivar_list[i].ivar_name, name)) {
                result = NO;
                break;
            }
        }
    }

    if (result) {
        old_ivar_list *old = cls->ivars;
        size_t oldSize;
        int newCount;
        old_ivar *ivar;
        size_t alignBytes;
        size_t misalign;
        
        if (old) {
            oldSize = sizeof(old_ivar_list) + 
                (old->ivar_count - 1) * sizeof(old_ivar);
            newCount = 1 + old->ivar_count;
        } else {
            oldSize = sizeof(old_ivar_list) - sizeof(old_ivar);
            newCount = 1;
        }

        // allocate new ivar list
        cls->ivars = (old_ivar_list *)
            calloc(oldSize+sizeof(old_ivar), 1);
        if (old) memcpy(cls->ivars, old, oldSize);
        if (old  &&  malloc_size(old)) free(old);
        cls->ivars->ivar_count = newCount;
        ivar = &cls->ivars->ivar_list[newCount-1];

        // set ivar name and type
        ivar->ivar_name = strdup(name);
        ivar->ivar_type = strdup(type);

        // align if necessary
        alignBytes = 1 << alignment;
        misalign = cls->instance_size % alignBytes;
        if (misalign) cls->instance_size += (long)(alignBytes - misalign);

        // set ivar offset and increase instance size
        ivar->ivar_offset = (int)cls->instance_size;
        cls->instance_size += (long)size;
    }

    return result;
}


/***********************************************************************
* class_addProtocol
**********************************************************************/
BOOL class_addProtocol(Class cls, Protocol *protocol_gen)
{
    old_protocol *protocol = oldprotocol(protocol_gen);
    old_protocol_list *plist;

    if (!cls) return NO;
    if (class_conformsToProtocol(cls, protocol_gen)) return NO;

    mutex_locker_t lock(classLock);

    // fixme optimize - protocol list doesn't escape?
    plist = (old_protocol_list*)calloc(sizeof(old_protocol_list), 1);
    plist->count = 1;
    plist->list[0] = protocol;
    plist->next = cls->protocols;
    cls->protocols = plist;

    // fixme metaclass?

    return YES;
}


/***********************************************************************
* _class_addProperties
* Internal helper to add properties to a class. 
* Used by category attachment and  class_addProperty() 
* Locking: acquires classLock
**********************************************************************/
bool 
_class_addProperties(Class cls,
                     old_property_list *additions)
{
    old_property_list *newlist;

    if (!(cls->info & CLS_EXT)) return NO;

    newlist = (old_property_list *)
        memdup(additions, sizeof(*newlist) - sizeof(newlist->first) 
                         + (additions->entsize * additions->count));

    mutex_locker_t lock(classLock);

    allocateExt(cls);
    if (!cls->ext->propertyLists) {
        // cls has no properties - simply use this list
        cls->ext->propertyLists = (old_property_list **)newlist;
        cls->setInfo(CLS_NO_PROPERTY_ARRAY);
    } 
    else if (cls->info & CLS_NO_PROPERTY_ARRAY) {
        // cls has one property list - make a new array
        old_property_list **newarray = (old_property_list **)
            malloc(3 * sizeof(*newarray));
        newarray[0] = newlist;
        newarray[1] = (old_property_list *)cls->ext->propertyLists;
        newarray[2] = nil;
        cls->ext->propertyLists = newarray;
        cls->clearInfo(CLS_NO_PROPERTY_ARRAY);
    }
    else {
        // cls has a property array - make a bigger one
        old_property_list **newarray;
        int count = 0;
        while (cls->ext->propertyLists[count]) count++;
        newarray = (old_property_list **)
            malloc((count+2) * sizeof(*newarray));
        newarray[0] = newlist;
        memcpy(&newarray[1], &cls->ext->propertyLists[0], 
               count * sizeof(*newarray));
        newarray[count+1] = nil;
        free(cls->ext->propertyLists);
        cls->ext->propertyLists = newarray;
    }

    return YES;
}


/***********************************************************************
* class_addProperty
* Adds a property to a class. Returns NO if the proeprty already exists.
* Locking: acquires classLock
**********************************************************************/
static bool 
_class_addProperty(Class cls, const char *name, 
                   const objc_property_attribute_t *attrs, unsigned int count, 
                   bool replace)
{
    if (!cls) return NO;
    if (!name) return NO;

    old_property *prop = oldproperty(class_getProperty(cls, name));
    if (prop  &&  !replace) {
        // already exists, refuse to replace
        return NO;
    } 
    else if (prop) {
        // replace existing
        mutex_locker_t lock(classLock);
        try_free(prop->attributes);
        prop->attributes = copyPropertyAttributeString(attrs, count);
        return YES;
    } 
    else {
        // add new
        old_property_list proplist;
        proplist.entsize = sizeof(old_property);
        proplist.count = 1;
        proplist.first.name = strdup(name);
        proplist.first.attributes = copyPropertyAttributeString(attrs, count);
        
        return _class_addProperties(cls, &proplist);
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
* class_copyProtocolList.  Returns a heap block containing the 
* protocols implemented by the class, or nil if the class 
* implements no protocols. Caller must free the block.
* Does not copy any superclass's protocols.
**********************************************************************/
Protocol * __unsafe_unretained *
class_copyProtocolList(Class cls, unsigned int *outCount)
{
    old_protocol_list *plist;
    Protocol **result = nil;
    unsigned int count = 0;
    unsigned int p;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    mutex_locker_t lock(classLock);

    for (plist = cls->protocols; plist != nil; plist = plist->next) {
        count += (int)plist->count;
    }

    if (count > 0) {
        result = (Protocol **)malloc((count+1) * sizeof(Protocol *));
        
        for (p = 0, plist = cls->protocols; 
             plist != nil; 
             plist = plist->next) 
        {
            int i;
            for (i = 0; i < plist->count; i++) {
                result[p++] = (Protocol *)plist->list[i];
            }
        }
        result[p] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* class_getProperty.  Return the named property.
**********************************************************************/
objc_property_t class_getProperty(Class cls, const char *name)
{
    if (!cls  ||  !name) return nil;

    mutex_locker_t lock(classLock);

    for (; cls; cls = cls->superclass) {
        uintptr_t iterator = 0;
        old_property_list *plist;
        while ((plist = nextPropertyList(cls, &iterator))) {
            uint32_t i;
            for (i = 0; i < plist->count; i++) {
                old_property *p = property_list_nth(plist, i);
                if (0 == strcmp(name, p->name)) {
                    return (objc_property_t)p;
                }
            }
        }
    }

    return nil;
}


/***********************************************************************
* class_copyPropertyList. Returns a heap block containing the 
* properties declared in the class, or nil if the class 
* declares no properties. Caller must free the block.
* Does not copy any superclass's properties.
**********************************************************************/
objc_property_t *class_copyPropertyList(Class cls, unsigned int *outCount)
{
    old_property_list *plist;
    uintptr_t iterator = 0;
    old_property **result = nil;
    unsigned int count = 0;
    unsigned int p, i;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    mutex_locker_t lock(classLock);

    iterator = 0;
    while ((plist = nextPropertyList(cls, &iterator))) {
        count += plist->count;
    }

    if (count > 0) {
        result = (old_property **)malloc((count+1) * sizeof(old_property *));
        
        p = 0;
        iterator = 0;
        while ((plist = nextPropertyList(cls, &iterator))) {
            for (i = 0; i < plist->count; i++) {
                result[p++] = property_list_nth(plist, i);
            }
        }
        result[p] = nil;
    }

    if (outCount) *outCount = count;
    return (objc_property_t *)result;
}


/***********************************************************************
* class_copyMethodList.  Returns a heap block containing the 
* methods implemented by the class, or nil if the class 
* implements no methods. Caller must free the block.
* Does not copy any superclass's methods.
**********************************************************************/
Method *class_copyMethodList(Class cls, unsigned int *outCount)
{
    old_method_list *mlist;
    void *iterator = nil;
    Method *result = nil;
    unsigned int count = 0;
    unsigned int m;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    mutex_locker_t lock(methodListLock);

    iterator = nil;
    while ((mlist = nextMethodList(cls, &iterator))) {
        count += mlist->method_count;
    }

    if (count > 0) {
        result = (Method *)malloc((count+1) * sizeof(Method));
        
        m = 0;
        iterator = nil;
        while ((mlist = nextMethodList(cls, &iterator))) {
            int i;
            for (i = 0; i < mlist->method_count; i++) {
                Method aMethod = (Method)&mlist->method_list[i];
                if (ignoreSelector(method_getName(aMethod))) {
                    count--;
                    continue;
                }
                result[m++] = aMethod;
            }
        }
        result[m] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* class_copyIvarList.  Returns a heap block containing the 
* ivars declared in the class, or nil if the class 
* declares no ivars. Caller must free the block.
* Does not copy any superclass's ivars.
**********************************************************************/
Ivar *class_copyIvarList(Class cls, unsigned int *outCount)
{
    Ivar *result = nil;
    unsigned int count = 0;
    int i;

    if (!cls) {
        if (outCount) *outCount = 0;
        return nil;
    }

    if (cls->ivars) {
        count = cls->ivars->ivar_count;
    }

    if (count > 0) {
        result = (Ivar *)malloc((count+1) * sizeof(Ivar));

        for (i = 0; i < cls->ivars->ivar_count; i++) {
            result[i] = (Ivar)&cls->ivars->ivar_list[i];
        }
        result[i] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


/***********************************************************************
* objc_allocateClass.
**********************************************************************/

void set_superclass(Class cls, Class supercls, bool cls_is_new)
{
    Class meta = cls->ISA();

    if (supercls) {
        cls->superclass = supercls;
        meta->superclass = supercls->ISA();
        meta->initIsa(supercls->ISA()->ISA());

        // Propagate C++ cdtors from superclass.
        if (supercls->info & CLS_HAS_CXX_STRUCTORS) {
            if (cls_is_new) cls->info |= CLS_HAS_CXX_STRUCTORS;
            else cls->setInfo(CLS_HAS_CXX_STRUCTORS);
        }

        // Superclass is no longer a leaf for cache flushing
        if (supercls->info & CLS_LEAF) {
            supercls->clearInfo(CLS_LEAF);
            supercls->ISA()->clearInfo(CLS_LEAF);
        }
    } else {
        cls->superclass = Nil;  // superclass of root class is nil
        meta->superclass = cls; // superclass of root metaclass is root class
        meta->initIsa(meta);    // metaclass of root metaclass is root metaclass

        // Root class is never a leaf for cache flushing, because the 
        // root metaclass is a subclass. (This could be optimized, but 
        // is too uncommon to bother.)
        cls->clearInfo(CLS_LEAF);
        meta->clearInfo(CLS_LEAF);
    }    
}

// &UnsetLayout is the default ivar layout during class construction
static const uint8_t UnsetLayout = 0;

Class objc_initializeClassPair(Class supercls, const char *name, Class cls, Class meta)
{
    // Connect to superclasses and metaclasses
    cls->initIsa(meta);
    set_superclass(cls, supercls, YES);

    // Set basic info
    cls->name = strdup(name);
    meta->name = strdup(name);
    cls->version = 0;
    meta->version = 7;
    cls->info = CLS_CLASS | CLS_CONSTRUCTING | CLS_EXT | CLS_LEAF;
    meta->info = CLS_META | CLS_CONSTRUCTING | CLS_EXT | CLS_LEAF;

    // Set instance size based on superclass.
    if (supercls) {
        cls->instance_size = supercls->instance_size;
        meta->instance_size = supercls->ISA()->instance_size;
    } else {
        cls->instance_size = sizeof(Class);  // just an isa
        meta->instance_size = sizeof(objc_class);
    }
    
    // No ivars. No methods. Empty cache. No protocols. No layout. Empty ext.
    cls->ivars = nil;
    cls->methodLists = nil;
    cls->cache = (Cache)&_objc_empty_cache;
    cls->protocols = nil;
    cls->ivar_layout = &UnsetLayout;
    cls->ext = nil;
    allocateExt(cls);
    cls->ext->weak_ivar_layout = &UnsetLayout;

    meta->ivars = nil;
    meta->methodLists = nil;
    meta->cache = (Cache)&_objc_empty_cache;
    meta->protocols = nil;
    meta->ext = nil;
    
    return cls;
}

Class objc_allocateClassPair(Class supercls, const char *name, 
                             size_t extraBytes)
{
    Class cls, meta;

    if (objc_getClass(name)) return nil;
    // fixme reserve class name against simultaneous allocation

    if (supercls  &&  (supercls->info & CLS_CONSTRUCTING)) {
        // Can't make subclass of an in-construction class
        return nil;
    }

    // Allocate new classes. 
    if (supercls) {
        cls = _calloc_class(supercls->ISA()->alignedInstanceSize() + extraBytes);
        meta = _calloc_class(supercls->ISA()->ISA()->alignedInstanceSize() + extraBytes);
    } else {
        cls = _calloc_class(sizeof(objc_class) + extraBytes);
        meta = _calloc_class(sizeof(objc_class) + extraBytes);
    }


    objc_initializeClassPair(supercls, name, cls, meta);
    
    return cls;
}


void objc_registerClassPair(Class cls)
{
    if ((cls->info & CLS_CONSTRUCTED)  ||  
        (cls->ISA()->info & CLS_CONSTRUCTED)) 
    {
        _objc_inform("objc_registerClassPair: class '%s' was already "
                     "registered!", cls->name);
        return;
    }

    if (!(cls->info & CLS_CONSTRUCTING)  ||  
        !(cls->ISA()->info & CLS_CONSTRUCTING)) 
    {
        _objc_inform("objc_registerClassPair: class '%s' was not "
                     "allocated with objc_allocateClassPair!", cls->name);
        return;
    }

    if (ISMETA(cls)) {
        _objc_inform("objc_registerClassPair: class '%s' is a metaclass, "
                     "not a class!", cls->name);
        return;
    }

    mutex_locker_t lock(classLock);

    // Build ivar layouts
    if (UseGC) {
        if (cls->ivar_layout != &UnsetLayout) {
            // Class builder already called class_setIvarLayout.
        }
        else if (!cls->superclass) {
            // Root class. Scan conservatively (should be isa ivar only).
            cls->ivar_layout = nil;
        }
        else if (cls->ivars == nil) {
            // No local ivars. Use superclass's layout.
            cls->ivar_layout = 
                ustrdupMaybeNil(cls->superclass->ivar_layout);
        }
        else {
            // Has local ivars. Build layout based on superclass.
            Class supercls = cls->superclass;
            const uint8_t *superlayout = 
                class_getIvarLayout(supercls);
            layout_bitmap bitmap = 
                layout_bitmap_create(superlayout, supercls->instance_size, 
                                     cls->instance_size, NO);
            int i;
            for (i = 0; i < cls->ivars->ivar_count; i++) {
                old_ivar *iv = &cls->ivars->ivar_list[i];
                layout_bitmap_set_ivar(bitmap, iv->ivar_type, iv->ivar_offset);
            }
            cls->ivar_layout = layout_string_create(bitmap);
            layout_bitmap_free(bitmap);
        }

        if (cls->ext->weak_ivar_layout != &UnsetLayout) {
            // Class builder already called class_setWeakIvarLayout.
        }
        else if (!cls->superclass) {
            // Root class. No weak ivars (should be isa ivar only)
            cls->ext->weak_ivar_layout = nil;
        }
        else if (cls->ivars == nil) {
            // No local ivars. Use superclass's layout.
            const uint8_t *weak = 
                class_getWeakIvarLayout(cls->superclass);
            cls->ext->weak_ivar_layout = ustrdupMaybeNil(weak);
        }
        else {
            // Has local ivars. Build layout based on superclass.
            // No way to add weak ivars yet.
            const uint8_t *weak = 
                class_getWeakIvarLayout(cls->superclass);
            cls->ext->weak_ivar_layout = ustrdupMaybeNil(weak);
        }
    }

    // Clear "under construction" bit, set "done constructing" bit
    cls->info &= ~CLS_CONSTRUCTING;
    cls->ISA()->info &= ~CLS_CONSTRUCTING;
    cls->info |= CLS_CONSTRUCTED;
    cls->ISA()->info |= CLS_CONSTRUCTED;

    NXHashInsertIfAbsent(class_hash, cls);
    objc_addRegisteredClass(cls);
    //objc_addRegisteredClass(cls->ISA());  if we ever allocate classes from GC
}


Class objc_duplicateClass(Class original, const char *name, size_t extraBytes)
{
    unsigned int count, i;
    old_method **originalMethods;
    old_method_list *duplicateMethods;
    // Don't use sizeof(objc_class) here because 
    // instance_size has historically contained two extra words, 
    // and instance_size is what objc_getIndexedIvars() actually uses.
    Class duplicate = 
        _calloc_class(original->ISA()->alignedInstanceSize() + extraBytes);

    duplicate->initIsa(original->ISA());
    duplicate->superclass = original->superclass;
    duplicate->name = strdup(name);
    duplicate->version = original->version;
    duplicate->info = original->info & (CLS_CLASS|CLS_META|CLS_INITIALIZED|CLS_JAVA_HYBRID|CLS_JAVA_CLASS|CLS_HAS_CXX_STRUCTORS|CLS_HAS_LOAD_METHOD);
    duplicate->instance_size = original->instance_size;
    duplicate->ivars = original->ivars;
    // methodLists handled below
    duplicate->cache = (Cache)&_objc_empty_cache;
    duplicate->protocols = original->protocols;
    if (original->info & CLS_EXT) {
        duplicate->info |= original->info & (CLS_EXT|CLS_NO_PROPERTY_ARRAY);
        duplicate->ivar_layout = original->ivar_layout;
        if (original->ext) {
            duplicate->ext = (old_class_ext *)malloc(original->ext->size);
            memcpy(duplicate->ext, original->ext, original->ext->size);
        } else {
            duplicate->ext = nil;
        }
    }

    // Method lists are deep-copied so they can be stomped.
    originalMethods = (old_method **)class_copyMethodList(original, &count);
    if (originalMethods) {
        duplicateMethods = (old_method_list *)
            calloc(sizeof(old_method_list) + 
                   (count-1)*sizeof(old_method), 1);
        duplicateMethods->obsolete = fixed_up_method_list;
        duplicateMethods->method_count = count;
        for (i = 0; i < count; i++) {
            duplicateMethods->method_list[i] = *(originalMethods[i]);
        }
        duplicate->methodLists = (old_method_list **)duplicateMethods;
        duplicate->info |= CLS_NO_METHOD_ARRAY;
        free(originalMethods);
    }

    mutex_locker_t lock(classLock);
    NXHashInsert(class_hash, duplicate);
    objc_addRegisteredClass(duplicate);

    return duplicate;
}


void objc_disposeClassPair(Class cls)
{
    if (!(cls->info & (CLS_CONSTRUCTED|CLS_CONSTRUCTING))  ||  
        !(cls->ISA()->info & (CLS_CONSTRUCTED|CLS_CONSTRUCTING))) 
    {
        // class not allocated with objc_allocateClassPair
        // disposing still-unregistered class is OK!
        _objc_inform("objc_disposeClassPair: class '%s' was not "
                     "allocated with objc_allocateClassPair!", cls->name);
        return;
    }

    if (ISMETA(cls)) {
        _objc_inform("objc_disposeClassPair: class '%s' is a metaclass, "
                     "not a class!", cls->name);
        return;
    }

    mutex_locker_t lock(classLock);
    NXHashRemove(class_hash, cls);
    objc_removeRegisteredClass(cls);
    unload_class(cls->ISA());
    unload_class(cls);
}


/***********************************************************************
* objc_constructInstance
* Creates an instance of `cls` at the location pointed to by `bytes`. 
* `bytes` must point to at least class_getInstanceSize(cls) bytes of 
*   well-aligned zero-filled memory.
* The new object's isa is set. Any C++ constructors are called.
* Returns `bytes` if successful. Returns nil if `cls` or `bytes` is 
*   nil, or if C++ constructors fail.
**********************************************************************/
id 
objc_constructInstance(Class cls, void *bytes) 
{
    if (!cls  ||  !bytes) return nil;

    id obj = (id)bytes;

    obj->initIsa(cls);

    if (cls->hasCxxCtor()) {
        return object_cxxConstructFromClass(obj, cls);
    } else {
        return obj;
    }
}


/***********************************************************************
* _class_createInstanceFromZone.  Allocate an instance of the
* specified class with the specified number of bytes for indexed
* variables, in the specified zone.  The isa field is set to the
* class, C++ default constructors are called, and all other fields are zeroed.
**********************************************************************/
id 
_class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone)
{
    void *bytes;
    size_t size;

    // Can't create something for nothing
    if (!cls) return nil;

    // Allocate and initialize
    size = cls->alignedInstanceSize() + extraBytes;

    // CF requires all objects be at least 16 bytes.
    if (size < 16) size = 16;

#if SUPPORT_GC
    if (UseGC) {
        bytes = auto_zone_allocate_object(gc_zone, size,
                                          AUTO_OBJECT_SCANNED, 0, 1);
    } else 
#endif
    if (zone) {
        bytes = malloc_zone_calloc((malloc_zone_t *)zone, 1, size);
    } else {
        bytes = calloc(1, size);
    }

    return objc_constructInstance(cls, bytes);
}


/***********************************************************************
* _class_createInstance.  Allocate an instance of the specified
* class with the specified number of bytes for indexed variables, in
* the default zone, using _class_createInstanceFromZone.
**********************************************************************/
static id _class_createInstance(Class cls, size_t extraBytes)
{
    return _class_createInstanceFromZone (cls, extraBytes, nil);
}


static id _object_copyFromZone(id oldObj, size_t extraBytes, void *zone) 
{
    id obj;
    size_t size;

    if (!oldObj) return nil;

    obj = (*_zoneAlloc)(oldObj->ISA(), extraBytes, zone);
    size = oldObj->ISA()->alignedInstanceSize() + extraBytes;
    
    // fixme need C++ copy constructor
    objc_memmove_collectable(obj, oldObj, size);
    
#if SUPPORT_GC
    if (UseGC) gc_fixup_weakreferences(obj, oldObj);
#endif
    
    return obj;
}


/***********************************************************************
* objc_destructInstance
* Destroys an instance without freeing memory. 
* Calls C++ destructors.
* Removes associative references.
* Returns `obj`. Does nothing if `obj` is nil.
* Be warned that GC DOES NOT CALL THIS. If you edit this, also edit finalize.
* CoreFoundation and other clients do call this under GC.
**********************************************************************/
void *objc_destructInstance(id obj) 
{
    if (obj) {
        Class isa = obj->getIsa();

        if (isa->hasCxxDtor()) {
            object_cxxDestruct(obj);
        }

        if (isa->instancesHaveAssociatedObjects()) {
            _object_remove_assocations(obj);
        }

        if (!UseGC) objc_clear_deallocating(obj);
    }

    return obj;
}

static id 
_object_dispose(id anObject) 
{
    if (anObject==nil) return nil;

    objc_destructInstance(anObject);
    
#if SUPPORT_GC
    if (UseGC) {
        auto_zone_retain(gc_zone, anObject); // gc free expects rc==1
    } else 
#endif
    {
        // only clobber isa for non-gc
        anObject->initIsa(_objc_getFreedObjectClass ()); 
    }
    free(anObject);
    return nil;
}

static id _object_copy(id oldObj, size_t extraBytes) 
{
    void *z = malloc_zone_from_ptr(oldObj);
    return _object_copyFromZone(oldObj, extraBytes,
					 z ? z : malloc_default_zone());
}

static id _object_reallocFromZone(id anObject, size_t nBytes, void *zone) 
{
    id newObject; 
    Class tmp;

    if (anObject == nil)
        __objc_error(nil, "reallocating nil object");

    if (anObject->ISA() == _objc_getFreedObjectClass ())
        __objc_error(anObject, "reallocating freed object");

    if (nBytes < anObject->ISA()->alignedInstanceSize())
        __objc_error(anObject, "(%s, %zu) requested size too small", 
                     object_getClassName(anObject), nBytes);

    // fixme need C++ copy constructor
    // fixme GC copy
    // Make sure not to modify space that has been declared free
    tmp = anObject->ISA(); 
    anObject->initIsa(_objc_getFreedObjectClass ());
    newObject = (id)malloc_zone_realloc((malloc_zone_t *)zone, anObject, nBytes);
    if (newObject) {
        newObject->initIsa(tmp);
    } else {
        // realloc failed, anObject is still alive
        anObject->initIsa(tmp);
    }
    return newObject;
}


static id _object_realloc(id anObject, size_t nBytes) 
{
    void *z = malloc_zone_from_ptr(anObject);
    return _object_reallocFromZone(anObject,
					    nBytes,
					    z ? z : malloc_default_zone());
}

id (*_alloc)(Class, size_t) = _class_createInstance;
id (*_copy)(id, size_t) = _object_copy;
id (*_realloc)(id, size_t) = _object_realloc;
id (*_dealloc)(id) = _object_dispose;
id (*_zoneAlloc)(Class, size_t, void *) = _class_createInstanceFromZone;
id (*_zoneCopy)(id, size_t, void *) = _object_copyFromZone;
id (*_zoneRealloc)(id, size_t, void *) = _object_reallocFromZone;
void (*_error)(id, const char *, va_list) = _objc_error;


id class_createInstance(Class cls, size_t extraBytes)
{
    if (UseGC) {
        return _class_createInstance(cls, extraBytes);
    } else {
        return (*_alloc)(cls, extraBytes);
    }
}

id class_createInstanceFromZone(Class cls, size_t extraBytes, void *z)
{
    OBJC_WARN_DEPRECATED;
    if (UseGC) {
        return _class_createInstanceFromZone(cls, extraBytes, z);
    } else {
        return (*_zoneAlloc)(cls, extraBytes, z);
    }
}

unsigned class_createInstances(Class cls, size_t extraBytes, 
                               id *results, unsigned num_requested)
{
    if (UseGC  ||  _alloc == &_class_createInstance) {
        return _class_createInstancesFromZone(cls, extraBytes, nil, 
                                              results, num_requested);
    } else {
        // _alloc in use, which isn't understood by the batch allocator
        return 0;
    }
}

id object_copy(id obj, size_t extraBytes) 
{
    if (UseGC) return _object_copy(obj, extraBytes);
    else return (*_copy)(obj, extraBytes); 
}

id object_copyFromZone(id obj, size_t extraBytes, void *z) 
{
    OBJC_WARN_DEPRECATED;
    if (UseGC) return _object_copyFromZone(obj, extraBytes, z);
    else return (*_zoneCopy)(obj, extraBytes, z); 
}

id object_dispose(id obj) 
{
    if (UseGC) return _object_dispose(obj);
    else return (*_dealloc)(obj); 
}

id object_realloc(id obj, size_t nBytes) 
{
    OBJC_WARN_DEPRECATED;
    if (UseGC) return _object_realloc(obj, nBytes);
    else return (*_realloc)(obj, nBytes); 
}

id object_reallocFromZone(id obj, size_t nBytes, void *z) 
{
    OBJC_WARN_DEPRECATED;
    if (UseGC) return _object_reallocFromZone(obj, nBytes, z);
    else return (*_zoneRealloc)(obj, nBytes, z); 
}


/***********************************************************************
* object_getIndexedIvars.
**********************************************************************/
void *object_getIndexedIvars(id obj)
{
    // ivars are tacked onto the end of the object
    if (!obj) return nil;
    if (obj->isTaggedPointer()) return nil;
    return ((char *) obj) + obj->ISA()->alignedInstanceSize();
}


// ProKit SPI
Class class_setSuperclass(Class cls, Class newSuper)
{
    Class oldSuper = cls->superclass;
    set_superclass(cls, newSuper, NO);
    flush_caches(cls, YES);
    return oldSuper;
}
#endif
