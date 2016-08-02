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

#include "objc-private.h"


#if OBJC_NO_GC  &&  OBJC_NO_GC_API

// No GC and no GC symbols needed. We're done here.

#elif OBJC_NO_GC  &&  !OBJC_NO_GC_API

// No GC but we do need to export GC symbols.
// These are mostly the same as the OBJC_NO_GC inline versions in objc-auto.h.

OBJC_EXPORT void objc_collect(unsigned long options __unused) { }
OBJC_EXPORT BOOL objc_collectingEnabled(void) { return NO; }
OBJC_EXPORT void objc_setCollectionThreshold(size_t threshold __unused) { }
OBJC_EXPORT void objc_setCollectionRatio(size_t ratio __unused) { }
OBJC_EXPORT void objc_startCollectorThread(void) { }

#if TARGET_OS_WIN32
OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) 
    { void *original = InterlockedCompareExchangePointer((void * volatile *)objectLocation, (void *)replacement, (void *)predicate); return (original == predicate); }

OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { void *original = InterlockedCompareExchangePointer((void * volatile *)objectLocation, (void *)replacement, (void *)predicate); return (original == predicate); }
#else
OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) 
    { return OSAtomicCompareAndSwapPtr((void *)predicate, (void *)replacement, (void * volatile *)objectLocation); }

OBJC_EXPORT BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return OSAtomicCompareAndSwapPtrBarrier((void *)predicate, (void *)replacement, (void * volatile *)objectLocation); }
#endif

OBJC_EXPORT BOOL objc_atomicCompareAndSwapGlobal(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtr(predicate, replacement, objectLocation); }

OBJC_EXPORT BOOL objc_atomicCompareAndSwapGlobalBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtrBarrier(predicate, replacement, objectLocation); }

OBJC_EXPORT BOOL objc_atomicCompareAndSwapInstanceVariable(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtr(predicate, replacement, objectLocation); }

OBJC_EXPORT BOOL objc_atomicCompareAndSwapInstanceVariableBarrier(id predicate, id replacement, volatile id *objectLocation) 
    { return objc_atomicCompareAndSwapPtrBarrier(predicate, replacement, objectLocation); }


OBJC_EXPORT id objc_assign_strongCast(id val, id *dest) 
    { return (*dest = val); }

OBJC_EXPORT id objc_assign_global(id val, id *dest) 
    { return (*dest = val); }

OBJC_EXPORT id objc_assign_threadlocal(id val, id *dest)
    { return (*dest = val); }

OBJC_EXPORT id objc_assign_ivar(id val, id dest, ptrdiff_t offset) 
    { return (*(id*)((char *)dest+offset) = val); }

OBJC_EXPORT id objc_read_weak(id *location) 
    { return *location; }

OBJC_EXPORT id objc_assign_weak(id value, id *location) 
    { return (*location = value); }

OBJC_EXPORT void *objc_memmove_collectable(void *dst, const void *src, size_t size) 
    { return memmove(dst, src, size); }

OBJC_EXPORT void objc_finalizeOnMainThread(Class cls __unused) { }
OBJC_EXPORT BOOL objc_is_finalized(void *ptr __unused) { return NO; }
OBJC_EXPORT void objc_clear_stack(unsigned long options __unused) { }

OBJC_EXPORT BOOL objc_collecting_enabled(void) { return NO; }
OBJC_EXPORT void objc_set_collection_threshold(size_t threshold __unused) { } 
OBJC_EXPORT void objc_set_collection_ratio(size_t ratio __unused) { } 
OBJC_EXPORT void objc_start_collector_thread(void) { }

OBJC_EXPORT id objc_allocate_object(Class cls, int extra) 
    { return class_createInstance(cls, extra); }

OBJC_EXPORT void objc_registerThreadWithCollector() { }
OBJC_EXPORT void objc_unregisterThreadWithCollector() { }
OBJC_EXPORT void objc_assertRegisteredThreadWithCollector() { }

OBJC_EXPORT malloc_zone_t* objc_collect_init(int(*callback)() __unused) { return nil; }
OBJC_EXPORT void* objc_collectableZone() { return nil; }

OBJC_EXPORT BOOL objc_isAuto(id object __unused) { return NO; }
OBJC_EXPORT BOOL objc_dumpHeap(char *filename __unused, unsigned long length __unused)
    { return NO; }

// OBJC_NO_GC && !OBJC_NO_GC_API
#else
// !OBJC_NO_GC

// Garbage collection.

#include <stdint.h>
#include <stdbool.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <libkern/OSAtomic.h>
#include <auto_zone.h>

#include <Block_private.h>
#include <dispatch/private.h>

#include "objc-private.h"
#include "objc-config.h"
#include "objc-accessors.h"
#include "objc-auto.h"
#include "objc-references.h"
#include "maptable.h"
#include "message.h"
#include "objc-gdb.h"

#if DEBUG  &&  !__OBJC2__
#include "objc-exception.h"
#endif


static auto_zone_t *gc_zone_init(void);
static void gc_block_init(void);
static void registeredClassTableInit(void);
static bool objc_isRegisteredClass(Class candidate);

int8_t UseGC = -1;
static bool WantsMainThreadFinalization = NO;

auto_zone_t *gc_zone = nil;


/* Method prototypes */
@interface DoesNotExist
- (const char *)UTF8String;
- (id)description;
@end


/***********************************************************************
* Break-on-error functions
**********************************************************************/

BREAKPOINT_FUNCTION( 
    void objc_assign_ivar_error(id base, ptrdiff_t offset) 
);

BREAKPOINT_FUNCTION( 
    void objc_assign_global_error(id value, id *slot)
);

BREAKPOINT_FUNCTION( 
    void objc_exception_during_finalize_error(void)
);

/***********************************************************************
* Utility exports
* Called by various libraries.
**********************************************************************/

OBJC_EXPORT void objc_set_collection_threshold(size_t threshold) { // Old naming
    if (UseGC) {
        auto_collection_parameters(gc_zone)->collection_threshold = threshold;
    }
}

OBJC_EXPORT void objc_setCollectionThreshold(size_t threshold) {
    if (UseGC) {
        auto_collection_parameters(gc_zone)->collection_threshold = threshold;
    }
}

