/*
 * Copyright (c) 2009 Apple Inc.  All Rights Reserved.
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


#ifndef _OBJC_INTERNAL_H
#define _OBJC_INTERNAL_H

/* 
 * WARNING  DANGER  HAZARD  BEWARE  EEK
 * 
 * Everything in this file is for Apple Internal use only.
 * These will change in arbitrary OS updates and in unpredictable ways.
 * When your program breaks, you get to keep both pieces.
 */

/*
 * objc-internal.h: Private SPI for use by other system frameworks.
 */

#include <objc/objc.h>
#include <objc/runtime.h>
#include <Availability.h>
#include <malloc/malloc.h>
#include <dispatch/dispatch.h>

__BEGIN_DECLS

// This is the allocation size required for each of the class and the metaclass 
// with objc_initializeClassPair() and objc_readClassPair().
// The runtime's class structure will never grow beyond this.
#define OBJC_MAX_CLASS_SIZE (32*sizeof(void*))

// In-place construction of an Objective-C class.
// cls and metacls must each be OBJC_MAX_CLASS_SIZE bytes.
// Returns nil if a class with the same name already exists.
// Returns nil if the superclass is under construction.
// Call objc_registerClassPair() when you are done.
OBJC_EXPORT Class objc_initializeClassPair(Class superclass, const char *name, Class cls, Class metacls) 
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_0);

// Class and metaclass construction from a compiler-generated memory image.
// cls and cls->isa must each be OBJC_MAX_CLASS_SIZE bytes. 
// Extra bytes not used the the metadata must be zero.
// info is the same objc_image_info that would be emitted by a static compiler.
// Returns nil if a class with the same name already exists.
// Returns nil if the superclass is nil and the class is not marked as a root.
// Returns nil if the superclass is under construction.
// Do not call objc_registerClassPair().
#if __OBJC2__
struct objc_image_info;
OBJC_EXPORT Class objc_readClassPair(Class cls, 
                                     const struct objc_image_info *info)
    __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0);
#endif

// Batch object allocation using malloc_zone_batch_malloc().
OBJC_EXPORT unsigned class_createInstances(Class cls, size_t extraBytes, 
                                           id *results, unsigned num_requested)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_4_3)
    OBJC_ARC_UNAVAILABLE;

// Get the isa pointer written into objects just before being freed.
OBJC_EXPORT Class _objc_getFreedObjectClass(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);

// Return YES if GC is on and `object` is a GC allocation.
OBJC_EXPORT BOOL objc_isAuto(id object) 
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);

// env NSObjCMessageLoggingEnabled
OBJC_EXPORT void instrumentObjcMessageSends(BOOL flag)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);

// Initializer called by libSystem
#if __OBJC2__
OBJC_EXPORT void _objc_init(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0);
#endif

#ifndef OBJC_NO_GC
// GC startup callback from Foundation
OBJC_EXPORT malloc_zone_t *objc_collect_init(int (*callback)(void))
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);
#endif

// Plainly-implemented GC barriers. Rosetta used to use these.
OBJC_EXPORT id objc_assign_strongCast_generic(id value, id *dest)
    UNAVAILABLE_ATTRIBUTE;
OBJC_EXPORT id objc_assign_global_generic(id value, id *dest)
    UNAVAILABLE_ATTRIBUTE;
OBJC_EXPORT id objc_assign_threadlocal_generic(id value, id *dest)
    UNAVAILABLE_ATTRIBUTE;
OBJC_EXPORT id objc_assign_ivar_generic(id value, id dest, ptrdiff_t offset)
    UNAVAILABLE_ATTRIBUTE;

// Install missing-class callback. Used by the late unlamented ZeroLink.
OBJC_EXPORT void _objc_setClassLoader(BOOL (*newClassLoader)(const char *))  OBJC2_UNAVAILABLE;

// Install handler for allocation failures. 
// Handler may abort, or throw, or provide an object to return.
OBJC_EXPORT void _objc_setBadAllocHandler(id (*newHandler)(Class isa))
     __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0);

