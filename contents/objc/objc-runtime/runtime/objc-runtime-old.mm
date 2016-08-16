/*
 * Copyright (c) 1999-2007 Apple Inc.  All Rights Reserved.
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
* objc-runtime-old.m
* Support for old-ABI classes and images.
**********************************************************************/

/***********************************************************************
 * Class loading and connecting (GrP 2004-2-11)
 *
 * When images are loaded (during program startup or otherwise), the 
 * runtime needs to load classes and categories from the images, connect 
 * classes to superclasses and categories to parent classes, and call 
 * +load methods. 
 * 
 * The Objective-C runtime can cope with classes arriving in any order. 
 * That is, a class may be discovered by the runtime before some 
 * superclass is known. To handle out-of-order class loads, the 
 * runtime uses a "pending class" system. 
 * 
 * (Historical note)
 * Panther and earlier: many classes arrived out-of-order because of 
 *   the poorly-ordered callback from dyld. However, the runtime's 
 *   pending mechanism only handled "missing superclass" and not 
 *   "present superclass but missing higher class". See Radar #3225652. 
 * Tiger: The runtime's pending mechanism was augmented to handle 
 *   arbitrary missing classes. In addition, dyld was rewritten and 
 *   now sends the callbacks in strictly bottom-up link order. 
 *   The pending mechanism may now be needed only for rare and 
 *   hard to construct programs.
 * (End historical note)
 * 
 * A class when first seen in an image is considered "unconnected". 
 * It is stored in `unconnected_class_hash`. If all of the class's 
 * superclasses exist and are already "connected", then the new class 
 * can be connected to its superclasses and moved to `class_hash` for 
 * normal use. Otherwise, the class waits in `unconnected_class_hash` 
 * until the superclasses finish connecting.
 * 
 * A "connected" class is 
 * (1) in `class_hash`, 
 * (2) connected to its superclasses, 
 * (3) has no unconnected superclasses, 
 * (4) is otherwise initialized and ready for use, and 
 * (5) is eligible for +load if +load has not already been called. 
 * 
 * An "unconnected" class is 
 * (1) in `unconnected_class_hash`, 
 * (2) not connected to its superclasses, 
 * (3) has an immediate superclass which is either missing or unconnected, 
 * (4) is not ready for use, and 
 * (5) is not yet eligible for +load.
 * 
 * Image mapping is NOT CURRENTLY THREAD-SAFE with respect to just about 
 * anything. Image mapping IS RE-ENTRANT in several places: superclass 
 * lookup may cause ZeroLink to load another image, and +load calls may 
 * cause dyld to load another image.
 * 
 * Image mapping sequence:
 * 
 * Read all classes in all new images. 
 *   Add them all to unconnected_class_hash. 
 *   Note any +load implementations before categories are attached.
 *   Attach any pending categories.
 * Read all categories in all new images. 
 *   Attach categories whose parent class exists (connected or not), 
 *     and pend the rest.
 *   Mark them all eligible for +load (if implemented), even if the 
 *     parent class is missing.
 * Try to connect all classes in all new images. 
 *   If the superclass is missing, pend the class
 *   If the superclass is unconnected, try to recursively connect it
 *   If the superclass is connected:
 *     connect the class
 *     mark the class eligible for +load, if implemented
 *     fix up any pended classrefs referring to the class
 *     connect any pended subclasses of the class
 * Resolve selector refs and class refs in all new images.
 *   Class refs whose classes still do not exist are pended.
 * Fix up protocol objects in all new images.
 * Call +load for classes and categories.
 *   May include classes or categories that are not in these images, 
 *     but are newly eligible because of these image.
 *   Class +loads will be called superclass-first because of the 
 *     superclass-first nature of the connecting process.
 *   Category +load needs to be deferred until the parent class is 
 *     connected and has had its +load called.
 * 
 * Performance: all classes are read before any categories are read. 
 * Fewer categories need be pended for lack of a parent class.
 * 
 * Performance: all categories are attempted to be attached before 
 * any classes are connected. Fewer class caches need be flushed. 
 * (Unconnected classes and their respective subclasses are guaranteed 
 * to be un-messageable, so their caches will be empty.)
 * 
 * Performance: all classes are read before any classes are connected. 
 * Fewer classes need be pended for lack of a superclass.
 * 
 * Correctness: all selector and class refs are fixed before any 
 * protocol fixups or +load methods. libobjc itself contains selector 
 * and class refs which are used in protocol fixup and +load.
 * 
 * Correctness: +load methods are scheduled in bottom-up link order. 
 * This constraint is in addition to superclass order. Some +load 
 * implementations expect to use another class in a linked-to library, 
 * even if the two classes don't share a direct superclass relationship.
 * 
 * Correctness: all classes are scanned for +load before any categories 
 * are attached. Otherwise, if a category implements +load and its class 
 * has no class methods, the class's +load scan would find the category's 
 * +load method, which would then be called twice.
 *
 * Correctness: pended class refs are not fixed up until the class is 
 * connected. Classes with missing weak superclasses remain unconnected. 
 * Class refs to classes with missing weak superclasses must be nil. 
 * Therefore class refs to unconnected classes must remain un-fixed.
 * 
 **********************************************************************/

#if !__OBJC2__

#include "objc-private.h"
#include "objc-runtime-old.h"
#include "objc-file-old.h"
#include "objc-cache-old.h"
#include "objc-loadmethod.h"


typedef struct _objc_unresolved_category
{
    struct _objc_unresolved_category *next;
    old_category *cat;  // may be nil
    long version;
} _objc_unresolved_category;

typedef struct _PendingSubclass
{
    Class subclass;  // subclass to finish connecting; may be nil
    struct _PendingSubclass *next;
} PendingSubclass;

typedef struct _PendingClassRef
{
    Class *ref;  // class reference to fix up; may be nil
                             // (ref & 1) is a metaclass reference
    struct _PendingClassRef *next;
} PendingClassRef;


static uintptr_t classHash(void *info, Class data);
static int classIsEqual(void *info, Class name, Class cls);
static int _objc_defaultClassHandler(const char *clsName);
static inline NXMapTable *pendingClassRefsMapTable(void);
static inline NXMapTable *pendingSubclassesMapTable(void);
static void pendClassInstallation(Class cls, const char *superName);
static void pendClassReference(Class *ref, const char *className, bool isMeta);
static void resolve_references_to_class(Class cls);
static void resolve_subclasses_of_class(Class cls);
static void really_connect_class(Class cls, Class supercls);
static bool connect_class(Class cls);
static void  map_method_descs (struct objc_method_description_list * methods, bool copy);
static void _objcTweakMethodListPointerForClass(Class cls);
static inline void _objc_add_category(Class cls, old_category *category, int version);
static bool _objc_add_category_flush_caches(Class cls, old_category *category, int version);
static _objc_unresolved_category *reverse_cat(_objc_unresolved_category *cat);
static void resolve_categories_for_class(Class cls);
static bool _objc_register_category(old_category *cat, int version);


// Function called when a class is loaded from an image
void (*callbackFunction)(Class, Category) = 0;

// Hash table of classes
NXHashTable *		class_hash = 0;
static NXHashTablePrototype	classHashPrototype =
{
    (uintptr_t (*) (const void *, const void *))			classHash,
    (int (*)(const void *, const void *, const void *))	classIsEqual,
    NXNoEffectFree, 0
};

// Hash table of unconnected classes
static NXHashTable *unconnected_class_hash = nil;

// Exported copy of class_hash variable (hook for debugging tools)
NXHashTable *_objc_debug_class_hash = nil;

// Category and class registries
// Keys are COPIES of strings, to prevent stale pointers with unloaded bundles
// Use NXMapKeyCopyingInsert and NXMapKeyFreeingRemove
static NXMapTable *		category_hash = nil;

// Keys are COPIES of strings, to prevent stale pointers with unloaded bundles
// Use NXMapKeyCopyingInsert and NXMapKeyFreeingRemove
static NXMapTable *		pendingClassRefsMap = nil;
static NXMapTable *		pendingSubclassesMap = nil;

// Protocols
static NXMapTable *protocol_map = nil;      // name -> protocol
static NXMapTable *protocol_ext_map = nil;  // protocol -> protocol ext

// Function pointer objc_getClass calls through when class is not found
static int			(*objc_classHandler) (const char *) = _objc_defaultClassHandler;

// Function pointer called by objc_getClass and objc_lookupClass when 
// class is not found. _objc_classLoader is called before objc_classHandler.
static BOOL (*_objc_classLoader)(const char *) = nil;


/***********************************************************************
* objc_dump_class_hash.  Log names of all known classes.
**********************************************************************/
void objc_dump_class_hash(void)
{
    NXHashTable *table;
    unsigned count;
    Class data;
    NXHashState state;

    table = class_hash;
    count = 0;
    state = NXInitHashState (table);
    while (NXNextHashState (table, &state, (void **) &data))
        printf ("class %d: %s\n", ++count, data->nameForLogging());
}


/***********************************************************************
* _objc_init_class_hash.  Return the class lookup table, create it if
* necessary.
**********************************************************************/
void _objc_init_class_hash(void)
{
    // Do nothing if class hash table already exists
    if (class_hash)
        return;

    // class_hash starts small, with only enough capacity for libobjc itself. 
    // If a second library is found by map_images(), class_hash is immediately 
    // resized to capacity 1024 to cut down on rehashes. 
    // Old numbers: A smallish Foundation+AppKit program will have
    // about 520 classes.  Larger apps (like IB or WOB) have more like
    // 800 classes.  Some customers have massive quantities of classes.
    // Foundation-only programs aren't likely to notice the ~6K loss.
    class_hash = NXCreateHashTable(classHashPrototype, 16, nil);
    _objc_debug_class_hash = class_hash;
}


/***********************************************************************
* objc_getClassList.  Return the known classes.
**********************************************************************/
int objc_getClassList(Class *buffer, int bufferLen) 
{
    NXHashState state;
    Class cls;
    int cnt, num;

    mutex_locker_t lock(classLock);
    if (!class_hash) return 0;

    num = NXCountHashTable(class_hash);
    if (nil == buffer) return num;

    cnt = 0;
    state = NXInitHashState(class_hash);
    while (cnt < bufferLen  &&  
           NXNextHashState(class_hash, &state, (void **)&cls)) 
    {
        buffer[cnt++] = cls;
    }

    return num;
}