void objc_setCollectionRatio(size_t ratio) {
    if (UseGC) {
        auto_collection_parameters(gc_zone)->full_vs_gen_frequency = ratio;
    }
}

void objc_set_collection_ratio(size_t ratio) {  // old naming
    if (UseGC) {
        auto_collection_parameters(gc_zone)->full_vs_gen_frequency = ratio;
    }
}

void objc_finalizeOnMainThread(Class cls) {
    if (UseGC) {
        WantsMainThreadFinalization = YES;
        cls->setShouldFinalizeOnMainThread();
    }
}

// stack based data structure queued if/when there is main-thread-only finalization work TBD
typedef struct BatchFinalizeBlock {
    auto_zone_foreach_object_t foreach;
    auto_zone_cursor_t cursor;
    size_t cursor_size;
    volatile bool finished;
    volatile bool started;
    struct BatchFinalizeBlock *next;
} BatchFinalizeBlock_t;

// The Main Thread Finalization Work Queue Head
static struct {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    BatchFinalizeBlock_t *head;
    BatchFinalizeBlock_t *tail;
} MainThreadWorkQ;


void objc_startCollectorThread(void) {
}

void objc_start_collector_thread(void) {
}

static void batchFinalizeOnMainThread(void);

void objc_collect(unsigned long options) {
    if (!UseGC) return;
    bool onMainThread = pthread_main_np();
    
    // while we're here, sneak off and do some finalization work (if any)
    if (onMainThread) batchFinalizeOnMainThread();
    // now on with our normally scheduled programming
    auto_zone_options_t amode = AUTO_ZONE_COLLECT_NO_OPTIONS;
    if (!(options & OBJC_COLLECT_IF_NEEDED)) {
        switch (options & 0x3) {
            case OBJC_RATIO_COLLECTION:        amode = AUTO_ZONE_COLLECT_RATIO_COLLECTION;        break;
            case OBJC_GENERATIONAL_COLLECTION: amode = AUTO_ZONE_COLLECT_GENERATIONAL_COLLECTION; break;
            case OBJC_FULL_COLLECTION:         amode = AUTO_ZONE_COLLECT_FULL_COLLECTION;         break;
            case OBJC_EXHAUSTIVE_COLLECTION:   amode = AUTO_ZONE_COLLECT_EXHAUSTIVE_COLLECTION;   break;
        }
        amode |= AUTO_ZONE_COLLECT_COALESCE;
        amode |= AUTO_ZONE_COLLECT_LOCAL_COLLECTION;
    }
    if (options & OBJC_WAIT_UNTIL_DONE) {
        __block bool done = NO;
        // If executing on the main thread, use the main thread work queue condition to block,
        // so main thread finalization can complete. Otherwise, use a thread-local condition.
        pthread_mutex_t localMutex = PTHREAD_MUTEX_INITIALIZER, *mutex = &localMutex;
        pthread_cond_t localCondition = PTHREAD_COND_INITIALIZER, *condition = &localCondition;
        if (onMainThread) {
            mutex = &MainThreadWorkQ.mutex;
            condition = &MainThreadWorkQ.condition;
        }
        pthread_mutex_lock(mutex);
        auto_zone_collect_and_notify(gc_zone, amode, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            pthread_mutex_lock(mutex);
            done = YES;
            pthread_cond_signal(condition);
            pthread_mutex_unlock(mutex);
        });
        while (!done) {
            pthread_cond_wait(condition, mutex);
            if (onMainThread && MainThreadWorkQ.head) {
                pthread_mutex_unlock(mutex);
                batchFinalizeOnMainThread();
                pthread_mutex_lock(mutex);
            }
        }
        pthread_mutex_unlock(mutex);
    } else {
        auto_zone_collect(gc_zone, amode);
    }
}


// USED BY CF & ONE OTHER
BOOL objc_isAuto(id object) 
{
    return UseGC && auto_zone_is_valid_pointer(gc_zone, object) != 0;
}


BOOL objc_collectingEnabled(void) 
{
    return UseGC;
}

BOOL objc_collecting_enabled(void) // Old naming
{
    return UseGC;
}

malloc_zone_t *objc_collectableZone(void) {
    return gc_zone;
}

BOOL objc_dumpHeap(char *filenamebuffer, unsigned long length) {
    static int counter = 0;
    ++counter;
    char buffer[1024];
    sprintf(buffer, OBJC_HEAP_DUMP_FILENAME_FORMAT, getpid(), counter);
    if (!_objc_dumpHeap(gc_zone, buffer)) return NO;
    if (filenamebuffer) {
        unsigned long blen = strlen(buffer);
        if (blen < length)
            strncpy(filenamebuffer, buffer, blen+1);
        else if (length > 0)
            filenamebuffer[0] = 0;  // give some answer
    }
    return YES;
}


/***********************************************************************
* Memory management. 
* Called by CF and Foundation.
**********************************************************************/

// Allocate an object in the GC zone, with the given number of extra bytes.
id objc_allocate_object(Class cls, int extra) 
{
    return class_createInstance(cls, extra);
}


/***********************************************************************
* Write barrier implementations, optimized for when GC is known to be on
* Called by the write barrier exports only.
* These implementations assume GC is on. The exported function must 
* either perform the check itself or be conditionally stomped at 
* startup time.
**********************************************************************/

id objc_assign_strongCast_gc(id value, id *slot) {
    if (!auto_zone_set_write_barrier(gc_zone, (void*)slot, value)) {    // stores & returns true if slot points into GC allocated memory
        auto_zone_root_write_barrier(gc_zone, slot, value);     // always stores
    }
    return value;
}

id objc_assign_global_gc(id value, id *slot) {
    // use explicit root registration.
    if (value && auto_zone_is_valid_pointer(gc_zone, value)) {
        if (auto_zone_is_finalized(gc_zone, value)) {
            _objc_inform("GC: storing an already collected object %p into global memory at %p, break on objc_assign_global_error to debug\n", (void*)value, slot);
            objc_assign_global_error(value, slot);
        }
        auto_zone_add_root(gc_zone, slot, value);
    }
    else
        *slot = value;

    return value;
}

id objc_assign_threadlocal_gc(id value, id *slot)
{
    if (value && auto_zone_is_valid_pointer(gc_zone, value)) {
        auto_zone_add_root(gc_zone, slot, value);
    }
    else {
        *slot = value;
    }

    return value;
}