// This can go away when AppKit stops calling it (rdar://7811851)
#if __OBJC2__
OBJC_EXPORT void objc_setMultithreaded (BOOL flag)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_0,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);
#endif

// Used by ExceptionHandling.framework
#if !__OBJC2__
OBJC_EXPORT void _objc_error(id rcv, const char *fmt, va_list args)
    __attribute__((noreturn))
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_0,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);

#endif


// Tagged pointer objects.

#if __LP64__
#define OBJC_HAVE_TAGGED_POINTERS 1
#endif

#if OBJC_HAVE_TAGGED_POINTERS

// Tagged pointer layout and usage is subject to change 
// on different OS versions. The current layout is:
// (MSB)
// 60 bits  payload
//  3 bits  tag index
//  1 bit   1 for tagged pointer objects, 0 for ordinary objects
// (LSB)

#if __has_feature(objc_fixed_enum)  ||  __cplusplus >= 201103L
enum objc_tag_index_t : uint8_t
#else
typedef uint8_t objc_tag_index_t;
enum
#endif
{
    OBJC_TAG_NSAtom            = 0, 
    OBJC_TAG_1                 = 1, 
    OBJC_TAG_NSString          = 2, 
    OBJC_TAG_NSNumber          = 3, 
    OBJC_TAG_NSIndexPath       = 4, 
    OBJC_TAG_NSManagedObjectID = 5, 
    OBJC_TAG_NSDate            = 6, 
    OBJC_TAG_7                 = 7
};
#if __has_feature(objc_fixed_enum)  &&  !defined(__cplusplus)
typedef enum objc_tag_index_t objc_tag_index_t;
#endif

OBJC_EXPORT void _objc_registerTaggedPointerClass(objc_tag_index_t tag, Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

OBJC_EXPORT Class _objc_getClassForTag(objc_tag_index_t tag)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

static inline bool 
_objc_taggedPointersEnabled(void)
{
    extern uintptr_t objc_debug_taggedpointer_mask;
    return (objc_debug_taggedpointer_mask != 0);
}

#if TARGET_OS_IPHONE
// tagged pointer marker is MSB

static inline void *
_objc_makeTaggedPointer(objc_tag_index_t tag, uintptr_t value)
{
    // assert(_objc_taggedPointersEnabled());
    // assert((unsigned int)tag < 8);
    // assert(((value << 4) >> 4) == value);
    return (void*)((1UL << 63) | ((uintptr_t)tag << 60) | (value & ~(0xFUL << 60)));
}

static inline bool 
_objc_isTaggedPointer(const void *ptr) 
{
    return (intptr_t)ptr < 0;  // a.k.a. ptr & 0x8000000000000000
}

static inline objc_tag_index_t 
_objc_getTaggedPointerTag(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return (objc_tag_index_t)(((uintptr_t)ptr >> 60) & 0x7);
}

static inline uintptr_t
_objc_getTaggedPointerValue(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return (uintptr_t)ptr & 0x0fffffffffffffff;
}

static inline intptr_t
_objc_getTaggedPointerSignedValue(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return ((intptr_t)ptr << 4) >> 4;
}

// TARGET_OS_IPHONE
#else
// not TARGET_OS_IPHONE
// tagged pointer marker is LSB

static inline void *
_objc_makeTaggedPointer(objc_tag_index_t tag, uintptr_t value)
{
    // assert(_objc_taggedPointersEnabled());
    // assert((unsigned int)tag < 8);
    // assert(((value << 4) >> 4) == value);
    return (void *)((value << 4) | ((uintptr_t)tag << 1) | 1);
}

static inline bool 
_objc_isTaggedPointer(const void *ptr) 
{
    return (uintptr_t)ptr & 1;
}

static inline objc_tag_index_t 
_objc_getTaggedPointerTag(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return (objc_tag_index_t)(((uintptr_t)ptr & 0xe) >> 1);
}

static inline uintptr_t
_objc_getTaggedPointerValue(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return (uintptr_t)ptr >> 4;
}

static inline intptr_t
_objc_getTaggedPointerSignedValue(const void *ptr) 
{
    // assert(_objc_isTaggedPointer(ptr));
    return (intptr_t)ptr >> 4;
}

// not TARGET_OS_IPHONE
#endif


OBJC_EXPORT void _objc_insert_tagged_isa(unsigned char slotNumber, Class isa)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_7,__MAC_10_9, __IPHONE_4_3,__IPHONE_7_0);