/***********************************************************************
* objc_copyClassList
* Returns pointers to all classes.
* This requires all classes be realized, which is regretfully non-lazy.
* 
* outCount may be nil. *outCount is the number of classes returned. 
* If the returned array is not nil, it is nil-terminated and must be 
* freed with free().
* Locking: acquires classLock
**********************************************************************/
Class *
objc_copyClassList(unsigned int *outCount)
{
    Class *result;
    unsigned int count;

    mutex_locker_t lock(classLock);
    result = nil;
    count = class_hash ? NXCountHashTable(class_hash) : 0;

    if (count > 0) {
        Class cls;
        NXHashState state = NXInitHashState(class_hash);
        result = (Class *)malloc((1+count) * sizeof(Class));
        count = 0;
        while (NXNextHashState(class_hash, &state, (void **)&cls)) {
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
* Locking: acquires classLock
**********************************************************************/
Protocol * __unsafe_unretained *
objc_copyProtocolList(unsigned int *outCount) 
{
    int count, i;
    Protocol *proto;
    const char *name;
    NXMapState state;
    Protocol **result;

    mutex_locker_t lock(classLock);

    count = NXCountMapTable(protocol_map);
    if (count == 0) {
        if (outCount) *outCount = 0;
        return nil;
    }

    result = (Protocol **)calloc(1 + count, sizeof(Protocol *));

    i = 0;
    state = NXInitMapState(protocol_map);
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
* objc_getClasses.  Return class lookup table.
*
* NOTE: This function is very dangerous, since you cannot safely use
* the hashtable without locking it, and the lock is private!
**********************************************************************/
void *objc_getClasses(void)
{
    OBJC_WARN_DEPRECATED;

    // Return the class lookup hash table
    return class_hash;
}


/***********************************************************************
* classHash.
**********************************************************************/
static uintptr_t classHash(void *info, Class data)
{
    // Nil classes hash to zero
    if (!data)
        return 0;

    // Call through to real hash function
    return _objc_strhash (data->mangledName());
}

/***********************************************************************
* classIsEqual.  Returns whether the class names match.  If we ever
* check more than the name, routines like objc_lookUpClass have to
* change as well.
**********************************************************************/
static int classIsEqual(void *info, Class name, Class cls)
{
    // Standard string comparison
    return strcmp(name->mangledName(), cls->mangledName()) == 0;
}


// Unresolved future classes
static NXHashTable *future_class_hash = nil;

// Resolved future<->original classes
static NXMapTable *future_class_to_original_class_map = nil;
static NXMapTable *original_class_to_future_class_map = nil;

// CF requests about 20 future classes; HIToolbox requests one.
#define FUTURE_COUNT 32


/***********************************************************************
* setOriginalClassForFutureClass
* Record resolution of a future class. 
**********************************************************************/
static void setOriginalClassForFutureClass(Class futureClass, 
                                           Class originalClass)
{
    if (!future_class_to_original_class_map) {
        future_class_to_original_class_map =
            NXCreateMapTable(NXPtrValueMapPrototype, FUTURE_COUNT);
        original_class_to_future_class_map =
            NXCreateMapTable(NXPtrValueMapPrototype, FUTURE_COUNT);
    }

    NXMapInsert (future_class_to_original_class_map,
                 futureClass, originalClass);
    NXMapInsert (original_class_to_future_class_map,
                 originalClass, futureClass);

    if (PrintFuture) {
        _objc_inform("FUTURE: using %p instead of %p for %s", (void*)futureClass, (void*)originalClass, originalClass->name);
    }
}

/***********************************************************************
* getOriginalClassForFutureClass
* getFutureClassForOriginalClass
* Switch between a future class and its corresponding original class.
* The future class is the one actually in use.
* The original class is the one from disk.
**********************************************************************/
/*
static Class
getOriginalClassForFutureClass(Class futureClass)
{
    if (!future_class_to_original_class_map) return Nil;
    return NXMapGet (future_class_to_original_class_map, futureClass);
}
*/
static Class
getFutureClassForOriginalClass(Class originalClass)
{
    if (!original_class_to_future_class_map) return Nil;
    return (Class)NXMapGet(original_class_to_future_class_map, originalClass);
}


/***********************************************************************
* makeFutureClass
* Initialize the memory in *cls with an unresolved future class with the 
* given name. The memory is recorded in future_class_hash.
**********************************************************************/
static void makeFutureClass(Class cls, const char *name)
{
    // CF requests about 20 future classes, plus HIToolbox has one.
    if (!future_class_hash) {
        future_class_hash = 
            NXCreateHashTable(classHashPrototype, FUTURE_COUNT, nil);
    }

    cls->name = strdup(name);
    NXHashInsert(future_class_hash, cls);

    if (PrintFuture) {
        _objc_inform("FUTURE: reserving %p for %s", (void*)cls, name);
    }
}


/***********************************************************************
* _objc_allocateFutureClass
* Allocate an unresolved future class for the given class name.
* Returns any existing allocation if one was already made.
* Assumes the named class doesn't exist yet.
* Not thread safe.
**********************************************************************/
Class _objc_allocateFutureClass(const char *name)
{
    Class cls;

    if (future_class_hash) {
        objc_class query;
        query.name = name;
        if ((cls = (Class)NXHashGet(future_class_hash, &query))) {
            // Already have a future class for this name.
            return cls;
        }
    } 

    cls = _calloc_class(sizeof(objc_class));
    makeFutureClass(cls, name);
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

bool objc_class::isFuture() 
{
    return future_class_hash  &&  NXHashGet(future_class_hash, this);
}


/***********************************************************************
* _objc_defaultClassHandler.  Default objc_classHandler.  Does nothing.
**********************************************************************/
static int _objc_defaultClassHandler(const char *clsName)
{
    // Return zero so objc_getClass doesn't bother re-searching
    return 0;
}

/***********************************************************************
* objc_setClassHandler.  Set objc_classHandler to the specified value.
*
* NOTE: This should probably deal with userSuppliedHandler being nil,
* because the objc_classHandler caller does not check... it would bus
* error.  It would make sense to handle nil by restoring the default
* handler.  Is anyone hacking with this, though?
**********************************************************************/
void objc_setClassHandler(int (*userSuppliedHandler)(const char *))
{
    OBJC_WARN_DEPRECATED;

    objc_classHandler = userSuppliedHandler;
}


/***********************************************************************
* _objc_setClassLoader
* Similar to objc_setClassHandler, but objc_classLoader is used for 
* both objc_getClass() and objc_lookupClass(), and objc_classLoader 
* pre-empts objc_classHandler. 
**********************************************************************/
void _objc_setClassLoader(BOOL (*newClassLoader)(const char *))
{
    _objc_classLoader = newClassLoader;
}


/***********************************************************************
* objc_getProtocol
* Get a protocol by name, or nil.
**********************************************************************/
Protocol *objc_getProtocol(const char *name)
{
    mutex_locker_t lock(classLock);
    if (!protocol_map) return nil;
    return (Protocol *)NXMapGet(protocol_map, name);
}


/***********************************************************************
* look_up_class
* Map a class name to a class using various methods.
* This is the common implementation of objc_lookUpClass and objc_getClass, 
* and is also used internally to get additional search options.
* Sequence:
* 1. class_hash
* 2. unconnected_class_hash (optional)
* 3. classLoader callback
* 4. classHandler callback (optional)
**********************************************************************/
Class look_up_class(const char *aClassName, bool includeUnconnected, 
                    bool includeClassHandler)
{
    bool includeClassLoader = YES; // class loader cannot be skipped
    Class result = nil;
    struct objc_class query;

    query.name = aClassName;

 retry:

    if (!result  &&  class_hash) {
        // Check ordinary classes
        mutex_locker_t lock(classLock);
        result = (Class)NXHashGet(class_hash, &query);
    }

    if (!result  &&  includeUnconnected  &&  unconnected_class_hash) {
        // Check not-yet-connected classes
        mutex_locker_t lock(classLock);
        result = (Class)NXHashGet(unconnected_class_hash, &query);
    }

    if (!result  &&  includeClassLoader  &&  _objc_classLoader) {
        // Try class loader callback
        if ((*_objc_classLoader)(aClassName)) {
            // Re-try lookup without class loader
            includeClassLoader = NO;
            goto retry;
        }
    }

    if (!result  &&  includeClassHandler  &&  objc_classHandler) {
        // Try class handler callback
        if ((*objc_classHandler)(aClassName)) {
            // Re-try lookup without class handler or class loader
            includeClassLoader = NO;
            includeClassHandler = NO;
            goto retry;
        }
    }

    return result;
}


/***********************************************************************
* objc_class::isConnected
* Returns TRUE if class cls is connected. 
* A connected class has either a connected superclass or a nil superclass, 
* and is present in class_hash.
**********************************************************************/
bool objc_class::isConnected()
{
    mutex_locker_t lock(classLock);
    return NXHashMember(class_hash, this);
}


/***********************************************************************
* pendingClassRefsMapTable.  Return a pointer to the lookup table for
* pending class refs.
**********************************************************************/
static inline NXMapTable *pendingClassRefsMapTable(void)
{
    // Allocate table if needed
    if (!pendingClassRefsMap) {
        pendingClassRefsMap = NXCreateMapTable(NXStrValueMapPrototype, 10);
    }
    
    // Return table pointer
    return pendingClassRefsMap;
}


/***********************************************************************
* pendingSubclassesMapTable.  Return a pointer to the lookup table for
* pending subclasses.
**********************************************************************/
static inline NXMapTable *pendingSubclassesMapTable(void)
{
    // Allocate table if needed
    if (!pendingSubclassesMap) {
        pendingSubclassesMap = NXCreateMapTable(NXStrValueMapPrototype, 10);
    }
    
    // Return table pointer
    return pendingSubclassesMap;
}


/***********************************************************************
* pendClassInstallation
* Finish connecting class cls when its superclass becomes connected.
* Check for multiple pends of the same class because connect_class does not.
**********************************************************************/
static void pendClassInstallation(Class cls, const char *superName)
{
    NXMapTable *table;
    PendingSubclass *pending;
    PendingSubclass *oldList;
    PendingSubclass *l;
    
    // Create and/or locate pending class lookup table
    table = pendingSubclassesMapTable ();

    // Make sure this class isn't already in the pending list.
    oldList = (PendingSubclass *)NXMapGet(table, superName);
    for (l = oldList; l != nil; l = l->next) {
        if (l->subclass == cls) return;  // already here, nothing to do
    }
    
    // Create entry referring to this class
    pending = (PendingSubclass *)malloc(sizeof(PendingSubclass));
    pending->subclass = cls;
    
    // Link new entry into head of list of entries for this class
    pending->next = oldList;
    
    // (Re)place entry list in the table
    NXMapKeyCopyingInsert (table, superName, pending);
}


/***********************************************************************
* pendClassReference
* Fix up a class ref when the class with the given name becomes connected.
**********************************************************************/
static void pendClassReference(Class *ref, const char *className, bool isMeta)
{
    NXMapTable *table;
    PendingClassRef *pending;
    
    // Create and/or locate pending class lookup table
    table = pendingClassRefsMapTable ();
    
    // Create entry containing the class reference
    pending = (PendingClassRef *)malloc(sizeof(PendingClassRef));
    pending->ref = ref;
    if (isMeta) {
        pending->ref = (Class *)((uintptr_t)pending->ref | 1);
    }
    
    // Link new entry into head of list of entries for this class
    pending->next = (PendingClassRef *)NXMapGet(table, className);
    
    // (Re)place entry list in the table
    NXMapKeyCopyingInsert (table, className, pending);

    if (PrintConnecting) {
        _objc_inform("CONNECT: pended reference to class '%s%s' at %p", 
                     className, isMeta ? " (meta)" : "", (void *)ref);
    }
}


/***********************************************************************
* resolve_references_to_class
* Fix up any pending class refs to this class.
**********************************************************************/
static void resolve_references_to_class(Class cls)
{
    PendingClassRef *pending;
    
    if (!pendingClassRefsMap) return;  // no unresolved refs for any class

    pending = (PendingClassRef *)NXMapGet(pendingClassRefsMap, cls->name); 
    if (!pending) return;  // no unresolved refs for this class

    NXMapKeyFreeingRemove(pendingClassRefsMap, cls->name);

    if (PrintConnecting) {
        _objc_inform("CONNECT: resolving references to class '%s'", cls->name);
    }

    while (pending) {
        PendingClassRef *next = pending->next;
        if (pending->ref) {
            bool isMeta = (uintptr_t)pending->ref & 1;
            Class *ref = 
                (Class *)((uintptr_t)pending->ref & ~(uintptr_t)1);
            *ref = isMeta ? cls->ISA() : cls;
        }
        free(pending);
        pending = next;
    }

    if (NXCountMapTable(pendingClassRefsMap) == 0) {
        NXFreeMapTable(pendingClassRefsMap);
        pendingClassRefsMap = nil;
    }
}


/***********************************************************************
* resolve_subclasses_of_class
* Fix up any pending subclasses of this class.
**********************************************************************/
static void resolve_subclasses_of_class(Class cls)
{
    PendingSubclass *pending;
    
    if (!pendingSubclassesMap) return;  // no unresolved subclasses 

    pending = (PendingSubclass *)NXMapGet(pendingSubclassesMap, cls->name); 
    if (!pending) return;  // no unresolved subclasses for this class

    NXMapKeyFreeingRemove(pendingSubclassesMap, cls->name);

    // Destroy the pending table if it's now empty, to save memory.
    if (NXCountMapTable(pendingSubclassesMap) == 0) {
        NXFreeMapTable(pendingSubclassesMap);
        pendingSubclassesMap = nil;
    }

    if (PrintConnecting) {
        _objc_inform("CONNECT: resolving subclasses of class '%s'", cls->name);
    }

    while (pending) {
        PendingSubclass *next = pending->next;
        if (pending->subclass) connect_class(pending->subclass);
        free(pending);
        pending = next;
    }
}


/***********************************************************************
* really_connect_class
* Connect cls to superclass supercls unconditionally.
* Also adjust the class hash tables and handle pended subclasses.
*
* This should be called from connect_class() ONLY.
**********************************************************************/
static void really_connect_class(Class cls,
                                 Class supercls)
{
    Class oldCls;

    // Connect superclass pointers.
    set_superclass(cls, supercls, YES);

    // Update GC layouts
    // For paranoia, this is a conservative update: 
    // only non-strong -> strong and weak -> strong are corrected.
    if (UseGC  &&  supercls  &&  
        (cls->info & CLS_EXT)  &&  (supercls->info & CLS_EXT)) 
    {
        bool layoutChanged;
        layout_bitmap ivarBitmap = 
            layout_bitmap_create(cls->ivar_layout, 
                                 cls->instance_size, 
                                 cls->instance_size, NO);

        layout_bitmap superBitmap = 
            layout_bitmap_create(supercls->ivar_layout, 
                                 supercls->instance_size, 
                                 supercls->instance_size, NO);

        // non-strong -> strong: bits set in super should be set in sub
        layoutChanged = layout_bitmap_or(ivarBitmap, superBitmap, cls->name);
        layout_bitmap_free(superBitmap);
        
        if (layoutChanged) {
            layout_bitmap weakBitmap = {};
            bool weakLayoutChanged = NO;

            if (cls->ext  &&  cls->ext->weak_ivar_layout) {
                // weak -> strong: strong bits should be cleared in weak layout
                // This is a subset of non-strong -> strong
                weakBitmap = 
                    layout_bitmap_create(cls->ext->weak_ivar_layout, 
                                         cls->instance_size, 
                                         cls->instance_size, YES);

                weakLayoutChanged = 
                    layout_bitmap_clear(weakBitmap, ivarBitmap, cls->name);
            } else {
                // no existing weak ivars, so no weak -> strong changes
            }

            // Rebuild layout strings. 
            if (PrintIvars) {
                _objc_inform("IVARS: gc layout changed "
                             "for class %s (super %s)",
                             cls->name, supercls->name);
                if (weakLayoutChanged) {
                    _objc_inform("IVARS: gc weak layout changed "
                                 "for class %s (super %s)",
                                 cls->name, supercls->name);
                }
            }
            cls->ivar_layout = layout_string_create(ivarBitmap);
            if (weakLayoutChanged) {
                cls->ext->weak_ivar_layout = layout_string_create(weakBitmap);
            }

            layout_bitmap_free(weakBitmap);
        }
        
        layout_bitmap_free(ivarBitmap);
    }

    // Done!
    cls->info |= CLS_CONNECTED;

    {
        mutex_locker_t lock(classLock);
        
        // Update hash tables. 
        NXHashRemove(unconnected_class_hash, cls);
        oldCls = (Class)NXHashInsert(class_hash, cls);
        objc_addRegisteredClass(cls);
        
        // Delete unconnected_class_hash if it is now empty.
        if (NXCountHashTable(unconnected_class_hash) == 0) {
            NXFreeHashTable(unconnected_class_hash);
            unconnected_class_hash = nil;
        }
        
        // No duplicate classes allowed. 
        // Duplicates should have been rejected by _objc_read_classes_from_image
        assert(!oldCls);
    }        
 
    // Fix up pended class refs to this class, if any
    resolve_references_to_class(cls);

    // Connect newly-connectable subclasses
    resolve_subclasses_of_class(cls);

    // GC debugging: make sure all classes with -dealloc also have -finalize
    if (DebugFinalizers) {
        extern IMP findIMPInClass(Class cls, SEL sel);
        if (findIMPInClass(cls, sel_getUid("dealloc"))  &&  
            ! findIMPInClass(cls, sel_getUid("finalize")))
        {
            _objc_inform("GC: class '%s' implements -dealloc but not -finalize", cls->name);
        }
    }

    // Debugging: if this class has ivars, make sure this class's ivars don't 
    // overlap with its super's. This catches some broken fragile base classes.
    // Do not use super->instance_size vs. self->ivar[0] to check this. 
    // Ivars may be packed across instance_size boundaries.
    if (DebugFragileSuperclasses  &&  cls->ivars  &&  cls->ivars->ivar_count) {
        Class ivar_cls = supercls;

        // Find closest superclass that has some ivars, if one exists.
        while (ivar_cls  &&  
               (!ivar_cls->ivars || ivar_cls->ivars->ivar_count == 0))
        {
            ivar_cls = ivar_cls->superclass;
        }

        if (ivar_cls) {
            // Compare superclass's last ivar to this class's first ivar
            old_ivar *super_ivar = 
                &ivar_cls->ivars->ivar_list[ivar_cls->ivars->ivar_count - 1];
            old_ivar *self_ivar = 
                &cls->ivars->ivar_list[0];

            // fixme could be smarter about super's ivar size
            if (self_ivar->ivar_offset <= super_ivar->ivar_offset) {
                _objc_inform("WARNING: ivars of superclass '%s' and "
                             "subclass '%s' overlap; superclass may have "
                             "changed since subclass was compiled", 
                             ivar_cls->name, cls->name);
            }
        }
    }
}


/***********************************************************************
* connect_class
* Connect class cls to its superclasses, if possible.
* If cls becomes connected, move it from unconnected_class_hash 
*   to connected_class_hash.
* Returns TRUE if cls is connected.
* Returns FALSE if cls could not be connected for some reason 
*   (missing superclass or still-unconnected superclass)
**********************************************************************/
static bool connect_class(Class cls)
{
    if (cls->isConnected()) {
        // This class is already connected to its superclass.
        // Do nothing.
        return TRUE;
    }
    else if (cls->superclass == nil) {
        // This class is a root class. 
        // Connect it to itself. 

        if (PrintConnecting) {
            _objc_inform("CONNECT: class '%s' now connected (root class)", 
                        cls->name);
        }

        really_connect_class(cls, nil);
        return TRUE;
    }
    else {
        // This class is not a root class and is not yet connected.
        // Connect it if its superclass and root class are already connected. 
        // Otherwise, add this class to the to-be-connected list, 
        // pending the completion of its superclass and root class.

        // At this point, cls->superclass and cls->ISA()->ISA() are still STRINGS
        char *supercls_name = (char *)cls->superclass;
        Class supercls;

        // YES unconnected, YES class handler
        if (nil == (supercls = look_up_class(supercls_name, YES, YES))) {
            // Superclass does not exist yet.
            // pendClassInstallation will handle duplicate pends of this class
            pendClassInstallation(cls, supercls_name);

            if (PrintConnecting) {
                _objc_inform("CONNECT: class '%s' NOT connected (missing super)", cls->name);
            }
            return FALSE;
        }
        
        if (! connect_class(supercls)) {
            // Superclass exists but is not yet connected.
            // pendClassInstallation will handle duplicate pends of this class
            pendClassInstallation(cls, supercls_name);

            if (PrintConnecting) {
                _objc_inform("CONNECT: class '%s' NOT connected (unconnected super)", cls->name);
            }
            return FALSE;
        }

        // Superclass exists and is connected. 
        // Connect this class to the superclass.
        
        if (PrintConnecting) {
            _objc_inform("CONNECT: class '%s' now connected", cls->name);
        }

        really_connect_class(cls, supercls);
        return TRUE;
    } 
}


/***********************************************************************
* _objc_read_categories_from_image.
* Read all categories from the given image. 
* Install them on their parent classes, or register them for later 
*   installation. 
* Returns YES if some method caches now need to be flushed.
**********************************************************************/
static bool _objc_read_categories_from_image (header_info *  hi)
{
    Module		mods;
    size_t	midx;
    bool needFlush = NO;

    if (_objcHeaderIsReplacement(hi)) {
        // Ignore any categories in this image
        return NO;
    }


    // Major loop - process all modules in the header
    mods = hi->mod_ptr;

    // NOTE: The module and category lists are traversed backwards 
    // to preserve the pre-10.4 processing order. Changing the order 
    // would have a small chance of introducing binary compatibility bugs.
    midx = hi->mod_count;
    while (midx-- > 0) {
        unsigned int	index;
        unsigned int	total;
        
        // Nothing to do for a module without a symbol table
        if (mods[midx].symtab == nil)
            continue;
        
        // Total entries in symbol table (class entries followed
        // by category entries)
        total = mods[midx].symtab->cls_def_cnt +
            mods[midx].symtab->cat_def_cnt;
        
        // Minor loop - register all categories from given module
        index = total;
        while (index-- > mods[midx].symtab->cls_def_cnt) {
            old_category *cat = (old_category *)mods[midx].symtab->defs[index];
            needFlush |= _objc_register_category(cat, (int)mods[midx].version);
        }
    }

    return needFlush;
}


/***********************************************************************
* _objc_read_classes_from_image.
* Read classes from the given image, perform assorted minor fixups, 
*   scan for +load implementation.
* Does not connect classes to superclasses. 
* Does attach pended categories to the classes.
* Adds all classes to unconnected_class_hash. class_hash is unchanged.
**********************************************************************/
static void _objc_read_classes_from_image(header_info *hi)
{
    unsigned int	index;
    unsigned int	midx;
    Module		mods;
    int 		isBundle = headerIsBundle(hi);

    if (_objcHeaderIsReplacement(hi)) {
        // Ignore any classes in this image
        return;
    }

    // class_hash starts small, enough only for libobjc itself. 
    // If other Objective-C libraries are found, immediately resize 
    // class_hash, assuming that Foundation and AppKit are about 
    // to add lots of classes.
    {
        mutex_locker_t lock(classLock);
        if (hi->mhdr != libobjc_header && _NXHashCapacity(class_hash) < 1024) {
            _NXHashRehashToCapacity(class_hash, 1024);
        }
    }

    // Major loop - process all modules in the image
    mods = hi->mod_ptr;
    for (midx = 0; midx < hi->mod_count; midx += 1)
    {
        // Skip module containing no classes
        if (mods[midx].symtab == nil)
            continue;

        // Minor loop - process all the classes in given module
        for (index = 0; index < mods[midx].symtab->cls_def_cnt; index += 1)
        {
            Class newCls, oldCls;
            bool rejected;

            // Locate the class description pointer
            newCls = (Class)mods[midx].symtab->defs[index];

            // Classes loaded from Mach-O bundles can be unloaded later.
            // Nothing uses this class yet, so cls->setInfo is not needed.
            if (isBundle) newCls->info |= CLS_FROM_BUNDLE;
            if (isBundle) newCls->ISA()->info |= CLS_FROM_BUNDLE;

            // Use common static empty cache instead of nil
            if (newCls->cache == nil)
                newCls->cache = (Cache) &_objc_empty_cache;
            if (newCls->ISA()->cache == nil)
                newCls->ISA()->cache = (Cache) &_objc_empty_cache;

            // Set metaclass version
            newCls->ISA()->version = mods[midx].version;

            // methodLists is nil or a single list, not an array
            newCls->info |= CLS_NO_METHOD_ARRAY|CLS_NO_PROPERTY_ARRAY;
            newCls->ISA()->info |= CLS_NO_METHOD_ARRAY|CLS_NO_PROPERTY_ARRAY;

            // class has no subclasses for cache flushing
            newCls->info |= CLS_LEAF;
            newCls->ISA()->info |= CLS_LEAF;

            if (mods[midx].version >= 6) {
                // class structure has ivar_layout and ext fields
                newCls->info |= CLS_EXT;
                newCls->ISA()->info |= CLS_EXT;
            }

            // Check for +load implementation before categories are attached
            if (_class_hasLoadMethod(newCls)) {
                newCls->ISA()->info |= CLS_HAS_LOAD_METHOD;
            }

            // Install into unconnected_class_hash.
            {
                mutex_locker_t lock(classLock);

                if (future_class_hash) {
                    Class futureCls = (Class)
                        NXHashRemove(future_class_hash, newCls);
                    if (futureCls) {
                        // Another class structure for this class was already 
                        // prepared by objc_getFutureClass(). Use it instead.
                        free((char *)futureCls->name);
                        memcpy(futureCls, newCls, sizeof(objc_class));
                        setOriginalClassForFutureClass(futureCls, newCls);
                        newCls = futureCls;
                        
                        if (NXCountHashTable(future_class_hash) == 0) {
                            NXFreeHashTable(future_class_hash);
                            future_class_hash = nil;
                        }
                    }
                }
                
                if (!unconnected_class_hash) {
                    unconnected_class_hash = 
                        NXCreateHashTable(classHashPrototype, 128, nil);
                }
                
                if ((oldCls = (Class)NXHashGet(class_hash, newCls))  ||  
                    (oldCls = (Class)NXHashGet(unconnected_class_hash, newCls)))
                {
                    // Another class with this name exists. Complain and reject.
                    inform_duplicate(newCls->name, oldCls, newCls);
                    rejected = YES;
                }
                else {
                    NXHashInsert(unconnected_class_hash, newCls); 
                    rejected = NO;
                }
            }

            if (!rejected) {
                // Attach pended categories for this class, if any
                resolve_categories_for_class(newCls);
            }
        }
    }
}


/***********************************************************************
* _objc_connect_classes_from_image.
* Connect the classes in the given image to their superclasses,
* or register them for later connection if any superclasses are missing.
**********************************************************************/
static void _objc_connect_classes_from_image(header_info *hi)
{
    unsigned int index;
    unsigned int midx;
    Module mods;
    bool replacement = _objcHeaderIsReplacement(hi);

    // Major loop - process all modules in the image
    mods = hi->mod_ptr;
    for (midx = 0; midx < hi->mod_count; midx += 1)
    {
        // Skip module containing no classes
        if (mods[midx].symtab == nil)
            continue;

        // Minor loop - process all the classes in given module
        for (index = 0; index < mods[midx].symtab->cls_def_cnt; index += 1)
        {
            Class cls = (Class)mods[midx].symtab->defs[index];
            if (! replacement) {
                bool connected;
                Class futureCls = getFutureClassForOriginalClass(cls);
                if (futureCls) {
                    // objc_getFutureClass() requested a different class 
                    // struct. Fix up the original struct's superclass 
                    // field for [super ...] use, but otherwise perform 
                    // fixups on the new class struct only.
                    const char *super_name = (const char *) cls->superclass;
                    if (super_name) cls->superclass = objc_getClass(super_name);
                    cls = futureCls;
                }
                connected = connect_class(cls);
                if (connected  &&  callbackFunction) {
                    (*callbackFunction)(cls, 0);
                }
            } else {
                // Replacement image - fix up superclass only (#3704817)
                // And metaclass's superclass (#5351107)
                const char *super_name = (const char *) cls->superclass;
                if (super_name) {
                    cls->superclass = objc_getClass(super_name);
                    // metaclass's superclass is superclass's metaclass
                    cls->ISA()->superclass = cls->superclass->ISA();
                } else {
                    // Replacement for a root class
                    // cls->superclass already nil
                    // root metaclass's superclass is root class
                    cls->ISA()->superclass = cls;
                }
            }
        }
    }
}


/***********************************************************************
* _objc_map_class_refs_for_image.  Convert the class ref entries from
* a class name string pointer to a class pointer.  If the class does
* not yet exist, the reference is added to a list of pending references
* to be fixed up at a later date.
**********************************************************************/
static void fix_class_ref(Class *ref, const char *name, bool isMeta)
{
    Class cls;

    // Get pointer to class of this name
    // NO unconnected, YES class loader
    // (real class with weak-missing superclass is unconnected now)
    cls = look_up_class(name, NO, YES);
    if (cls) {
        // Referenced class exists. Fix up the reference.
        *ref = isMeta ? cls->ISA() : cls;
    } else {
        // Referenced class does not exist yet. Insert nil for now 
        // (weak-linking) and fix up the reference if the class arrives later.
        pendClassReference (ref, name, isMeta);
        *ref = nil;
    }
}

static void _objc_map_class_refs_for_image (header_info * hi)
{
    Class *cls_refs;
    size_t	count;
    unsigned int	index;

    // Locate class refs in image
    cls_refs = _getObjcClassRefs (hi, &count);
    if (cls_refs) {
        // Process each class ref
        for (index = 0; index < count; index += 1) {
            // Ref is initially class name char*
            const char *name = (const char *) cls_refs[index];
            if (!name) continue;
            fix_class_ref(&cls_refs[index], name, NO /*never meta*/);
        }
    }
}


/***********************************************************************
* _objc_remove_pending_class_refs_in_image
* Delete any pending class ref fixups for class refs in the given image, 
* because the image is about to be unloaded.
**********************************************************************/
static void removePendingReferences(Class *refs, size_t count)
{
    Class *end = refs + count;

    if (!refs) return;
    if (!pendingClassRefsMap) return;

    // Search the pending class ref table for class refs in this range.
    // The class refs may have already been stomped with nil, 
    // so there's no way to recover the original class name.

    {    
        const char *key;
        PendingClassRef *pending;
        NXMapState  state = NXInitMapState(pendingClassRefsMap);
        while(NXNextMapState(pendingClassRefsMap, &state, 
                             (const void **)&key, (const void **)&pending)) 
        {
            for ( ; pending != nil; pending = pending->next) {
                if (pending->ref >= refs  &&  pending->ref < end) {
                    pending->ref = nil;
                }
            }
        }
    } 
}

static void _objc_remove_pending_class_refs_in_image(header_info *hi)
{
    Class *cls_refs;
    size_t count;

    // Locate class refs in this image
    cls_refs = _getObjcClassRefs(hi, &count);
    removePendingReferences(cls_refs, count);
}


/***********************************************************************
* map_selrefs.  For each selector in the specified array,
* replace the name pointer with a uniqued selector.
* If copy is TRUE, all selector data is always copied. This is used 
* for registering selectors from unloadable bundles, so the selector 
* can still be used after the bundle's data segment is unmapped.
* Returns YES if dst was written to, NO if it was unchanged.
**********************************************************************/
static inline void map_selrefs(SEL *sels, size_t count, bool copy)
{
    size_t index;

    if (!sels) return;

    sel_lock();

    // Process each selector
    for (index = 0; index < count; index += 1)
    {
        SEL sel;

        // Lookup pointer to uniqued string
        sel = sel_registerNameNoLock((const char *) sels[index], copy);

        // Replace this selector with uniqued one (avoid
        // modifying the VM page if this would be a NOP)
        if (sels[index] != sel) {
            sels[index] = sel;
        }
    }
    
    sel_unlock();
}


/***********************************************************************
* map_method_descs.  For each method in the specified method list,
* replace the name pointer with a uniqued selector.
* If copy is TRUE, all selector data is always copied. This is used 
* for registering selectors from unloadable bundles, so the selector 
* can still be used after the bundle's data segment is unmapped.
**********************************************************************/
static void  map_method_descs (struct objc_method_description_list * methods, bool copy)
{
    int index;

    if (!methods) return;

    sel_lock();

    // Process each method
    for (index = 0; index < methods->count; index += 1)
    {
        struct objc_method_description *	method;
        SEL					sel;

        // Get method entry to fix up
        method = &methods->list[index];

        // Lookup pointer to uniqued string
        sel = sel_registerNameNoLock((const char *) method->name, copy);

        // Replace this selector with uniqued one (avoid
        // modifying the VM page if this would be a NOP)
        if (method->name != sel)
            method->name = sel;
    }

    sel_unlock();
}


/***********************************************************************
* ext_for_protocol
* Returns the protocol extension for the given protocol.
* Returns nil if the protocol has no extension.
**********************************************************************/
static old_protocol_ext *ext_for_protocol(old_protocol *proto)
{
    if (!proto) return nil;
    if (!protocol_ext_map) return nil;
    else return (old_protocol_ext *)NXMapGet(protocol_ext_map, proto);
}


/***********************************************************************
* lookup_method
* Search a protocol method list for a selector.
**********************************************************************/
static struct objc_method_description *
lookup_method(struct objc_method_description_list *mlist, SEL aSel)
{
   if (mlist) {
       int i;
       for (i = 0; i < mlist->count; i++) {
           if (mlist->list[i].name == aSel) {
               return mlist->list+i;
           }
       }
   }
   return nil;
}


/***********************************************************************
* lookup_protocol_method
* Search for a selector in a protocol 
* (and optionally recursively all incorporated protocols)
**********************************************************************/
struct objc_method_description *
lookup_protocol_method(old_protocol *proto, SEL aSel, 
                       bool isRequiredMethod, bool isInstanceMethod, 
                       bool recursive)
{
    struct objc_method_description *m = nil;
    old_protocol_ext *ext;

    if (isRequiredMethod) {
        if (isInstanceMethod) {
            m = lookup_method(proto->instance_methods, aSel);
        } else {
            m = lookup_method(proto->class_methods, aSel);
        }
    } else if ((ext = ext_for_protocol(proto))) {
        if (isInstanceMethod) {
            m = lookup_method(ext->optional_instance_methods, aSel);
        } else {
            m = lookup_method(ext->optional_class_methods, aSel);
        }
    }

    if (!m  &&  recursive  &&  proto->protocol_list) {
        int i;
        for (i = 0; !m  &&  i < proto->protocol_list->count; i++) {
            m = lookup_protocol_method(proto->protocol_list->list[i], aSel, 
                                       isRequiredMethod,isInstanceMethod,true);
        }
    }

    return m;
}


/***********************************************************************
* protocol_getName
* Returns the name of the given protocol.
**********************************************************************/
const char *protocol_getName(Protocol *p)
{
    old_protocol *proto = oldprotocol(p);
    if (!proto) return "nil";
    return proto->protocol_name;
}


/***********************************************************************
* protocol_getMethodDescription
* Returns the description of a named method.
* Searches either required or optional methods.
* Searches either instance or class methods.
**********************************************************************/
struct objc_method_description 
protocol_getMethodDescription(Protocol *p, SEL aSel, 
                              BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    struct objc_method_description empty = {nil, nil};
    old_protocol *proto = oldprotocol(p);
    struct objc_method_description *desc;
    if (!proto) return empty;

    desc = lookup_protocol_method(proto, aSel, 
                                  isRequiredMethod, isInstanceMethod, true);
    if (desc) return *desc;
    else return empty;
}


/***********************************************************************
* protocol_copyMethodDescriptionList
* Returns an array of method descriptions from a protocol.
* Copies either required or optional methods.
* Copies either instance or class methods.
**********************************************************************/
struct objc_method_description *
protocol_copyMethodDescriptionList(Protocol *p, 
                                   BOOL isRequiredMethod, 
                                   BOOL isInstanceMethod, 
                                   unsigned int *outCount)
{
    struct objc_method_description_list *mlist = nil;
    old_protocol *proto = oldprotocol(p);
    old_protocol_ext *ext;
    unsigned int i, count;
    struct objc_method_description *result;

    if (!proto) {
        if (outCount) *outCount = 0;
        return nil;
    } 

    if (isRequiredMethod) {
        if (isInstanceMethod) {
            mlist = proto->instance_methods;
        } else {
            mlist = proto->class_methods;
        }
    } else if ((ext = ext_for_protocol(proto))) {
        if (isInstanceMethod) {
            mlist = ext->optional_instance_methods;
        } else {
            mlist = ext->optional_class_methods;
        }
    }

    if (!mlist) {
        if (outCount) *outCount = 0;
        return nil;
    }
    
    count = mlist->count;
    result = (struct objc_method_description *)
        calloc(count + 1, sizeof(struct objc_method_description));
    for (i = 0; i < count; i++) {
        result[i] = mlist->list[i];
    }

    if (outCount) *outCount = count;
    return result;
}


objc_property_t protocol_getProperty(Protocol *p, const char *name, 
                              BOOL isRequiredProperty, BOOL isInstanceProperty)
{
    old_protocol *proto = oldprotocol(p);
    old_protocol_ext *ext;
    old_protocol_list *proto_list;

    if (!proto  ||  !name) return nil;
    
    if (!isRequiredProperty  ||  !isInstanceProperty) {
        // Only required instance properties are currently supported
        return nil;
    }

    if ((ext = ext_for_protocol(proto))) {
        old_property_list *plist;
        if ((plist = ext->instance_properties)) {
            uint32_t i;
            for (i = 0; i < plist->count; i++) {
                old_property *prop = property_list_nth(plist, i);
                if (0 == strcmp(name, prop->name)) {
                    return (objc_property_t)prop;
                }
            }
        }
    }

    if ((proto_list = proto->protocol_list)) {
        int i;
        for (i = 0; i < proto_list->count; i++) {
            objc_property_t prop = 
                protocol_getProperty((Protocol *)proto_list->list[i], name, 
                                     isRequiredProperty, isInstanceProperty);
            if (prop) return prop;
        }
    }
    
    return nil;
}


objc_property_t *protocol_copyPropertyList(Protocol *p, unsigned int *outCount)
{
    old_property **result = nil;
    old_protocol_ext *ext;
    old_property_list *plist;
    
    old_protocol *proto = oldprotocol(p);
    if (! (ext = ext_for_protocol(proto))) {
        if (outCount) *outCount = 0;
        return nil;
    }

    plist = ext->instance_properties;
    result = copyPropertyList(plist, outCount);
    
    return (objc_property_t *)result;
}


/***********************************************************************
* protocol_copyProtocolList
* Copies this protocol's incorporated protocols. 
* Does not copy those protocol's incorporated protocols in turn.
**********************************************************************/
Protocol * __unsafe_unretained *
protocol_copyProtocolList(Protocol *p, unsigned int *outCount)
{
    unsigned int count = 0;
    Protocol **result = nil;
    old_protocol *proto = oldprotocol(p);
    
    if (!proto) {
        if (outCount) *outCount = 0;
        return nil;
    }

    if (proto->protocol_list) {
        count = (unsigned int)proto->protocol_list->count;
    }
    if (count > 0) {
        unsigned int i;
        result = (Protocol **)malloc((count+1) * sizeof(Protocol *));

        for (i = 0; i < count; i++) {
            result[i] = (Protocol *)proto->protocol_list->list[i];
        }
        result[i] = nil;
    }

    if (outCount) *outCount = count;
    return result;
}


BOOL protocol_conformsToProtocol(Protocol *self_gen, Protocol *other_gen)
{
    old_protocol *self = oldprotocol(self_gen);
    old_protocol *other = oldprotocol(other_gen);

    if (!self  ||  !other) {
        return NO;
    }

    if (0 == strcmp(self->protocol_name, other->protocol_name)) {
        return YES;
    }

    if (self->protocol_list) {
        int i;
        for (i = 0; i < self->protocol_list->count; i++) {
            old_protocol *proto = self->protocol_list->list[i];
            if (0 == strcmp(other->protocol_name, proto->protocol_name)) {
                return YES;
            }
            if (protocol_conformsToProtocol((Protocol *)proto, other_gen)) {
                return YES;
            }
        }
    }

    return NO;
}


BOOL protocol_isEqual(Protocol *self, Protocol *other)
{
    if (self == other) return YES;
    if (!self  ||  !other) return NO;

    if (!protocol_conformsToProtocol(self, other)) return NO;
    if (!protocol_conformsToProtocol(other, self)) return NO;

    return YES;
}


/***********************************************************************
* _protocol_getMethodTypeEncoding
* Return the @encode string for the requested protocol method.
* Returns nil if the compiler did not emit any extended @encode data.
* Locking: runtimeLock must not be held by the caller
**********************************************************************/
const char * 
_protocol_getMethodTypeEncoding(Protocol *proto_gen, SEL sel, 
                                BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    old_protocol *proto = oldprotocol(proto_gen);
    if (!proto) return nil;
    old_protocol_ext *ext = ext_for_protocol(proto);
    if (!ext) return nil;
    if (ext->size < offsetof(old_protocol_ext, extendedMethodTypes) + sizeof(ext->extendedMethodTypes)) return nil;
    if (! ext->extendedMethodTypes) return nil;

    struct objc_method_description *m = 
        lookup_protocol_method(proto, sel, 
                               isRequiredMethod, isInstanceMethod, false);
    if (!m) {
        // No method with that name. Search incorporated protocols.
        if (proto->protocol_list) {
            for (int i = 0; i < proto->protocol_list->count; i++) {
                const char *enc = 
                    _protocol_getMethodTypeEncoding((Protocol *)proto->protocol_list->list[i], sel, isRequiredMethod, isInstanceMethod);
                if (enc) return enc;
            }
        }
        return nil;
    }
    
    int i = 0;
    if (isRequiredMethod && isInstanceMethod) {
        i += ((uintptr_t)m - (uintptr_t)proto->instance_methods) / sizeof(proto->instance_methods->list[0]);
        goto done;
    } else if (proto->instance_methods) {
        i += proto->instance_methods->count;
    }

    if (isRequiredMethod && !isInstanceMethod) {
        i += ((uintptr_t)m - (uintptr_t)proto->class_methods) / sizeof(proto->class_methods->list[0]);
        goto done;
    } else if (proto->class_methods) {
        i += proto->class_methods->count;
    }

    if (!isRequiredMethod && isInstanceMethod) {
        i += ((uintptr_t)m - (uintptr_t)ext->optional_instance_methods) / sizeof(ext->optional_instance_methods->list[0]);
        goto done;
    } else if (ext->optional_instance_methods) {
        i += ext->optional_instance_methods->count;
    }

    if (!isRequiredMethod && !isInstanceMethod) {
        i += ((uintptr_t)m - (uintptr_t)ext->optional_class_methods) / sizeof(ext->optional_class_methods->list[0]);
        goto done;
    } else if (ext->optional_class_methods) {
        i += ext->optional_class_methods->count;
    }

 done:
    return ext->extendedMethodTypes[i];
}


/***********************************************************************
* objc_allocateProtocol
* Creates a new protocol. The protocol may not be used until 
* objc_registerProtocol() is called.
* Returns nil if a protocol with the same name already exists.
* Locking: acquires classLock
**********************************************************************/
Protocol *
objc_allocateProtocol(const char *name)
{
    Class cls = objc_getClass("__IncompleteProtocol");

    mutex_locker_t lock(classLock);

    if (NXMapGet(protocol_map, name)) return nil;

    old_protocol *result = (old_protocol *)
        calloc(1, sizeof(old_protocol) 
                         + sizeof(old_protocol_ext));
    old_protocol_ext *ext = (old_protocol_ext *)(result+1);
    
    result->isa = cls;
    result->protocol_name = strdup(name);
    ext->size = sizeof(old_protocol_ext);

    // fixme reserve name without installing

    NXMapInsert(protocol_ext_map, result, result+1);

    return (Protocol *)result;
}


/***********************************************************************
* objc_registerProtocol
* Registers a newly-constructed protocol. The protocol is now 
* ready for use and immutable.
* Locking: acquires classLock
**********************************************************************/
void objc_registerProtocol(Protocol *proto_gen) 
{
    old_protocol *proto = oldprotocol(proto_gen);

    Class oldcls = objc_getClass("__IncompleteProtocol");
    Class cls = objc_getClass("Protocol");

    mutex_locker_t lock(classLock);

    if (proto->isa == cls) {
        _objc_inform("objc_registerProtocol: protocol '%s' was already "
                     "registered!", proto->protocol_name);
        return;
    }
    if (proto->isa != oldcls) {
        _objc_inform("objc_registerProtocol: protocol '%s' was not allocated "
                     "with objc_allocateProtocol!", proto->protocol_name);
        return;
    }

    proto->isa = cls;

    NXMapKeyCopyingInsert(protocol_map, proto->protocol_name, proto);
}


/***********************************************************************
* protocol_addProtocol
* Adds an incorporated protocol to another protocol.
* No method enforcement is performed.
* `proto` must be under construction. `addition` must not.
* Locking: acquires classLock
**********************************************************************/
void 
protocol_addProtocol(Protocol *proto_gen, Protocol *addition_gen) 
{
    old_protocol *proto = oldprotocol(proto_gen);
    old_protocol *addition = oldprotocol(addition_gen);

    Class cls = objc_getClass("__IncompleteProtocol");

    if (!proto_gen) return;
    if (!addition_gen) return;

    mutex_locker_t lock(classLock);

    if (proto->isa != cls) {
        _objc_inform("protocol_addProtocol: modified protocol '%s' is not "
                     "under construction!", proto->protocol_name);
        return;
    }
    if (addition->isa == cls) {
        _objc_inform("protocol_addProtocol: added protocol '%s' is still "
                     "under construction!", addition->protocol_name);
        return;        
    }
    
    old_protocol_list *protolist = proto->protocol_list;
    if (protolist) {
        size_t size = sizeof(old_protocol_list) 
            + protolist->count * sizeof(protolist->list[0]);
        protolist = (old_protocol_list *)
            realloc(protolist, size);
    } else {
        protolist = (old_protocol_list *)
            calloc(1, sizeof(old_protocol_list));
    }

    protolist->list[protolist->count++] = addition;
    proto->protocol_list = protolist;
}


/***********************************************************************
* protocol_addMethodDescription
* Adds a method to a protocol. The protocol must be under construction.
* Locking: acquires classLock
**********************************************************************/
static void
_protocol_addMethod(struct objc_method_description_list **list, SEL name, const char *types)
{
    if (!*list) {
        *list = (struct objc_method_description_list *)
            calloc(sizeof(struct objc_method_description_list), 1);
    } else {
        size_t size = sizeof(struct objc_method_description_list) 
            + (*list)->count * sizeof(struct objc_method_description);
        *list = (struct objc_method_description_list *)
            realloc(*list, size);
    }

    struct objc_method_description *desc = &(*list)->list[(*list)->count++];
    desc->name = name;
    desc->types = strdup(types ?: "");
}

void 
protocol_addMethodDescription(Protocol *proto_gen, SEL name, const char *types,
                              BOOL isRequiredMethod, BOOL isInstanceMethod) 
{
    old_protocol *proto = oldprotocol(proto_gen);

    Class cls = objc_getClass("__IncompleteProtocol");

    if (!proto_gen) return;

    mutex_locker_t lock(classLock);

    if (proto->isa != cls) {
        _objc_inform("protocol_addMethodDescription: protocol '%s' is not "
                     "under construction!", proto->protocol_name);
        return;
    }

    if (isRequiredMethod  &&  isInstanceMethod) {
        _protocol_addMethod(&proto->instance_methods, name, types);
    } else if (isRequiredMethod  &&  !isInstanceMethod) {
        _protocol_addMethod(&proto->class_methods, name, types);
    } else if (!isRequiredMethod  &&  isInstanceMethod) {
        old_protocol_ext *ext = (old_protocol_ext *)(proto+1);
        _protocol_addMethod(&ext->optional_instance_methods, name, types);
    } else /*  !isRequiredMethod  &&  !isInstanceMethod) */ {
        old_protocol_ext *ext = (old_protocol_ext *)(proto+1);
        _protocol_addMethod(&ext->optional_class_methods, name, types);
    }
}


/***********************************************************************
* protocol_addProperty
* Adds a property to a protocol. The protocol must be under construction.
* Locking: acquires classLock
**********************************************************************/
static void 
_protocol_addProperty(old_property_list **plist, const char *name, 
                      const objc_property_attribute_t *attrs, 
                      unsigned int count)
{
    if (!*plist) {
        *plist = (old_property_list *)
            calloc(sizeof(old_property_list), 1);
        (*plist)->entsize = sizeof(old_property);
    } else {
        *plist = (old_property_list *)
            realloc(*plist, sizeof(old_property_list) 
                              + (*plist)->count * (*plist)->entsize);
    }

    old_property *prop = property_list_nth(*plist, (*plist)->count++);
    prop->name = strdup(name);
    prop->attributes = copyPropertyAttributeString(attrs, count);
}

void 
protocol_addProperty(Protocol *proto_gen, const char *name, 
                     const objc_property_attribute_t *attrs, 
                     unsigned int count,
                     BOOL isRequiredProperty, BOOL isInstanceProperty)
{
    old_protocol *proto = oldprotocol(proto_gen);

    Class cls = objc_getClass("__IncompleteProtocol");

    if (!proto) return;
    if (!name) return;

    mutex_locker_t lock(classLock);
    
    if (proto->isa != cls) {
        _objc_inform("protocol_addProperty: protocol '%s' is not "
                     "under construction!", proto->protocol_name);
        return;
    }

    old_protocol_ext *ext = ext_for_protocol(proto);

    if (isRequiredProperty  &&  isInstanceProperty) {
        _protocol_addProperty(&ext->instance_properties, name, attrs, count);
    }
    //else if (isRequiredProperty  &&  !isInstanceProperty) {
    //    _protocol_addProperty(&ext->class_properties, name, attrs, count);
    //} else if (!isRequiredProperty  &&  isInstanceProperty) {
    //    _protocol_addProperty(&ext->optional_instance_properties, name, attrs, count);
    //} else /*  !isRequiredProperty  &&  !isInstanceProperty) */ {
    //    _protocol_addProperty(&ext->optional_class_properties, name, attrs, count);
    //}
}


/***********************************************************************
* _objc_fixup_protocol_objects_for_image.  For each protocol in the
* specified image, selectorize the method names and add to the protocol hash.
**********************************************************************/

static bool versionIsExt(uintptr_t version, const char *names, size_t size)
{
    // CodeWarrior used isa field for string "Protocol" 
    //   from section __OBJC,__class_names.  rdar://4951638
    // gcc (10.4 and earlier) used isa field for version number; 
    //   the only version number used on Mac OS X was 2.
    // gcc (10.5 and later) uses isa field for ext pointer

    if (version < 4096 /* not PAGE_SIZE */) {
        return NO;
    }

    if (version >= (uintptr_t)names  &&  version < (uintptr_t)(names + size)) {
        return NO;
    }

    return YES;
}

static void fix_protocol(old_protocol *proto, Class protocolClass, 
                         bool isBundle, const char *names, size_t names_size)
{
    uintptr_t version;
    if (!proto) return;

    version = (uintptr_t)proto->isa;

    // Set the protocol's isa
    proto->isa = protocolClass;

    // Fix up method lists
    // fixme share across duplicates
    map_method_descs (proto->instance_methods, isBundle);
    map_method_descs (proto->class_methods, isBundle);

    // Fix up ext, if any
    if (versionIsExt(version, names, names_size)) {
        old_protocol_ext *ext = (old_protocol_ext *)version;
        NXMapInsert(protocol_ext_map, proto, ext);
        map_method_descs (ext->optional_instance_methods, isBundle);
        map_method_descs (ext->optional_class_methods, isBundle);
    }
    
    // Record the protocol it if we don't have one with this name yet
    // fixme bundles - copy protocol
    // fixme unloading
    if (!NXMapGet(protocol_map, proto->protocol_name)) {
        NXMapKeyCopyingInsert(protocol_map, proto->protocol_name, proto);
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s",
                         proto, proto->protocol_name);
        }
    } else {
        // duplicate - do nothing
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: protocol at %p is %s (duplicate)",
                         proto, proto->protocol_name);
        }
    }
}

static void _objc_fixup_protocol_objects_for_image (header_info * hi)
{
    Class protocolClass = objc_getClass("Protocol");
    size_t count, i;
    old_protocol **protos;
    int isBundle = headerIsBundle(hi);
    const char *names;
    size_t names_size;

    mutex_locker_t lock(classLock);

    // Allocate the protocol registry if necessary.
    if (!protocol_map) {
        protocol_map = 
            NXCreateMapTable(NXStrValueMapPrototype, 32);
    }
    if (!protocol_ext_map) {
        protocol_ext_map = 
            NXCreateMapTable(NXPtrValueMapPrototype, 32);
    }

    protos = _getObjcProtocols(hi, &count);
    names = _getObjcClassNames(hi, &names_size);
    for (i = 0; i < count; i++) {
        fix_protocol(protos[i], protocolClass, isBundle, names, names_size);
    }
}


/***********************************************************************
* _objc_fixup_selector_refs.  Register all of the selectors in each
* image, and fix them all up.
**********************************************************************/
static void _objc_fixup_selector_refs   (const header_info *hi)
{
    size_t count;
    SEL *sels;

    bool preoptimized = hi->isPreoptimized();
# if SUPPORT_IGNORED_SELECTOR_CONSTANT
    // shared cache can't fix constant ignored selectors
    if (UseGC) preoptimized = NO;
# endif

    if (PrintPreopt) {
        if (preoptimized) {
            _objc_inform("PREOPTIMIZATION: honoring preoptimized selectors in %s", 
                         hi->fname);
        }
        else if (_objcHeaderOptimizedByDyld(hi)) {
            _objc_inform("PREOPTIMIZATION: IGNORING preoptimized selectors in %s", 
                         hi->fname);
        }
    }

    if (preoptimized) return;
    
    sels = _getObjcSelectorRefs (hi, &count);

    map_selrefs(sels, count, headerIsBundle(hi));
}

static inline bool _is_threaded() {
#if TARGET_OS_WIN32
    return YES;
#else
    return pthread_is_threaded_np() != 0;
#endif
}

#if !TARGET_OS_WIN32
/***********************************************************************
* unmap_image
* Process the given image which is about to be unmapped by dyld.
* mh is mach_header instead of headerType because that's what 
*   dyld_priv.h says even for 64-bit.
**********************************************************************/
void 
unmap_image(const struct mach_header *mh, intptr_t vmaddr_slide)
{
    recursive_mutex_locker_t lock(loadMethodLock);
    unmap_image_nolock(mh);
}


/***********************************************************************
* map_images
* Process the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
**********************************************************************/
const char *
map_2_images(enum dyld_image_states state, uint32_t infoCount,
             const struct dyld_image_info infoList[])
{
    recursive_mutex_locker_t lock(loadMethodLock);
    return map_images_nolock(state, infoCount, infoList);
}


/***********************************************************************
* load_images
* Process +load in the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
*
* Locking: acquires classLock and loadMethodLock
**********************************************************************/
const char *
load_images(enum dyld_image_states state, uint32_t infoCount,
           const struct dyld_image_info infoList[])
{
    bool found;

    recursive_mutex_locker_t lock(loadMethodLock);

    // Discover +load methods
    found = load_images_nolock(state, infoCount, infoList);

    // Call +load methods (without classLock - re-entrant)
    if (found) {
        call_load_methods();
    }

    return nil;
}
#endif


/***********************************************************************
* _read_images
* Perform metadata processing for hCount images starting with firstNewHeader
**********************************************************************/
void _read_images(header_info **hList, uint32_t hCount)
{
    uint32_t i;
    bool categoriesLoaded = NO;

    if (!class_hash) _objc_init_class_hash();

    // Parts of this order are important for correctness or performance.

    // Read classes from all images.
    for (i = 0; i < hCount; i++) {
        _objc_read_classes_from_image(hList[i]);
    }

    // Read categories from all images. 
    // But not if any other threads are running - they might
    // call a category method before the fixups below are complete.
     if (!_is_threaded()) {
        bool needFlush = NO;
        for (i = 0; i < hCount; i++) {
            needFlush |= _objc_read_categories_from_image(hList[i]);
        }
        if (needFlush) flush_marked_caches();
        categoriesLoaded = YES;
    }

    // Connect classes from all images.
    for (i = 0; i < hCount; i++) {
        _objc_connect_classes_from_image(hList[i]);
    }

    // Fix up class refs, selector refs, and protocol objects from all images.
    for (i = 0; i < hCount; i++) {
        _objc_map_class_refs_for_image(hList[i]);
        _objc_fixup_selector_refs(hList[i]);
        _objc_fixup_protocol_objects_for_image(hList[i]);
    }

    // Read categories from all images. 
    // But not if this is the only thread - it's more 
    // efficient to attach categories earlier if safe.
    if (!categoriesLoaded) {
        bool needFlush = NO;
        for (i = 0; i < hCount; i++) {
            needFlush |= _objc_read_categories_from_image(hList[i]);
        }
        if (needFlush) flush_marked_caches();
    }

    // Multi-threaded category load MUST BE LAST to avoid a race.
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
    if (cls->info & CLS_LOADED) return;
    if (cls->superclass) schedule_class_load(cls->superclass);
    add_class_to_loadable_list(cls);
    cls->info |= CLS_LOADED;
}

bool hasLoadMethods(const headerType *mhdr)
{
    return true;
}

void prepare_load_methods(const headerType *mhdr)
{
    Module mods;
    unsigned int midx;

    header_info *hi;
    for (hi = FirstHeader; hi; hi = hi->next) {
        if (mhdr == hi->mhdr) break;
    }
    if (!hi) return;

    if (_objcHeaderIsReplacement(hi)) {
        // Ignore any classes in this image
        return;
    }

    // Major loop - process all modules in the image
    mods = hi->mod_ptr;
    for (midx = 0; midx < hi->mod_count; midx += 1)
    {
        unsigned int index;

        // Skip module containing no classes
        if (mods[midx].symtab == nil)
            continue;

        // Minor loop - process all the classes in given module
        for (index = 0; index < mods[midx].symtab->cls_def_cnt; index += 1)
        {
            // Locate the class description pointer
            Class cls = (Class)mods[midx].symtab->defs[index];
            if (cls->info & CLS_CONNECTED) {
                schedule_class_load(cls);
            }
        }
    }


    // Major loop - process all modules in the header
    mods = hi->mod_ptr;

    // NOTE: The module and category lists are traversed backwards 
    // to preserve the pre-10.4 processing order. Changing the order 
    // would have a small chance of introducing binary compatibility bugs.
    midx = (unsigned int)hi->mod_count;
    while (midx-- > 0) {
        unsigned int index;
        unsigned int total;
        Symtab symtab = mods[midx].symtab;

        // Nothing to do for a module without a symbol table
        if (mods[midx].symtab == nil)
            continue;
        // Total entries in symbol table (class entries followed
        // by category entries)
        total = mods[midx].symtab->cls_def_cnt +
            mods[midx].symtab->cat_def_cnt;
        
        // Minor loop - register all categories from given module
        index = total;
        while (index-- > mods[midx].symtab->cls_def_cnt) {
            old_category *cat = (old_category *)symtab->defs[index];
            add_category_to_loadable_list((Category)cat);
        }
    }
}


#if TARGET_OS_WIN32

void unload_class(Class cls)
{
}

#else

/***********************************************************************
* _objc_remove_classes_in_image
* Remove all classes in the given image from the runtime, because 
* the image is about to be unloaded.
* Things to clean up:
*   class_hash
*   unconnected_class_hash
*   pending subclasses list (only if class is still unconnected)
*   loadable class list
*   class's method caches
*   class refs in all other images
**********************************************************************/
// Re-pend any class references in refs that point into [start..end)
static void rependClassReferences(Class *refs, size_t count, 
                                  uintptr_t start, uintptr_t end)
{
    size_t i;

    if (!refs) return;

    // Process each class ref
    for (i = 0; i < count; i++) {
        if ((uintptr_t)(refs[i]) >= start  &&  (uintptr_t)(refs[i]) < end) {
            pendClassReference(&refs[i], refs[i]->name,
                               refs[i]->info & CLS_META);
            refs[i] = nil;
        }
    }
}


void try_free(const void *p)
{
    if (p  &&  malloc_size(p)) free((void *)p);
}

// Deallocate all memory in a method list
static void unload_mlist(old_method_list *mlist) 
{
    int i;
    for (i = 0; i < mlist->method_count; i++) {
        try_free(mlist->method_list[i].method_types);
    }
    try_free(mlist);
}

static void unload_property_list(old_property_list *proplist)
{
    uint32_t i;

    if (!proplist) return;

    for (i = 0; i < proplist->count; i++) {
        old_property *prop = property_list_nth(proplist, i);
        try_free(prop->name);
        try_free(prop->attributes);
    }
    try_free(proplist);
}


// Deallocate all memory in a class. 
void unload_class(Class cls)
{
    // Free method cache
    // This dereferences the cache contents; do this before freeing methods
    if (cls->cache  &&  cls->cache != &_objc_empty_cache) {
        _cache_free(cls->cache);
    }

    // Free ivar lists
    if (cls->ivars) {
        int i;
        for (i = 0; i < cls->ivars->ivar_count; i++) {
            try_free(cls->ivars->ivar_list[i].ivar_name);
            try_free(cls->ivars->ivar_list[i].ivar_type);
        }
        try_free(cls->ivars);
    }

    // Free fixed-up method lists and method list array
    if (cls->methodLists) {
        // more than zero method lists
        if (cls->info & CLS_NO_METHOD_ARRAY) {
            // one method list
            unload_mlist((old_method_list *)cls->methodLists);
        } 
        else {
            // more than one method list
            old_method_list **mlistp;
            for (mlistp = cls->methodLists; 
                 *mlistp != nil  &&  *mlistp != END_OF_METHODS_LIST; 
                 mlistp++) 
            {
                unload_mlist(*mlistp);
            }
            free(cls->methodLists);
        }
    }

    // Free protocol list
    old_protocol_list *protos = cls->protocols;
    while (protos) {
        old_protocol_list *dead = protos;
        protos = protos->next;
        try_free(dead);
    }

    if ((cls->info & CLS_EXT)) {
        if (cls->ext) {
            // Free property lists and property list array
            if (cls->ext->propertyLists) {
                // more than zero property lists
                if (cls->info & CLS_NO_PROPERTY_ARRAY) {
                    // one property list
                    old_property_list *proplist = 
                        (old_property_list *)cls->ext->propertyLists;
                    unload_property_list(proplist);
                } else {
                    // more than one property list
                    old_property_list **plistp;
                    for (plistp = cls->ext->propertyLists; 
                         *plistp != nil; 
                         plistp++) 
                    {
                        unload_property_list(*plistp);
                    }
                    try_free(cls->ext->propertyLists);
                }
            }

            // Free weak ivar layout
            try_free(cls->ext->weak_ivar_layout);

            // Free ext
            try_free(cls->ext);
        }

        // Free non-weak ivar layout
        try_free(cls->ivar_layout);
    }

    // Free class name
    try_free(cls->name);

    // Free cls
    try_free(cls);
}


static void _objc_remove_classes_in_image(header_info *hi)
{
    unsigned int       index;
    unsigned int       midx;
    Module             mods;

    mutex_locker_t lock(classLock);
    
    // Major loop - process all modules in the image
    mods = hi->mod_ptr;
    for (midx = 0; midx < hi->mod_count; midx += 1)
    {
        // Skip module containing no classes
        if (mods[midx].symtab == nil)
            continue;
        
        // Minor loop - process all the classes in given module
        for (index = 0; index < mods[midx].symtab->cls_def_cnt; index += 1)
        {
            Class cls;
            
            // Locate the class description pointer
            cls = (Class)mods[midx].symtab->defs[index];

            // Remove from loadable class list, if present
            remove_class_from_loadable_list(cls);

            // Remove from unconnected_class_hash and pending subclasses
            if (unconnected_class_hash  &&  NXHashMember(unconnected_class_hash, cls)) {
                NXHashRemove(unconnected_class_hash, cls);
                if (pendingSubclassesMap) {
                    // Find this class in its superclass's pending list
                    char *supercls_name = (char *)cls->superclass;
                    PendingSubclass *pending = (PendingSubclass *)
                        NXMapGet(pendingSubclassesMap, supercls_name);
                    for ( ; pending != nil; pending = pending->next) {
                        if (pending->subclass == cls) {
                            pending->subclass = Nil;
                            break;
                        }
                    }
                }
            }
            
            // Remove from class_hash
            NXHashRemove(class_hash, cls);
            objc_removeRegisteredClass(cls);

            // Free heap memory pointed to by the class
            unload_class(cls->ISA());
            unload_class(cls);
        }
    }


    // Search all other images for class refs that point back to this range.
    // Un-fix and re-pend any such class refs.

    // Get the location of the dying image's __OBJC segment
    uintptr_t seg;
    unsigned long seg_size;
    seg = (uintptr_t)getsegmentdata(hi->mhdr, "__OBJC", &seg_size);

    header_info *other_hi;
    for (other_hi = FirstHeader; other_hi != nil; other_hi = other_hi->next) {
        Class *other_refs;
        size_t count;
        if (other_hi == hi) continue;  // skip the image being unloaded

        // Fix class refs in the other image
        other_refs = _getObjcClassRefs(other_hi, &count);
        rependClassReferences(other_refs, count, seg, seg+seg_size);
    }
}


/***********************************************************************
* _objc_remove_categories_in_image
* Remove all categories in the given image from the runtime, because 
* the image is about to be unloaded.
* Things to clean up:
*    unresolved category list
*    loadable category list
**********************************************************************/
static void _objc_remove_categories_in_image(header_info *hi)
{
    Module mods;
    unsigned int midx;
    
    // Major loop - process all modules in the header
    mods = hi->mod_ptr;
    
    for (midx = 0; midx < hi->mod_count; midx++) {
        unsigned int index;
        unsigned int total;
        Symtab symtab = mods[midx].symtab;
        
        // Nothing to do for a module without a symbol table
        if (symtab == nil) continue;
        
        // Total entries in symbol table (class entries followed
        // by category entries)
        total = symtab->cls_def_cnt + symtab->cat_def_cnt;
        
        // Minor loop - check all categories from given module
        for (index = symtab->cls_def_cnt; index < total; index++) {
            old_category *cat = (old_category *)symtab->defs[index];

            // Clean up loadable category list
            remove_category_from_loadable_list((Category)cat);

            // Clean up category_hash
            if (category_hash) {
                _objc_unresolved_category *cat_entry = (_objc_unresolved_category *)NXMapGet(category_hash, cat->class_name);
                for ( ; cat_entry != nil; cat_entry = cat_entry->next) {
                    if (cat_entry->cat == cat) {
                        cat_entry->cat = nil;
                        break;
                    }
                }
            }
        }
    }
}


/***********************************************************************
* unload_paranoia
* Various paranoid debugging checks that look for poorly-behaving 
* unloadable bundles. 
* Called by _objc_unmap_image when OBJC_UNLOAD_DEBUG is set.
**********************************************************************/
static void unload_paranoia(header_info *hi) 
{
    // Get the location of the dying image's __OBJC segment
    uintptr_t seg;
    unsigned long seg_size;
    seg = (uintptr_t)getsegmentdata(hi->mhdr, "__OBJC", &seg_size);

    _objc_inform("UNLOAD DEBUG: unloading image '%s' [%p..%p]", 
                 hi->fname, (void *)seg, (void*)(seg+seg_size));

    mutex_locker_t lock(classLock);

    // Make sure the image contains no categories on surviving classes.
    {
        Module mods;
        unsigned int midx;

        // Major loop - process all modules in the header
        mods = hi->mod_ptr;
        
        for (midx = 0; midx < hi->mod_count; midx++) {
            unsigned int index;
            unsigned int total;
            Symtab symtab = mods[midx].symtab;

            // Nothing to do for a module without a symbol table
            if (symtab == nil) continue;
            
            // Total entries in symbol table (class entries followed
            // by category entries)
            total = symtab->cls_def_cnt + symtab->cat_def_cnt;
            
            // Minor loop - check all categories from given module
            for (index = symtab->cls_def_cnt; index < total; index++) {
                old_category *cat = (old_category *)symtab->defs[index];
                struct objc_class query;

                query.name = cat->class_name;
                if (NXHashMember(class_hash, &query)) {
                    _objc_inform("UNLOAD DEBUG: dying image contains category '%s(%s)' on surviving class '%s'!", cat->class_name, cat->category_name, cat->class_name);
                }
            }
        }
    }

    // Make sure no surviving class is in the dying image.
    // Make sure no surviving class has a superclass in the dying image.
    // fixme check method implementations too
    {
        Class cls;
        NXHashState state;

        state = NXInitHashState(class_hash);
        while (NXNextHashState(class_hash, &state, (void **)&cls)) {
            if ((vm_address_t)cls >= seg  && 
                (vm_address_t)cls < seg+seg_size) 
            {
                _objc_inform("UNLOAD DEBUG: dying image contains surviving class '%s'!", cls->name);
            }
            
            if ((vm_address_t)cls->superclass >= seg  &&  
                (vm_address_t)cls->superclass < seg+seg_size)
            {
                _objc_inform("UNLOAD DEBUG: dying image contains superclass '%s' of surviving class '%s'!", cls->superclass->name, cls->name);
            }
        }
    }
}


/***********************************************************************
* _unload_image
* Only handles MH_BUNDLE for now.
* Locking: loadMethodLock acquired by unmap_image
**********************************************************************/
void _unload_image(header_info *hi)
{
    loadMethodLock.assertLocked();

    // Cleanup:
    // Remove image's classes from the class list and free auxiliary data.
    // Remove image's unresolved or loadable categories and free auxiliary data
    // Remove image's unresolved class refs.
    _objc_remove_classes_in_image(hi);
    _objc_remove_categories_in_image(hi);
    _objc_remove_pending_class_refs_in_image(hi);
    
    // Perform various debugging checks if requested.
    if (DebugUnload) unload_paranoia(hi);
}

#endif


/***********************************************************************
* objc_addClass.  Add the specified class to the table of known classes,
* after doing a little verification and fixup.
**********************************************************************/
void		objc_addClass		(Class cls)
{
    OBJC_WARN_DEPRECATED;

    // Synchronize access to hash table
    mutex_locker_t lock(classLock);

    // Make sure both the class and the metaclass have caches!
    // Clear all bits of the info fields except CLS_CLASS and CLS_META.
    // Normally these bits are already clear but if someone tries to cons
    // up their own class on the fly they might need to be cleared.
    if (cls->cache == nil) {
        cls->cache = (Cache) &_objc_empty_cache;
        cls->info = CLS_CLASS;
    }

    if (cls->ISA()->cache == nil) {
        cls->ISA()->cache = (Cache) &_objc_empty_cache;
        cls->ISA()->info = CLS_META;
    }

    // methodLists should be: 
    // 1. nil (Tiger and later only)
    // 2. A -1 terminated method list array
    // In either case, CLS_NO_METHOD_ARRAY remains clear.
    // If the user manipulates the method list directly, 
    // they must use the magic private format.

    // Add the class to the table
    (void) NXHashInsert (class_hash, cls);
    objc_addRegisteredClass(cls);

    // Superclass is no longer a leaf for cache flushing
    if (cls->superclass && (cls->superclass->info & CLS_LEAF)) {
        cls->superclass->clearInfo(CLS_LEAF);
        cls->superclass->ISA()->clearInfo(CLS_LEAF);
    }
}

/***********************************************************************
* _objcTweakMethodListPointerForClass.
* Change the class's method list pointer to a method list array. 
* Does nothing if the method list pointer is already a method list array.
* If the class is currently in use, methodListLock must be held by the caller.
**********************************************************************/
static void _objcTweakMethodListPointerForClass(Class cls)
{
    old_method_list *	originalList;
    const int					initialEntries = 4;
    size_t							mallocSize;
    old_method_list **	ptr;

    // Do nothing if methodLists is already an array.
    if (cls->methodLists  &&  !(cls->info & CLS_NO_METHOD_ARRAY)) return;

    // Remember existing list
    originalList = (old_method_list *) cls->methodLists;

    // Allocate and zero a method list array
    mallocSize   = sizeof(old_method_list *) * initialEntries;
    ptr	     = (old_method_list **) calloc(1, mallocSize);

    // Insert the existing list into the array
    ptr[initialEntries - 1] = END_OF_METHODS_LIST;
    ptr[0] = originalList;

    // Replace existing list with array
    cls->methodLists = ptr;
    cls->clearInfo(CLS_NO_METHOD_ARRAY);
}


/***********************************************************************
* _objc_insertMethods.
* Adds methods to a class.
* Does not flush any method caches.
* Does not take any locks.
* If the class is already in use, use class_addMethods() instead.
**********************************************************************/
void _objc_insertMethods(Class cls, old_method_list *mlist, old_category *cat)
{
    old_method_list ***list;
    old_method_list **ptr;
    ptrdiff_t endIndex;
    size_t oldSize;
    size_t newSize;

    if (!cls->methodLists) {
        // cls has no methods - simply use this method list
        cls->methodLists = (old_method_list **)mlist;
        cls->setInfo(CLS_NO_METHOD_ARRAY);
        return;
    }

    // Log any existing methods being replaced
    if (PrintReplacedMethods) {
        int i;
        for (i = 0; i < mlist->method_count; i++) {
            extern IMP findIMPInClass(Class cls, SEL sel);
            SEL sel = sel_registerName((char *)mlist->method_list[i].method_name);
            IMP newImp = mlist->method_list[i].method_imp;
            IMP oldImp;

            if ((oldImp = findIMPInClass(cls, sel))) {
                logReplacedMethod(cls->name, sel, ISMETA(cls), 
                                  cat ? cat->category_name : nil, 
                                  oldImp, newImp);
            }
        }
    }

    // Create method list array if necessary
    _objcTweakMethodListPointerForClass(cls);
    
    list = &cls->methodLists;

    // Locate unused entry for insertion point
    ptr = *list;
    while ((*ptr != 0) && (*ptr != END_OF_METHODS_LIST))
        ptr += 1;

    // If array is full, add to it
    if (*ptr == END_OF_METHODS_LIST)
    {
        // Calculate old and new dimensions
        endIndex = ptr - *list;
        oldSize  = (endIndex + 1) * sizeof(void *);
        newSize  = oldSize + sizeof(old_method_list *); // only increase by 1

        // Grow the method list array by one.
        *list = (old_method_list **)realloc(*list, newSize);

        // Zero out addition part of new array
        bzero (&((*list)[endIndex]), newSize - oldSize);

        // Place new end marker
        (*list)[(newSize/sizeof(void *)) - 1] = END_OF_METHODS_LIST;

        // Insertion point corresponds to old array end
        ptr = &((*list)[endIndex]);
    }

    // Right shift existing entries by one
    bcopy (*list, (*list) + 1, (uint8_t *)ptr - (uint8_t *)*list);

    // Insert at method list at beginning of array
    **list = mlist;
}

/***********************************************************************
* _objc_removeMethods.
* Remove methods from a class.
* Does not take any locks.
* Does not flush any method caches.
* If the class is currently in use, use class_removeMethods() instead.
**********************************************************************/
void _objc_removeMethods(Class cls, old_method_list *mlist)
{
    old_method_list ***list;
    old_method_list **ptr;

    if (cls->methodLists == nil) {
        // cls has no methods
        return;
    }
    if (cls->methodLists == (old_method_list **)mlist) {
        // mlist is the class's only method list - erase it
        cls->methodLists = nil;
        return;
    }
    if (cls->info & CLS_NO_METHOD_ARRAY) {
        // cls has only one method list, and this isn't it - do nothing
        return;
    }

    // cls has a method list array - search it

    list = &cls->methodLists;

    // Locate list in the array
    ptr = *list;
    while (*ptr != mlist) {
        // fix for radar # 2538790
        if ( *ptr == END_OF_METHODS_LIST ) return;
        ptr += 1;
    }

    // Remove this entry
    *ptr = 0;

    // Left shift the following entries
    while (*(++ptr) != END_OF_METHODS_LIST)
        *(ptr-1) = *ptr;
    *(ptr-1) = 0;
}

/***********************************************************************
* _objc_add_category.  Install the specified category's methods and
* protocols into the class it augments.
* The class is assumed not to be in use yet: no locks are taken and 
* no method caches are flushed.
**********************************************************************/
static inline void _objc_add_category(Class cls, old_category *category, int version)
{
    if (PrintConnecting) {
        _objc_inform("CONNECT: attaching category '%s (%s)'", cls->name, category->category_name);
    }

    // Augment instance methods
    if (category->instance_methods)
        _objc_insertMethods (cls, category->instance_methods, category);

    // Augment class methods
    if (category->class_methods)
        _objc_insertMethods (cls->ISA(), category->class_methods, category);

    // Augment protocols
    if ((version >= 5) && category->protocols)
    {
        if (cls->ISA()->version >= 5)
        {
            category->protocols->next = cls->protocols;
            cls->protocols	          = category->protocols;
            cls->ISA()->protocols       = category->protocols;
        }
        else
        {
            _objc_inform ("unable to add protocols from category %s...\n", category->category_name);
            _objc_inform ("class `%s' must be recompiled\n", category->class_name);
        }
    }

    // Augment properties
    if (version >= 7  &&  category->instance_properties) {
        if (cls->ISA()->version >= 6) {
            _class_addProperties(cls, category->instance_properties);
        } else {
            _objc_inform ("unable to add properties from category %s...\n", category->category_name);
            _objc_inform ("class `%s' must be recompiled\n", category->class_name);
        }
    }
}

/***********************************************************************
* _objc_add_category_flush_caches.  Install the specified category's 
* methods into the class it augments, and flush the class' method cache.
* Return YES if some method caches now need to be flushed.
**********************************************************************/
static bool _objc_add_category_flush_caches(Class cls, old_category *category, int version)
{
    bool needFlush = NO;

    // Install the category's methods into its intended class
    {
        mutex_locker_t lock(methodListLock);
        _objc_add_category (cls, category, version);
    }

    // Queue for cache flushing so category's methods can get called
    if (category->instance_methods) {
        cls->setInfo(CLS_FLUSH_CACHE);
        needFlush = YES;
    }
    if (category->class_methods) {
        cls->ISA()->setInfo(CLS_FLUSH_CACHE);
        needFlush = YES;
    }
    
    return needFlush;
}


/***********************************************************************
* reverse_cat
* Reverse the given linked list of pending categories. 
* The pending category list is built backwards, and needs to be 
* reversed before actually attaching the categories to a class.
* Returns the head of the new linked list.
**********************************************************************/
static _objc_unresolved_category *reverse_cat(_objc_unresolved_category *cat)
{
    _objc_unresolved_category *prev;
    _objc_unresolved_category *cur;
    _objc_unresolved_category *ahead;

    if (!cat) return nil;

    prev = nil;
    cur = cat;
    ahead = cat->next;
    
    while (cur) {
        ahead = cur->next;
        cur->next = prev;
        prev = cur;
        cur = ahead;
    }

    return prev;
}


/***********************************************************************
* resolve_categories_for_class.  
* Install all existing categories intended for the specified class.
* cls must be a true class and not a metaclass.
**********************************************************************/
static void resolve_categories_for_class(Class cls)
{
    _objc_unresolved_category *	pending;
    _objc_unresolved_category *	next;

    // Nothing to do if there are no categories at all
    if (!category_hash) return;

    // Locate and remove first element in category list
    // associated with this class
    pending = (_objc_unresolved_category *)
        NXMapKeyFreeingRemove (category_hash, cls->name);

    // Traverse the list of categories, if any, registered for this class

    // The pending list is built backwards. Reverse it and walk forwards.
    pending = reverse_cat(pending);

    while (pending) {
        if (pending->cat) {
            // Install the category
            // use the non-flush-cache version since we are only
            // called from the class intialization code
            _objc_add_category(cls, pending->cat, (int)pending->version);
        }

        // Delink and reclaim this registration
        next = pending->next;
        free(pending);
        pending = next;
    }
}


/***********************************************************************
* _objc_resolve_categories_for_class.  
* Public version of resolve_categories_for_class. This was 
* exported pre-10.4 for Omni et al. to workaround a problem 
* with too-lazy category attachment.
* cls should be a class, but this function can also cope with metaclasses.
**********************************************************************/
void _objc_resolve_categories_for_class(Class cls)
{
    // If cls is a metaclass, get the class. 
    // resolve_categories_for_class() requires a real class to work correctly.
    if (ISMETA(cls)) {
        if (strncmp(cls->name, "_%", 2) == 0) {
            // Posee's meta's name is smashed and isn't in the class_hash, 
            // so objc_getClass doesn't work.
            const char *baseName = strchr(cls->name, '%'); // get posee's real name
            cls = objc_getClass(baseName);
        } else {
            cls = objc_getClass(cls->name);
        }
    }

    resolve_categories_for_class(cls);
}


/***********************************************************************
* _objc_register_category.
* Process a category read from an image. 
* If the category's class exists, attach the category immediately. 
*   Classes that need cache flushing are marked but not flushed.
* If the category's class does not exist yet, pend the category for 
*   later attachment. Pending categories are attached in the order 
*   they were discovered.
* Returns YES if some method caches now need to be flushed.
**********************************************************************/
static bool _objc_register_category(old_category *cat, int version)
{
    _objc_unresolved_category *	new_cat;
    _objc_unresolved_category *	old;
    Class theClass;

    // If the category's class exists, attach the category.
    if ((theClass = objc_lookUpClass(cat->class_name))) {
        return _objc_add_category_flush_caches(theClass, cat, version);
    }
    
    // If the category's class exists but is unconnected, 
    // then attach the category to the class but don't bother 
    // flushing any method caches (because they must be empty).
    // YES unconnected, NO class_handler
    if ((theClass = look_up_class(cat->class_name, YES, NO))) {
        _objc_add_category(theClass, cat, version);
        return NO;
    }


    // Category's class does not exist yet. 
    // Save the category for later attachment.

    if (PrintConnecting) {
        _objc_inform("CONNECT: pending category '%s (%s)'", cat->class_name, cat->category_name);
    }

    // Create category lookup table if needed
    if (!category_hash)
        category_hash = NXCreateMapTable(NXStrValueMapPrototype, 128);

    // Locate an existing list of categories, if any, for the class.
    old = (_objc_unresolved_category *)
        NXMapGet (category_hash, cat->class_name);

    // Register the category to be fixed up later.
    // The category list is built backwards, and is reversed again 
    // by resolve_categories_for_class().
    new_cat = (_objc_unresolved_category *)
        malloc(sizeof(_objc_unresolved_category));
    new_cat->next    = old;
    new_cat->cat     = cat;
    new_cat->version = version;
    (void) NXMapKeyCopyingInsert (category_hash, cat->class_name, new_cat);

    return NO;
}


const char **
_objc_copyClassNamesForImage(header_info *hi, unsigned int *outCount)
{
    Module mods;
    unsigned int m;
    const char **list;
    int count;
    int allocated;

    list = nil;
    count = 0;
    allocated = 0;
    
    mods = hi->mod_ptr;
    for (m = 0; m < hi->mod_count; m++) {
        int d;

        if (!mods[m].symtab) continue;
        
        for (d = 0; d < mods[m].symtab->cls_def_cnt; d++) {
            Class cls = (Class)mods[m].symtab->defs[d];
            // fixme what about future-ified classes?
            if (cls->isConnected()) {
                if (count == allocated) {
                    allocated = allocated*2 + 16;
                    list = (const char **)
                        realloc((void *)list, allocated * sizeof(char *));
                }
                list[count++] = cls->name;
            }
        }
    }

    if (count > 0) {
        // nil-terminate non-empty list
        if (count == allocated) {
            allocated = allocated+1;
            list = (const char **)
                realloc((void *)list, allocated * sizeof(char *));
        }
        list[count] = nil;
    }

    if (outCount) *outCount = count;
    return list;
}

Class gdb_class_getClass(Class cls)
{
    const char *className = cls->name;
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
* Lock management
**********************************************************************/
rwlock_t selLock;
mutex_t classLock;
mutex_t methodListLock;
mutex_t cacheUpdateLock;
recursive_mutex_t loadMethodLock;

void lock_init(void)
{
}


#endif