id objc_assign_ivar_gc(id value, id base, ptrdiff_t offset) 
{
    id *slot = (id*) ((char *)base + offset);

    if (value) {
        if (!auto_zone_set_write_barrier(gc_zone, (char *)base + offset, value)) {
            _objc_inform("GC: %p + %tu isn't in the auto_zone, break on objc_assign_ivar_error to debug.\n", (void*)base, offset);
            objc_assign_ivar_error(base, offset);
        }
    }
    else
        *slot = value;
    
    return value;
}

id objc_assign_strongCast_non_gc(id value, id *slot) {
    return (*slot = value);
}

id objc_assign_global_non_gc(id value, id *slot) {
    return (*slot = value);
}

id objc_assign_threadlocal_non_gc(id value, id *slot) {
    return (*slot = value);
}

id objc_assign_ivar_non_gc(id value, id base, ptrdiff_t offset) {
    id *slot = (id*) ((char *)base + offset);
    return (*slot = value);
}


/***********************************************************************
* Non-trivial write barriers
**********************************************************************/

void *objc_memmove_collectable(void *dst, const void *src, size_t size)
{
    if (UseGC) {
        return auto_zone_write_barrier_memmove(gc_zone, dst, src, size);
    } else {
        return memmove(dst, src, size);
    }
}