#endif


// External Reference support. Used to support compaction.

enum {
    OBJC_XREF_STRONG = 1,
    OBJC_XREF_WEAK = 2
};
typedef uintptr_t objc_xref_type_t;
typedef uintptr_t objc_xref_t;

OBJC_EXPORT objc_xref_t _object_addExternalReference(id object, objc_xref_type_t type)
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_4_3);
OBJC_EXPORT void _object_removeExternalReference(objc_xref_t xref)
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_4_3);
OBJC_EXPORT id _object_readExternalReference(objc_xref_t xref)
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_4_3);

OBJC_EXPORT uintptr_t _object_getExternalHash(id object)
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

/**
 * Returns the method implementation of an object.
 *
 * @param obj An Objective-C object.
 * @param name An Objective-C selector.
 *
 * @return The IMP corresponding to the instance method implemented by
 * the class of \e obj.
 * 
 * @note Equivalent to:
 *
 * class_getMethodImplementation(object_getClass(obj), name);
 */
OBJC_EXPORT IMP object_getMethodImplementation(id obj, SEL name)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

OBJC_EXPORT IMP object_getMethodImplementation_stret(id obj, SEL name)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0)
    OBJC_ARM64_UNAVAILABLE;


// Instance-specific instance variable layout.

OBJC_EXPORT void _class_setIvarLayoutAccessor(Class cls_gen, const uint8_t* (*accessor) (id object))
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_NA);
OBJC_EXPORT const uint8_t *_object_getIvarLayout(Class cls_gen, id object)
     __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_NA);

