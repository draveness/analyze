/*
 * Copyright (c) 2004-2007 Apple Inc. All rights reserved.
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

#ifndef _OBJC_AUTO_H_
#define _OBJC_AUTO_H_

#pragma GCC system_header

#include <objc/objc.h>
#include <malloc/malloc.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <Availability.h>
#include <TargetConditionals.h>

#if !TARGET_OS_WIN32
#include <sys/types.h>
#include <libkern/OSAtomic.h>
#else
#   define WINVER 0x0501		// target Windows XP and later
#   define _WIN32_WINNT 0x0501	// target Windows XP and later
#   define WIN32_LEAN_AND_MEAN
// workaround: windef.h typedefs BOOL as int
#   define BOOL WINBOOL
#   include <windows.h>
#   undef BOOL
#endif


/* objc_collect() options */
enum {
    // choose one
    OBJC_RATIO_COLLECTION        = (0 << 0),  // run "ratio" generational collections, then a full
    OBJC_GENERATIONAL_COLLECTION = (1 << 0),  // run fast incremental collection
    OBJC_FULL_COLLECTION         = (2 << 0),  // run full collection.
    OBJC_EXHAUSTIVE_COLLECTION   = (3 << 0),  // run full collections until memory available stops improving
    
    OBJC_COLLECT_IF_NEEDED       = (1 << 3), // run collection only if needed (allocation threshold exceeded)
    OBJC_WAIT_UNTIL_DONE         = (1 << 4), // wait (when possible) for collection to end before returning (when collector is running on dedicated thread)
};

/* objc_clear_stack() options */
enum {
    OBJC_CLEAR_RESIDENT_STACK = (1 << 0)
};

#ifndef OBJC_NO_GC


/* GC declarations */

/* Collection utilities */

OBJC_EXPORT void objc_collect(unsigned long options)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA);
OBJC_EXPORT BOOL objc_collectingEnabled(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT malloc_zone_t *objc_collectableZone(void) 
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_NA);

/* GC configuration */

/* Tells collector to wait until specified bytes have been allocated before trying to collect again. */
OBJC_EXPORT void objc_setCollectionThreshold(size_t threshold)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);

/* Tells collector to run a full collection for every ratio generational collections. */
OBJC_EXPORT void objc_setCollectionRatio(size_t ratio)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);

// 
// GC-safe compare-and-swap
//

/* Atomic update, with write barrier. */
OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) 
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;
/* "Barrier" version also includes memory barrier. */
OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) 
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;

// atomic update of a global variable
OBJC_EXPORT BOOL objc_atomicCompareAndSwapGlobal(id predicate, id replacement, volatile id *objectLocation)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;
OBJC_EXPORT BOOL objc_atomicCompareAndSwapGlobalBarrier(id predicate, id replacement, volatile id *objectLocation)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;
// atomic update of an instance variable
OBJC_EXPORT BOOL objc_atomicCompareAndSwapInstanceVariable(id predicate, id replacement, volatile id *objectLocation)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;
OBJC_EXPORT BOOL objc_atomicCompareAndSwapInstanceVariableBarrier(id predicate, id replacement, volatile id *objectLocation)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA) OBJC_ARC_UNAVAILABLE;


// 
// Read and write barriers
// 

OBJC_EXPORT id objc_assign_strongCast(id val, id *dest)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);
OBJC_EXPORT id objc_assign_global(id val, id *dest)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);
OBJC_EXPORT id objc_assign_threadlocal(id val, id *dest)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_NA);
OBJC_EXPORT id objc_assign_ivar(id value, id dest, ptrdiff_t offset)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);
OBJC_EXPORT void *objc_memmove_collectable(void *dst, const void *src, size_t size)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);

OBJC_EXPORT id objc_read_weak(id *location)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT id objc_assign_weak(id value, id *location)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);


//
// Thread management
// 

/* Register the calling thread with the garbage collector. */
OBJC_EXPORT void objc_registerThreadWithCollector(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA);

/* Unregisters the calling thread with the garbage collector. 
   Unregistration also happens automatically at thread exit. */
OBJC_EXPORT void objc_unregisterThreadWithCollector(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA);

/* To be called from code which must only execute on a registered thread. */
/* If the calling thread is unregistered then an error message is emitted and the thread is implicitly registered. */
OBJC_EXPORT void objc_assertRegisteredThreadWithCollector(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_NA);

/* Erases any stale references in unused parts of the stack. */
OBJC_EXPORT void objc_clear_stack(unsigned long options)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);


//
// Finalization
// 

/* Returns true if object has been scheduled for finalization.  Can be used to avoid operations that may lead to resurrection, which are fatal. */
OBJC_EXPORT BOOL objc_is_finalized(void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_NA);

// Deprcated. Tells runtime to issue finalize calls on the main thread only.
OBJC_EXPORT void objc_finalizeOnMainThread(Class cls)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);


//
// Deprecated names. 
//