BOOL objc_atomicCompareAndSwapPtr(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL issueMemoryBarrier = NO;
    if (UseGC)
        return auto_zone_atomicCompareAndSwapPtr(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtr((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}

BOOL objc_atomicCompareAndSwapPtrBarrier(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL issueMemoryBarrier = YES;
    if (UseGC)
        return auto_zone_atomicCompareAndSwapPtr(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtrBarrier((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}

BOOL objc_atomicCompareAndSwapGlobal(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL isGlobal = YES;
    const BOOL issueMemoryBarrier = NO;
    if (UseGC)
        return auto_zone_atomicCompareAndSwap(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, isGlobal, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtr((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}

BOOL objc_atomicCompareAndSwapGlobalBarrier(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL isGlobal = YES;
    const BOOL issueMemoryBarrier = YES;
    if (UseGC)
        return auto_zone_atomicCompareAndSwap(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, isGlobal, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtrBarrier((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}

BOOL objc_atomicCompareAndSwapInstanceVariable(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL isGlobal = NO;
    const BOOL issueMemoryBarrier = NO;
    if (UseGC)
        return auto_zone_atomicCompareAndSwap(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, isGlobal, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtr((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}

BOOL objc_atomicCompareAndSwapInstanceVariableBarrier(id predicate, id replacement, volatile id *objectLocation) {
    const BOOL isGlobal = NO;
    const BOOL issueMemoryBarrier = YES;
    if (UseGC)
        return auto_zone_atomicCompareAndSwap(gc_zone, (void *)predicate, (void *)replacement, (void * volatile *)objectLocation, isGlobal, issueMemoryBarrier);
    else
        return OSAtomicCompareAndSwapPtrBarrier((void *)predicate, (void *)replacement, (void * volatile *)objectLocation);
}


/***********************************************************************
* Weak ivar support
**********************************************************************/

id objc_read_weak_gc(id *location) {
    id result = *location;
    if (result) {
        result = (id)auto_read_weak_reference(gc_zone, (void **)location);
    }
    return result;
}

id objc_read_weak_non_gc(id *location) {
    return *location;
}

id objc_assign_weak_gc(id value, id *location) {
    auto_assign_weak_reference(gc_zone, value, (const void **)location, nil);
    return value;
}

id objc_assign_weak_non_gc(id value, id *location) {
    return (*location = value);
}


void gc_fixup_weakreferences(id newObject, id oldObject) {
    // fix up weak references if any.
    const unsigned char *weakLayout = (const unsigned char *)class_getWeakIvarLayout(newObject->ISA());
    if (weakLayout) {
        void **newPtr = (void **)newObject, **oldPtr = (void **)oldObject;
        unsigned char byte;
        while ((byte = *weakLayout++)) {
            unsigned skips = (byte >> 4);
            unsigned weaks = (byte & 0x0F);
            newPtr += skips, oldPtr += skips;
            while (weaks--) {
                *newPtr = nil;
                auto_assign_weak_reference(gc_zone, auto_read_weak_reference(gc_zone, oldPtr), (const void **)newPtr, nil);
                ++newPtr, ++oldPtr;
            }
        }
    }
}


/***********************************************************************
* dyld resolver functions for basic GC write barriers
* dyld calls the resolver function to bind the symbol. 
* We return the GC or non-GC variant as appropriate.
**********************************************************************/

#define GC_RESOLVER(name)                                       \
    OBJC_EXPORT void *name##_resolver(void) __asm__("_" #name); \
    void *name##_resolver(void)                                 \
    {                                                           \
        __asm__(".symbol_resolver _" #name);                    \
        if (UseGC) return (void*)name##_gc;                     \
        else return (void*)name##_non_gc;                       \
    }

GC_RESOLVER(objc_assign_ivar)
GC_RESOLVER(objc_assign_strongCast)
GC_RESOLVER(objc_assign_global)
GC_RESOLVER(objc_assign_threadlocal)
GC_RESOLVER(objc_read_weak)
GC_RESOLVER(objc_assign_weak)
GC_RESOLVER(objc_getProperty)
GC_RESOLVER(objc_setProperty)
GC_RESOLVER(objc_getAssociatedObject)
GC_RESOLVER(objc_setAssociatedObject)
GC_RESOLVER(_object_addExternalReference)
GC_RESOLVER(_object_readExternalReference)
GC_RESOLVER(_object_removeExternalReference)


/***********************************************************************
* Testing tools
* Used to isolate resurrection of garbage objects during finalization.
**********************************************************************/
BOOL objc_is_finalized(void *ptr) {
    if (ptr != nil && UseGC) {
        return auto_zone_is_finalized(gc_zone, ptr);
    }
    return NO;
}


/***********************************************************************
* Stack clearing.
* Used by top-level thread loops to reduce false pointers from the stack.
**********************************************************************/
void objc_clear_stack(unsigned long options) {
    if (!UseGC) return;
    auto_zone_clear_stack(gc_zone, 0);
}


/***********************************************************************
* Finalization support
**********************************************************************/

// Finalizer crash debugging
static void *finalizing_object;

// finalize a single object without fuss
// When there are no main-thread-only classes this is used directly
// Otherwise, it is used indirectly by smarter code that knows main-thread-affinity requirements
static void finalizeOneObject(void *obj, void *ignored) {
    id object = (id)obj;
    finalizing_object = obj;

    Class cls = object->ISA();
    CRSetCrashLogMessage2(class_getName(cls));

    /// call -finalize method.
    ((void(*)(id, SEL))objc_msgSend)(object, @selector(finalize));

    // Call C++ destructors. 
    // This would be objc_destructInstance() but for performance.
    if (cls->hasCxxDtor()) {
        object_cxxDestruct(object);
    }

    finalizing_object = nil;
    CRSetCrashLogMessage2(nil);
}

// finalize object only if it is a main-thread-only object.
// Called only from the main thread.
static void finalizeOneMainThreadOnlyObject(void *obj, void *arg) {
    id object = (id)obj;
    Class cls = object->ISA();
    if (cls == nil) {
        _objc_fatal("object with nil ISA passed to finalizeOneMainThreadOnlyObject:  %p\n", obj);
    }
    if (cls->shouldFinalizeOnMainThread()) {
        finalizeOneObject(obj, nil);
    }
}

// finalize one object only if it is not a main-thread-only object
// called from any other thread than the main thread
// Important: if a main-thread-only object is passed, return that fact in the needsMain argument
static void finalizeOneAnywhereObject(void *obj, void *needsMain) {
    id object = (id)obj;
    Class cls = object->ISA();
    bool *needsMainThreadWork = (bool *)needsMain;
    if (cls == nil) {
        _objc_fatal("object with nil ISA passed to finalizeOneAnywhereObject:  %p\n", obj);
    }
    if (!cls->shouldFinalizeOnMainThread()) {
        finalizeOneObject(obj, nil);
    }
    else {
        *needsMainThreadWork = true;
    }
}


// Utility workhorse.
// Set up the expensive @try block and ask the collector to hand the next object to
// our finalizeAnObject function.
// Track and return a boolean that records whether or not any main thread work is necessary.
// (When we know that there are no main thread only objects then the boolean isn't even computed)
static bool batchFinalize(auto_zone_t *zone,
                          auto_zone_foreach_object_t foreach,
                          auto_zone_cursor_t cursor, 
                          size_t cursor_size,
                          void (*finalizeAnObject)(void *, void*))
{
#if DEBUG  &&  !__OBJC2__
    // debug: don't call try/catch before exception handlers are installed
    objc_exception_functions_t table = {};
    objc_exception_get_functions(&table);
    assert(table.throw_exc);
#endif

    bool needsMainThreadWork = false;
    for (;;) {
        @try {
            foreach(cursor, finalizeAnObject, &needsMainThreadWork);
            // non-exceptional return means finalization is complete.
            break;
        } 
        @catch (id exception) {
            // whoops, note exception, then restart at cursor's position
            _objc_inform("GC: -finalize resulted in an exception (%p) being thrown, break on objc_exception_during_finalize_error to debug\n\t%s", exception, (const char*)[[exception description] UTF8String]);
            objc_exception_during_finalize_error();
        } 
        @catch (...) {
            // whoops, note exception, then restart at cursor's position
            _objc_inform("GC: -finalize resulted in an exception being thrown, break on objc_exception_during_finalize_error to debug");
            objc_exception_during_finalize_error();
        }
    }
    return needsMainThreadWork;
}

// Called on main thread-only.
// Pick up work from global queue.
// called parasitically by anyone requesting a collection
// called explicitly when there is known to be main thread only finalization work
// In both cases we are on the main thread
// Guard against recursion by something called from a finalizer
static void batchFinalizeOnMainThread() {
    pthread_mutex_lock(&MainThreadWorkQ.mutex);
    if (!MainThreadWorkQ.head || MainThreadWorkQ.head->started) {
        // No work or we're already here
        pthread_mutex_unlock(&MainThreadWorkQ.mutex);
        return;
    }
    while (MainThreadWorkQ.head) {
        BatchFinalizeBlock_t *bfb = MainThreadWorkQ.head;
        bfb->started = YES;
        pthread_mutex_unlock(&MainThreadWorkQ.mutex);
            
        batchFinalize(gc_zone, bfb->foreach, bfb->cursor, bfb->cursor_size, finalizeOneMainThreadOnlyObject);
        // signal the collector thread(s) that finalization has finished.
        pthread_mutex_lock(&MainThreadWorkQ.mutex);
        bfb->finished = YES;
        pthread_cond_broadcast(&MainThreadWorkQ.condition);
        MainThreadWorkQ.head = bfb->next;
    }
    MainThreadWorkQ.tail = nil;
    pthread_mutex_unlock(&MainThreadWorkQ.mutex);
}


// Knowing that we possibly have main thread only work to do, first process everything
// that is not main-thread-only.  If we discover main thread only work, queue a work block
// to the main thread that will do just the main thread only work.  Wait for it.
// Called from a non main thread.
static void batchFinalizeOnTwoThreads(auto_zone_t *zone,
                                         auto_zone_foreach_object_t foreach,
                                         auto_zone_cursor_t cursor, 
                                         size_t cursor_size)
{
    // First, lets get rid of everything we can on this thread, then ask main thread to help if needed
    char cursor_copy[cursor_size];
    memcpy(cursor_copy, cursor, cursor_size);
    bool needsMainThreadFinalization = batchFinalize(zone, foreach, (auto_zone_cursor_t)cursor_copy, cursor_size, finalizeOneAnywhereObject);

    if (! needsMainThreadFinalization)
        return;     // no help needed
    
    // set up the control block.  Either our ping of main thread with _callOnMainThread will get to it, or
    // an objc_collect(if_needed) will get to it.  Either way, this block will be processed on the main thread.
    BatchFinalizeBlock_t bfb;
    bfb.foreach = foreach;
    bfb.cursor = cursor;
    bfb.cursor_size = cursor_size;
    bfb.started = NO;
    bfb.finished = NO;
    bfb.next = nil;
    pthread_mutex_lock(&MainThreadWorkQ.mutex);
    if (MainThreadWorkQ.tail) {
    
        // link to end so that ordering of finalization is preserved.
        MainThreadWorkQ.tail->next = &bfb;
        MainThreadWorkQ.tail = &bfb;
    }
    else {
        MainThreadWorkQ.head = &bfb;
        MainThreadWorkQ.tail = &bfb;
    }
    pthread_mutex_unlock(&MainThreadWorkQ.mutex);
    
    //printf("----->asking main thread to finalize\n");
    dispatch_async(dispatch_get_main_queue(), ^{ batchFinalizeOnMainThread(); });
    
    // wait for the main thread to finish finalizing instances of classes marked CLS_FINALIZE_ON_MAIN_THREAD.
    pthread_mutex_lock(&MainThreadWorkQ.mutex);
    while (!bfb.finished) {
        // the main thread might be blocked waiting for a synchronous collection to complete, so wake it here
        pthread_cond_signal(&MainThreadWorkQ.condition);
        pthread_cond_wait(&MainThreadWorkQ.condition, &MainThreadWorkQ.mutex);
    }
    pthread_mutex_unlock(&MainThreadWorkQ.mutex);
    //printf("<------ main thread finalize done\n");

}



// collector calls this with garbage ready
// thread collectors, too, so this needs to be thread-safe
static void BatchInvalidate(auto_zone_t *zone,
                                         auto_zone_foreach_object_t foreach,
                                         auto_zone_cursor_t cursor, 
                                         size_t cursor_size)
{
    if (pthread_main_np() || !WantsMainThreadFinalization) {
        // Collect all objects.  We're either pre-multithreaded on main thread or we're on the collector thread
        // but no main-thread-only objects have been allocated.
        batchFinalize(zone, foreach, cursor, cursor_size, finalizeOneObject);
    }
    else {
        // We're on the dedicated thread.  Collect some on main thread, the rest here.
        batchFinalizeOnTwoThreads(zone, foreach, cursor, cursor_size);
    }
    
}


/*
 * Zombie support
 * Collector calls into this system when it finds resurrected objects.
 * This keeps them pitifully alive and leaked, even if they reference garbage.
 */
 
// idea:  keep a side table mapping resurrected object pointers to their original Class, so we don't
// need to smash anything. alternatively, could use associative references to track against a secondary
// object with information about the resurrection, such as a stack crawl, etc.

static Class _NSResurrectedObjectClass;
static NXMapTable *_NSResurrectedObjectMap = nil;
static pthread_mutex_t _NSResurrectedObjectLock = PTHREAD_MUTEX_INITIALIZER;

static Class resurrectedObjectOriginalClass(id object) {
    Class originalClass;
    pthread_mutex_lock(&_NSResurrectedObjectLock);
    originalClass = (Class) NXMapGet(_NSResurrectedObjectMap, object);
    pthread_mutex_unlock(&_NSResurrectedObjectLock);
    return originalClass;
}

static id _NSResurrectedObject_classMethod(id self, SEL selector) { return self; }

static id _NSResurrectedObject_instanceMethod(id self, SEL name) {
    _objc_inform("**resurrected** object %p of class %s being sent message '%s'\n", (void*)self, class_getName(resurrectedObjectOriginalClass(self)), sel_getName(name));
    return self;
}

static void _NSResurrectedObject_finalize(id self, SEL _cmd) {
    Class originalClass;
    pthread_mutex_lock(&_NSResurrectedObjectLock);
    originalClass = (Class) NXMapRemove(_NSResurrectedObjectMap, self);
    pthread_mutex_unlock(&_NSResurrectedObjectLock);
    if (originalClass) _objc_inform("**resurrected** object %p of class %s being finalized\n", (void*)self, class_getName(originalClass));
    _objc_rootFinalize(self);
}

static bool _NSResurrectedObject_resolveInstanceMethod(id self, SEL _cmd, SEL name) {
    class_addMethod((Class)self, name, (IMP)_NSResurrectedObject_instanceMethod, "@@:");
    return YES;
}

static bool _NSResurrectedObject_resolveClassMethod(id self, SEL _cmd, SEL name) {
    class_addMethod(self->ISA(), name, (IMP)_NSResurrectedObject_classMethod, "@@:");
    return YES;
}

static void _NSResurrectedObject_initialize() {
    _NSResurrectedObjectMap = NXCreateMapTable(NXPtrValueMapPrototype, 128);
    _NSResurrectedObjectClass = objc_allocateClassPair(objc_getClass("NSObject"), "_NSResurrectedObject", 0);
    class_addMethod(_NSResurrectedObjectClass, @selector(finalize), (IMP)_NSResurrectedObject_finalize, "v@:");
    Class metaClass = _NSResurrectedObjectClass->ISA();
    class_addMethod(metaClass, @selector(resolveInstanceMethod:), (IMP)_NSResurrectedObject_resolveInstanceMethod, "c@::");
    class_addMethod(metaClass, @selector(resolveClassMethod:), (IMP)_NSResurrectedObject_resolveClassMethod, "c@::");
    objc_registerClassPair(_NSResurrectedObjectClass);
}

static void resurrectZombie(auto_zone_t *zone, void *ptr) {
    id object = (id) ptr;
    Class cls = object->ISA();
    if (cls != _NSResurrectedObjectClass) {
        // remember the original class for this instance.
        pthread_mutex_lock(&_NSResurrectedObjectLock);
        NXMapInsert(_NSResurrectedObjectMap, ptr, cls);
        pthread_mutex_unlock(&_NSResurrectedObjectLock);
        object_setClass(object, _NSResurrectedObjectClass);
    }
}

/***********************************************************************
* Pretty printing support
* For development purposes.
**********************************************************************/


static char *name_for_address(auto_zone_t *zone, vm_address_t base, vm_address_t offset, int withRetainCount);

static char* objc_name_for_address(auto_zone_t *zone, vm_address_t base, vm_address_t offset)
{
    return name_for_address(zone, base, offset, false);
}

static const char* objc_name_for_object(auto_zone_t *zone, void *object) {
    Class cls = *(Class *)object;
    if (!objc_isRegisteredClass(cls)) return "";
    return class_getName(cls);
}

/***********************************************************************
* Collection support
**********************************************************************/

static bool objc_isRegisteredClass(Class candidate);

static const unsigned char *objc_layout_for_address(auto_zone_t *zone, void *address) {
    id object = (id)address;
    volatile void *clsptr = (void*)object->ISA();
    Class cls = (Class)clsptr;
    return objc_isRegisteredClass(cls) ? _object_getIvarLayout(cls, object) : nil;
}

static const unsigned char *objc_weak_layout_for_address(auto_zone_t *zone, void *address) {
    id object = (id)address;
    volatile void *clsptr = (void*)object->ISA();
    Class cls = (Class)clsptr;
    return objc_isRegisteredClass(cls) ? class_getWeakIvarLayout(cls) : nil;
}

void gc_register_datasegment(uintptr_t base, size_t size) {
    auto_zone_register_datasegment(gc_zone, (void*)base, size);
}

void gc_unregister_datasegment(uintptr_t base, size_t size) {
    auto_zone_unregister_datasegment(gc_zone, (void*)base, size);
}


/***********************************************************************
* Initialization
**********************************************************************/

static void objc_will_grow(auto_zone_t *zone, auto_heap_growth_info_t info) {
    if (auto_zone_is_collecting(gc_zone)) {
        ;
    }
    else  {
        auto_zone_collect(gc_zone, AUTO_ZONE_COLLECT_COALESCE|AUTO_ZONE_COLLECT_RATIO_COLLECTION);
    }
}


static auto_zone_t *gc_zone_init(void)
{
    auto_zone_t *result;
    static int didOnce = 0;
    if (!didOnce) {
        didOnce = 1;
        
        // initialize the batch finalization queue
        MainThreadWorkQ.head = nil;
        MainThreadWorkQ.tail = nil;
        pthread_mutex_init(&MainThreadWorkQ.mutex, nil);
        pthread_cond_init(&MainThreadWorkQ.condition, nil);
    }
    
    result = auto_zone_create("auto_zone");
    
    auto_zone_disable_compaction(result);
    
    auto_collection_control_t *control = auto_collection_parameters(result);
    
    // set up the magic control parameters
    control->batch_invalidate = BatchInvalidate;
    control->will_grow = objc_will_grow;
    control->resurrect = resurrectZombie;
    control->layout_for_address = objc_layout_for_address;
    control->weak_layout_for_address = objc_weak_layout_for_address;
    control->name_for_address = objc_name_for_address;
    
    if (control->version >= sizeof(auto_collection_control_t)) {
        control->name_for_object = objc_name_for_object;
    }

    return result;
}


/* should be defined in /usr/local/include/libdispatch_private.h. */
extern void (*dispatch_begin_thread_4GC)(void);
extern void (*dispatch_end_thread_4GC)(void);

static void objc_reapThreadLocalBlocks()
{
    if (UseGC) auto_zone_reap_all_local_blocks(gc_zone);
}

void objc_registerThreadWithCollector()
{
    if (UseGC) auto_zone_register_thread(gc_zone);
}

void objc_unregisterThreadWithCollector()
{
    if (UseGC) auto_zone_unregister_thread(gc_zone);
}

void objc_assertRegisteredThreadWithCollector()
{
    if (UseGC) auto_zone_assert_thread_registered(gc_zone);
}

// Always called by _objcInit, even if GC is off.
void gc_init(bool wantsGC)
{
    assert(UseGC == -1);
    UseGC = wantsGC;

    if (PrintGC) {
        _objc_inform("GC: is %s", wantsGC ? "ON" : "OFF");
    }

    if (UseGC) {
        // Set up the GC zone
        gc_zone = gc_zone_init();
        
        // tell libdispatch to register its threads with the GC.
        dispatch_begin_thread_4GC = objc_registerThreadWithCollector;
        dispatch_end_thread_4GC = objc_reapThreadLocalBlocks;
        
        // set up the registered classes list
        registeredClassTableInit();

        // tell Blocks to use collectable memory.  CF will cook up the classes separately.
        gc_block_init();

        // Add GC state to crash log reports
        _objc_inform_on_crash("garbage collection is ON");
    }
}


// Called by NSObject +load to perform late GC setup
// This work must wait until after all of libSystem initializes.
void gc_init2(void)
{
    assert(UseGC);

    // create the _NSResurrectedObject class used to track resurrections.
    _NSResurrectedObject_initialize();
    
    // tell libauto to set up its dispatch queues
    auto_collect_multithreaded(gc_zone);
}

// Called by Foundation.
// This function used to initialize NSObject stuff, but now does nothing.
malloc_zone_t *objc_collect_init(int (*callback)(void) __unused)
{
    return (malloc_zone_t *)gc_zone;
}

/*
 * Support routines for the Block implementation
 */


// The Block runtime now needs to sometimes allocate a Block that is an Object - namely
// when it neesd to have a finalizer which, for now, is only if there are C++ destructors
// in the helper function.  Hence the isObject parameter.
// Under GC a -copy message should allocate a refcount 0 block, ergo the isOne parameter.
static void *block_gc_alloc5(const unsigned long size, const bool isOne, const bool isObject) {
    auto_memory_type_t type = isObject ? (AUTO_OBJECT|AUTO_MEMORY_SCANNED) : AUTO_MEMORY_SCANNED;
    return auto_zone_allocate_object(gc_zone, size, type, isOne, false);
}

// The Blocks runtime keeps track of everything above 1 and so it only calls
// up to the collector to tell it about the 0->1 transition and then the 1->0 transition
static void block_gc_setHasRefcount(const void *block, const bool hasRefcount) {
    if (hasRefcount)
        auto_zone_retain(gc_zone, (void *)block);
    else
        auto_zone_release(gc_zone, (void *)block);
}

static void block_gc_memmove(void *dst, void *src, unsigned long size) {
    auto_zone_write_barrier_memmove(gc_zone, dst, src, (size_t)size);
}

static void gc_block_init(void) {
    _Block_use_GC(
                  block_gc_alloc5,
                  block_gc_setHasRefcount,
                  (void (*)(void *, void **))objc_assign_strongCast_gc,
                  (void (*)(const void *, void *))objc_assign_weak,
                  block_gc_memmove
    );
}


/***********************************************************************
* Track classes.
* In addition to the global class hashtable (set) indexed by name, we
* also keep one based purely by pointer when running under Garbage Collection.
* This allows the background collector to race against objects recycled from TLC.
* Specifically, the background collector can read the admin byte and see that
* a thread local object is an object, get scheduled out, and the TLC recovers it,
* linking it into the cache, then the background collector reads the isa field and
* finds linkage info.  By qualifying all isa fields read we avoid this.
**********************************************************************/

// This is a self-contained hash table of all classes.  The first two elements contain the (size-1) and count.
static volatile Class *AllClasses = nil;

#define SHIFT 3
#define INITIALSIZE 512
#define REMOVED ~0ul 

// Allocate the side table.
static void registeredClassTableInit() {
    assert(UseGC);
    // allocate a collectable (refcount 0) zeroed hunk of unscanned memory
    uintptr_t *table = (uintptr_t *)auto_zone_allocate_object(gc_zone, INITIALSIZE*sizeof(void *), AUTO_MEMORY_UNSCANNED, true, true);
    // set initial capacity (as mask)
    table[0] = INITIALSIZE - 1;
    // set initial count
    table[1] = 0;
    AllClasses = (Class *)table;
}

// Verify that a particular pointer is to a class.
// Safe from any thread anytime
static bool objc_isRegisteredClass(Class candidate) {
    assert(UseGC);
    // nil is never a valid ISA.
    if (candidate == nil) return NO;
    // We don't care about a race with another thread adding a class to which we randomly might have a pointer
    // Get local copy of classes so that we're immune from updates.
    // We keep the size of the list as the first element so there is no race as the list & size get updated.
    uintptr_t *allClasses = (uintptr_t *)AllClasses;
    // Slot 0 is always the size of the list in log 2 masked terms (e.g. size - 1) where size is always power of 2
    // Slot 1 is count
    uintptr_t slot = (((uintptr_t)candidate) >> SHIFT) & allClasses[0];
    // avoid slot 0 and 1
    if (slot < 2) slot = 2;
    for(;;) {
        long int slotValue = allClasses[slot];
        if (slotValue == (long int)candidate) {
            return YES;
        }
        if (slotValue == 0) {
            return NO;
        }
        ++slot;
        if (slot > allClasses[0])
            slot = 2;   // skip size, count
    }
}

// Utility used when growing
// Assumes lock held
static void addClassHelper(uintptr_t *table, uintptr_t candidate) {
    uintptr_t slot = (((long int)candidate) >> SHIFT) & table[0];
    if (slot < 2) slot = 2;
    for(;;) {
        uintptr_t slotValue = table[slot];
        if (slotValue == 0) {
            table[slot] = candidate;
            ++table[1];
            return;
        }
        ++slot;
        if (slot > table[0])
            slot = 2;   // skip size, count
    }
}

// lock held by callers
void objc_addRegisteredClass(Class candidate) {
    if (!UseGC) return;
    uintptr_t *table = (uintptr_t *)AllClasses;
    // Slot 0 is always the size of the list in log 2 masked terms (e.g. size - 1) where size is always power of 2
    // Slot 1 is count - always non-zero
    uintptr_t slot = (((long int)candidate) >> SHIFT) & table[0];
    if (slot < 2) slot = 2;
    for(;;) {
        uintptr_t slotValue = table[slot];
        assert(slotValue != (uintptr_t)candidate);
        if (slotValue == REMOVED) {
            table[slot] = (long)candidate;
            return;
        }
        else if (slotValue == 0) {
            table[slot] = (long)candidate;
            if (2*++table[1] > table[0]) {  // add to count; check if we cross 50% utilization
                // grow
                uintptr_t oldSize = table[0]+1;
                uintptr_t *newTable = (uintptr_t *)auto_zone_allocate_object(gc_zone, oldSize*2*sizeof(void *), AUTO_MEMORY_UNSCANNED, true, true);
                uintptr_t i;
                newTable[0] = 2*oldSize - 1;
                newTable[1] = 0;
                for (i = 2; i < oldSize; ++i) {
                    if (table[i] && table[i] != REMOVED)
                        addClassHelper(newTable, table[i]);
                }
                AllClasses = (Class *)newTable;
                // let the old table be collected when other threads are no longer reading it.
                auto_zone_release(gc_zone, (void *)table);
            }
            return;
        }
        ++slot;
        if (slot > table[0])
            slot = 2;   // skip size, count
    }
}

// lock held by callers
void objc_removeRegisteredClass(Class candidate) {
    if (!UseGC) return;
    uintptr_t *table = (uintptr_t *)AllClasses;
    // Slot 0 is always the size of the list in log 2 masked terms (e.g. size - 1) where size is always power of 2
    // Slot 1 is count - always non-zero
    uintptr_t slot = (((uintptr_t)candidate) >> SHIFT) & table[0];
    if (slot < 2) slot = 2;
    for(;;) {
        uintptr_t slotValue = table[slot];
        if (slotValue == (uintptr_t)candidate) {
            table[slot] = REMOVED;  // if next slot == 0 we could set to 0 here and decr count
            return;
        }
        assert(slotValue != 0);
        ++slot;
        if (slot > table[0])
            slot = 2;   // skip size, count
    }
}


/***********************************************************************
* Debugging - support for smart printouts when errors occur
**********************************************************************/


static malloc_zone_t *objc_debug_zone(void)
{
    static malloc_zone_t *z = nil;
    if (!z) {
        z = malloc_create_zone(PAGE_MAX_SIZE, 0);
        malloc_set_zone_name(z, "objc-auto debug");
    }
    return z;
}

static char *_malloc_append_unsigned(uintptr_t value, unsigned base, char *head) {
    if (!value) {
        head[0] = '0';
    } else {
        if (value >= base) head = _malloc_append_unsigned(value / base, base, head);
        value = value % base;
        head[0] = (value < 10) ? '0' + value : 'a' + value - 10;
    }
    return head+1;
}

static void strlcati(char *str, uintptr_t value, size_t bufSize)
{
    if ( (bufSize - strlen(str)) < 30)
        return;
    str = _malloc_append_unsigned(value, 10, str + strlen(str));
    str[0] = '\0';
}


static Ivar ivar_for_offset(Class cls, vm_address_t offset)
{
    unsigned i;
    vm_address_t ivar_offset;
    Ivar super_ivar, result;
    Ivar *ivars;
    unsigned int ivar_count;

    if (!cls) return nil;

    // scan base classes FIRST
    super_ivar = ivar_for_offset(cls->superclass, offset);
    // result is best-effort; our ivars may be closer

    ivars = class_copyIvarList(cls, &ivar_count);
    if (ivars && ivar_count) {
        // Try our first ivar. If it's too big, use super's best ivar.
        // (lose 64-bit precision)
        ivar_offset = ivar_getOffset(ivars[0]);
        if (ivar_offset > offset) result = super_ivar;
        else if (ivar_offset == offset) result = ivars[0];
        else result = nil;

        // Try our other ivars. If any is too big, use the previous.
        for (i = 1; result == nil && i < ivar_count; i++) {
            ivar_offset = ivar_getOffset(ivars[i]);
            if (ivar_offset == offset) {
                result = ivars[i];
            } else if (ivar_offset > offset) {
                result = ivars[i - 1];
            }
        }

        // Found nothing. Return our last ivar.
        if (result == nil)
            result = ivars[ivar_count - 1];
        
        free(ivars);
    } else {
        result = super_ivar;
    }
    
    return result;
}

static void append_ivar_at_offset(char *buf, Class cls, vm_address_t offset, size_t bufSize)
{
    Ivar ivar = nil;

    if (offset == 0) return;  // don't bother with isa
    if (offset >= class_getInstanceSize(cls)) {
        strlcat(buf, ".<extra>+", bufSize);
        strlcati(buf, offset, bufSize);
        return;
    }

    ivar = ivar_for_offset(cls, offset);
    if (!ivar) {
        strlcat(buf, ".<?>", bufSize);
        return;
    }

    // fixme doesn't handle structs etc.
    
    strlcat(buf, ".", bufSize);
    const char *ivar_name = ivar_getName(ivar);
    if (ivar_name) strlcat(buf, ivar_name, bufSize);
    else strlcat(buf, "<anonymous ivar>", bufSize);

    offset -= ivar_getOffset(ivar);
    if (offset > 0) {
        strlcat(buf, "+", bufSize);
        strlcati(buf, offset, bufSize);
    }
}


static const char *cf_class_for_object(void *cfobj)
{
    // ick - we don't link against CF anymore

    struct fake_cfclass {
        size_t version;
        const char *className;
        // don't care about the rest
    };

    const char *result;
    void *dlh;
    size_t (*CFGetTypeID)(void *);
    fake_cfclass * (*_CFRuntimeGetClassWithTypeID)(size_t);

    result = "anonymous_NSCFType";

    dlh = dlopen("/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD | RTLD_FIRST);
    if (!dlh) return result;

    CFGetTypeID = (size_t(*)(void*)) dlsym(dlh, "CFGetTypeID");
    _CFRuntimeGetClassWithTypeID = (fake_cfclass*(*)(size_t)) dlsym(dlh, "_CFRuntimeGetClassWithTypeID");
    
    if (CFGetTypeID  &&  _CFRuntimeGetClassWithTypeID) {
        size_t cfid = (*CFGetTypeID)(cfobj);
        result = (*_CFRuntimeGetClassWithTypeID)(cfid)->className;
    }

    dlclose(dlh);
    return result;
}


static char *name_for_address(auto_zone_t *zone, vm_address_t base, vm_address_t offset, int withRetainCount)
{
#define APPEND_SIZE(s) \
    strlcat(buf, "[", sizeof(buf)); \
    strlcati(buf, s, sizeof(buf)); \
    strlcat(buf, "]", sizeof(buf));

    char buf[1500];
    char *result;

    buf[0] = '\0';

    size_t size = 
        auto_zone_size(zone, (void *)base);
    auto_memory_type_t type = size ? 
        auto_zone_get_layout_type(zone, (void *)base) : AUTO_TYPE_UNKNOWN;
    unsigned int refcount = size ? 
        auto_zone_retain_count(zone, (void *)base) : 0;

    switch (type) {
    case AUTO_OBJECT_SCANNED: 
    case AUTO_OBJECT_UNSCANNED:
    case AUTO_OBJECT_ALL_POINTERS: {
        const char *class_name = object_getClassName((id)base);
        if ((0 == strcmp(class_name, "__NSCFType")) || (0 == strcmp(class_name, "NSCFType"))) {
            strlcat(buf, cf_class_for_object((void *)base), sizeof(buf));
        } else {
            strlcat(buf, class_name, sizeof(buf));
        }
        if (offset) {
            append_ivar_at_offset(buf, ((id)base)->ISA(), offset, sizeof(buf));
        }
        APPEND_SIZE(size);
        break;
    }
    case AUTO_MEMORY_SCANNED:
        strlcat(buf, "{conservative-block}", sizeof(buf));
        APPEND_SIZE(size);
        break;
    case AUTO_MEMORY_UNSCANNED:
        strlcat(buf, "{no-pointers-block}", sizeof(buf));
        APPEND_SIZE(size);
        break;
    case AUTO_MEMORY_ALL_POINTERS:
        strlcat(buf, "{all-pointers-block}", sizeof(buf));
        APPEND_SIZE(size);
        break;
    case AUTO_MEMORY_ALL_WEAK_POINTERS:
        strlcat(buf, "{all-weak-pointers-block}", sizeof(buf));
        APPEND_SIZE(size);
        break;
    case AUTO_TYPE_UNKNOWN:
        strlcat(buf, "{uncollectable-memory}", sizeof(buf));
        break;
    default:
        strlcat(buf, "{unknown-memory-type}", sizeof(buf));
    } 
    
    if (withRetainCount  &&  refcount > 0) {
        strlcat(buf, " [[refcount=", sizeof(buf));
        strlcati(buf, refcount, sizeof(buf));
        strlcat(buf, "]]", sizeof(buf));
    }

    size_t len = 1 + strlen(buf);
    result = (char *)malloc_zone_malloc(objc_debug_zone(), len);
    memcpy(result, buf, len);
    return result;

#undef APPEND_SIZE
}


// not OBJC_NO_GC
#endif