OBJC_EXPORT BOOL _class_usesAutomaticRetainRelease(Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT BOOL _class_isFutureClass(Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);


// Obsolete ARC conversions. 

// hack - remove and reinstate objc.h's definitions
#undef objc_retainedObject
#undef objc_unretainedObject
#undef objc_unretainedPointer
OBJC_EXPORT id objc_retainedObject(objc_objectptr_t pointer)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
OBJC_EXPORT id objc_unretainedObject(objc_objectptr_t pointer)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
OBJC_EXPORT objc_objectptr_t objc_unretainedPointer(id object)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#if __has_feature(objc_arc)
#   define objc_retainedObject(o) ((__bridge_transfer id)(objc_objectptr_t)(o))
#   define objc_unretainedObject(o) ((__bridge id)(objc_objectptr_t)(o))
#   define objc_unretainedPointer(o) ((__bridge objc_objectptr_t)(id)(o))
#else
#   define objc_retainedObject(o) ((id)(objc_objectptr_t)(o))
#   define objc_unretainedObject(o) ((id)(objc_objectptr_t)(o))
#   define objc_unretainedPointer(o) ((objc_objectptr_t)(id)(o))
#endif

// API to only be called by root classes like NSObject or NSProxy

OBJC_EXPORT
id
_objc_rootRetain(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void
_objc_rootRelease(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
bool
_objc_rootReleaseWasZero(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
bool
_objc_rootTryRetain(id obj)
__OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
bool
_objc_rootIsDeallocating(id obj)
__OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
_objc_rootAutorelease(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
uintptr_t
_objc_rootRetainCount(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
_objc_rootInit(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
_objc_rootAllocWithZone(Class cls, malloc_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
_objc_rootAlloc(Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void
_objc_rootDealloc(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void
_objc_rootFinalize(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
malloc_zone_t *
_objc_rootZone(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
uintptr_t
_objc_rootHash(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void *
objc_autoreleasePoolPush(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void
objc_autoreleasePoolPop(void *context)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);


OBJC_EXPORT id objc_alloc(Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

OBJC_EXPORT id objc_allocWithZone(Class cls)
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

OBJC_EXPORT id objc_retain(id obj)
    __asm__("_objc_retain")
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT void objc_release(id obj)
    __asm__("_objc_release")
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT id objc_autorelease(id obj)
    __asm__("_objc_autorelease")
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Prepare a value at +1 for return through a +0 autoreleasing convention.
OBJC_EXPORT
id
objc_autoreleaseReturnValue(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Prepare a value at +0 for return through a +0 autoreleasing convention.
OBJC_EXPORT
id
objc_retainAutoreleaseReturnValue(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Accept a value returned through a +0 autoreleasing convention for use at +1.
OBJC_EXPORT
id
objc_retainAutoreleasedReturnValue(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Accept a value returned through a +0 autoreleasing convention for use at +0.
OBJC_EXPORT
id
objc_unsafeClaimAutoreleasedReturnValue(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_11, __IPHONE_9_0);

OBJC_EXPORT
void
objc_storeStrong(id *location, id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
objc_retainAutorelease(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// obsolete.
OBJC_EXPORT id objc_retain_autorelease(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id
objc_loadWeakRetained(id *location)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
id 
objc_initWeak(id *location, id val) 
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Like objc_storeWeak, but stores nil if the new object is deallocating 
// or the new object's class does not support weak references.
// Returns the value stored (either the new object or nil).
OBJC_EXPORT
id
objc_storeWeakOrNil(id *location, id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_11, __IPHONE_9_0);

// Like objc_initWeak, but stores nil if the new object is deallocating 
// or the new object's class does not support weak references.
// Returns the value stored (either the new object or nil).
OBJC_EXPORT
id 
objc_initWeakOrNil(id *location, id val) 
    __OSX_AVAILABLE_STARTING(__MAC_10_11, __IPHONE_9_0);

OBJC_EXPORT
void 
objc_destroyWeak(id *location) 
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void 
objc_copyWeak(id *to, id *from)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void 
objc_moveWeak(id *to, id *from) 
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);


OBJC_EXPORT
void
_objc_autoreleasePoolPrint(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT BOOL objc_should_deallocate(id object)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT void objc_clear_deallocating(id object)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

 
// to make CF link for now

OBJC_EXPORT
void *
_objc_autoreleasePoolPush(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

OBJC_EXPORT
void
_objc_autoreleasePoolPop(void *context)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);


// Extra @encode data for XPC, or NULL
OBJC_EXPORT const char *_protocol_getMethodTypeEncoding(Protocol *p, SEL sel, BOOL isRequiredMethod, BOOL isInstanceMethod)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0);


// API to only be called by classes that provide their own reference count storage

OBJC_EXPORT
void
_objc_deallocOnMainThreadHelper(void *context)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// On async versus sync deallocation and the _dealloc2main flag
//
// Theory:
//
// If order matters, then code must always: [self dealloc].
// If order doesn't matter, then always async should be safe.
//
// Practice:
//
// The _dealloc2main bit is set for GUI objects that may be retained by other
// threads. Once deallocation begins on the main thread, doing more async
// deallocation will at best cause extra UI latency and at worst cause
// use-after-free bugs in unretained delegate style patterns. Yes, this is
// extremely fragile. Yes, in the long run, developers should switch to weak
// references.
//
// Note is NOT safe to do any equality check against the result of
// dispatch_get_current_queue(). The main thread can and does drain more than
// one dispatch queue. That is why we call pthread_main_np().
//

typedef enum {
    _OBJC_RESURRECT_OBJECT = -1,        /* _logicBlock has called -retain, and scheduled a -release for later. */
    _OBJC_DEALLOC_OBJECT_NOW = 1,       /* call [self dealloc] immediately. */
    _OBJC_DEALLOC_OBJECT_LATER = 2      /* call [self dealloc] on the main queue. */
} _objc_object_disposition_t;

#define _OBJC_SUPPORTED_INLINE_REFCNT_LOGIC_BLOCK(_rc_ivar, _logicBlock)        \
    -(id)retain {                                                               \
        /* this will fail to compile if _rc_ivar is an unsigned type */         \
        int _retain_count_ivar_must_not_be_unsigned[0L - (__typeof__(_rc_ivar))-1] __attribute__((unused)); \
        __typeof__(_rc_ivar) _prev = __sync_fetch_and_add(&_rc_ivar, 2);        \
        if (_prev < -2) { /* specifically allow resurrection from logical 0. */ \
            __builtin_trap(); /* BUG: retain of over-released ref */            \
        }                                                                       \
        return self;                                                            \
    }                                                                           \
    -(oneway void)release {                                                     \
        __typeof__(_rc_ivar) _prev = __sync_fetch_and_sub(&_rc_ivar, 2);        \
        if (_prev > 0) {                                                        \
            return;                                                             \
        } else if (_prev < 0) {                                                 \
            __builtin_trap(); /* BUG: over-release */                           \
        }                                                                       \
        _objc_object_disposition_t fate = _logicBlock(self);                    \
        if (fate == _OBJC_RESURRECT_OBJECT) {                                   \
            return;                                                             \
        }                                                                       \
        /* mark the object as deallocating. */                                  \
        if (!__sync_bool_compare_and_swap(&_rc_ivar, -2, 1)) {                  \
            __builtin_trap(); /* BUG: dangling ref did a retain */              \
        }                                                                       \
        if (fate == _OBJC_DEALLOC_OBJECT_NOW) {                                 \
            [self dealloc];                                                     \
        } else if (fate == _OBJC_DEALLOC_OBJECT_LATER) {                        \
            dispatch_barrier_async_f(dispatch_get_main_queue(), self,           \
                _objc_deallocOnMainThreadHelper);                               \
        } else {                                                                \
            __builtin_trap(); /* BUG: bogus fate value */                       \
        }                                                                       \
    }                                                                           \
    -(NSUInteger)retainCount {                                                  \
        return (_rc_ivar + 2) >> 1;                                             \
    }                                                                           \
    -(BOOL)_tryRetain {                                                         \
        __typeof__(_rc_ivar) _prev;                                             \
        do {                                                                    \
            _prev = _rc_ivar;                                                   \
            if (_prev & 1) {                                                    \
                return 0;                                                       \
            } else if (_prev == -2) {                                           \
                return 0;                                                       \
            } else if (_prev < -2) {                                            \
                __builtin_trap(); /* BUG: over-release elsewhere */             \
            }                                                                   \
        } while ( ! __sync_bool_compare_and_swap(&_rc_ivar, _prev, _prev + 2)); \
        return 1;                                                               \
    }                                                                           \
    -(BOOL)_isDeallocating {                                                    \
        if (_rc_ivar == -2) {                                                   \
            return 1;                                                           \
        } else if (_rc_ivar < -2) {                                             \
            __builtin_trap(); /* BUG: over-release elsewhere */                 \
        }                                                                       \
        return _rc_ivar & 1;                                                    \
    }

#define _OBJC_SUPPORTED_INLINE_REFCNT_LOGIC(_rc_ivar, _dealloc2main)            \
    _OBJC_SUPPORTED_INLINE_REFCNT_LOGIC_BLOCK(_rc_ivar, (^(id _self_ __attribute__((unused))) { \
        if (_dealloc2main && !pthread_main_np()) {                              \
            return _OBJC_DEALLOC_OBJECT_LATER;                                  \
        } else {                                                                \
            return _OBJC_DEALLOC_OBJECT_NOW;                                    \
        }                                                                       \
    }))

#define _OBJC_SUPPORTED_INLINE_REFCNT(_rc_ivar) _OBJC_SUPPORTED_INLINE_REFCNT_LOGIC(_rc_ivar, 0)
#define _OBJC_SUPPORTED_INLINE_REFCNT_WITH_DEALLOC2MAIN(_rc_ivar) _OBJC_SUPPORTED_INLINE_REFCNT_LOGIC(_rc_ivar, 1)

__END_DECLS

#endif