/* Deprecated. Use objc_collectingEnabled() instead. */
OBJC_EXPORT BOOL objc_collecting_enabled(void)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_4,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);
/* Deprecated. Use objc_setCollectionThreshold() instead. */
OBJC_EXPORT void objc_set_collection_threshold(size_t threshold)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_4,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);
/* Deprecated. Use objc_setCollectionRatio() instead. */
OBJC_EXPORT void objc_set_collection_ratio(size_t ratio)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_4,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);
/* Deprecated. Use objc_startCollectorThread() instead. */
OBJC_EXPORT void objc_start_collector_thread(void)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_4,__MAC_10_5, __IPHONE_NA,__IPHONE_NA);
/* Deprecated. No replacement. Formerly told the collector to run using a dedicated background thread. */
OBJC_EXPORT void objc_startCollectorThread(void)
__OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_NA,__IPHONE_NA);


/* Deprecated. Use class_createInstance() instead. */
OBJC_EXPORT id objc_allocate_object(Class cls, int extra)
__OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_4,__MAC_10_4, __IPHONE_NA,__IPHONE_NA);


/* !defined(OBJC_NO_GC) */
#else
/* defined(OBJC_NO_GC) */


/* Non-GC declarations */

static OBJC_INLINE void objc_collect(unsigned long options __unused) { }
static OBJC_INLINE BOOL objc_collectingEnabled(void) { return NO; }
#if TARGET_OS_MAC  &&  !TARGET_OS_EMBEDDED  &&  !TARGET_IPHONE_SIMULATOR
static OBJC_INLINE malloc_zone_t *objc_collectableZone(void) { return nil; }
#endif
static OBJC_INLINE void objc_setCollectionThreshold(size_t threshold __unused) { }
static OBJC_INLINE void objc_setCollectionRatio(size_t ratio __unused) { }
static OBJC_INLINE void objc_startCollectorThread(void) { }

#if __has_feature(objc_arc)

/* Covers for GC memory operations are unavailable in ARC */

#else

#if TARGET_OS_WIN32
static OBJC_INLINE BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) 
    { void *original = InterlockedCompareExchangePointer((void * volatile *)objectLocation, (void *)replacement, (void *)predicate); return (original == predicate); }

static OBJC_INLINE BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { void *original = InterlockedCompareExchangePointer((void * volatile *)objectLocation, (void *)replacement, (void *)predicate); return (original == predicate); }
#else
static OBJC_INLINE BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) 
    { return OSAtomicCompareAndSwapPtr((void *)predicate, (void *)replacement, (void * volatile *)objectLocation); }

static OBJC_INLINE BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return OSAtomicCompareAndSwapPtrBarrier((void *)predicate, (void *)replacement, (void * volatile *)objectLocation); }
#endif

static OBJC_INLINE BOOL objc_atomicCompareAndSwapGlobal(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtr(predicate, replacement, objectLocation); }

static OBJC_INLINE BOOL objc_atomicCompareAndSwapGlobalBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtrBarrier(predicate, replacement, objectLocation); }

static OBJC_INLINE BOOL objc_atomicCompareAndSwapInstanceVariable(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtr(predicate, replacement, objectLocation); }

static OBJC_INLINE BOOL objc_atomicCompareAndSwapInstanceVariableBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtrBarrier(predicate, replacement, objectLocation); }


static OBJC_INLINE id objc_assign_strongCast(id val, id *dest) 
    { return (*dest = val); }

static OBJC_INLINE id objc_assign_global(id val, id *dest) 
    { return (*dest = val); }

static OBJC_INLINE id objc_assign_threadlocal(id val, id *dest) 
    { return (*dest = val); }

static OBJC_INLINE id objc_assign_ivar(id val, id dest, ptrdiff_t offset) 
    { return (*(id*)((char *)dest+offset) = val); }

static OBJC_INLINE id objc_read_weak(id *location) 
    { return *location; }

static OBJC_INLINE id objc_assign_weak(id value, id *location) 
    { return (*location = value); }

/* MRC */
#endif

static OBJC_INLINE void *objc_memmove_collectable(void *dst, const void *src, size_t size) 
    { return memmove(dst, src, size); }

static OBJC_INLINE void objc_finalizeOnMainThread(Class cls __unused) { }
static OBJC_INLINE BOOL objc_is_finalized(void *ptr __unused) { return NO; }
static OBJC_INLINE void objc_clear_stack(unsigned long options __unused) { }

static OBJC_INLINE BOOL objc_collecting_enabled(void) { return NO; }
static OBJC_INLINE void objc_set_collection_threshold(size_t threshold __unused) { } 
static OBJC_INLINE void objc_set_collection_ratio(size_t ratio __unused) { } 
static OBJC_INLINE void objc_start_collector_thread(void) { }

#if __has_feature(objc_arc)
extern id objc_allocate_object(Class cls, int extra) UNAVAILABLE_ATTRIBUTE;
#else
OBJC_EXPORT id class_createInstance(Class cls, size_t extraBytes)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
static OBJC_INLINE id objc_allocate_object(Class cls, int extra) 
    { return class_createInstance(cls, extra); }
#endif

static OBJC_INLINE void objc_registerThreadWithCollector() { }
static OBJC_INLINE void objc_unregisterThreadWithCollector() { }
static OBJC_INLINE void objc_assertRegisteredThreadWithCollector() { }

/* defined(OBJC_NO_GC) */
#endif


#if TARGET_OS_EMBEDDED
enum {
    OBJC_GENERATIONAL = (1 << 0)
};
static OBJC_INLINE void objc_collect_if_needed(unsigned long options) __attribute__((deprecated));
static OBJC_INLINE void objc_collect_if_needed(unsigned long options __unused) { }
#endif

#endif
