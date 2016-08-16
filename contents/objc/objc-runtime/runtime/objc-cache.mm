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
* objc-cache.m
* Method cache management
* Cache flushing
* Cache garbage collection
* Cache instrumentation
* Dedicated allocator for large caches
**********************************************************************/


/***********************************************************************
 * Method cache locking (GrP 2001-1-14)
 *
 * For speed, objc_msgSend does not acquire any locks when it reads 
 * method caches. Instead, all cache changes are performed so that any 
 * objc_msgSend running concurrently with the cache mutator will not 
 * crash or hang or get an incorrect result from the cache. 
 *
 * When cache memory becomes unused (e.g. the old cache after cache 
 * expansion), it is not immediately freed, because a concurrent 
 * objc_msgSend could still be using it. Instead, the memory is 
 * disconnected from the data structures and placed on a garbage list. 
 * The memory is now only accessible to instances of objc_msgSend that 
 * were running when the memory was disconnected; any further calls to 
 * objc_msgSend will not see the garbage memory because the other data 
 * structures don't point to it anymore. The collecting_in_critical
 * function checks the PC of all threads and returns FALSE when all threads 
 * are found to be outside objc_msgSend. This means any call to objc_msgSend 
 * that could have had access to the garbage has finished or moved past the 
 * cache lookup stage, so it is safe to free the memory.
 *
 * All functions that modify cache data or structures must acquire the 
 * cacheUpdateLock to prevent interference from concurrent modifications.
 * The function that frees cache garbage must acquire the cacheUpdateLock 
 * and use collecting_in_critical() to flush out cache readers.
 * The cacheUpdateLock is also used to protect the custom allocator used 
 * for large method cache blocks.
 *
 * Cache readers (PC-checked by collecting_in_critical())
 * objc_msgSend*
 * cache_getImp
 *
 * Cache writers (hold cacheUpdateLock while reading or writing; not PC-checked)
 * cache_fill         (acquires lock)
 * cache_expand       (only called from cache_fill)
 * cache_create       (only called from cache_expand)
 * bcopy               (only called from instrumented cache_expand)
 * flush_caches        (acquires lock)
 * cache_flush        (only called from cache_fill and flush_caches)
 * cache_collect_free (only called from cache_expand and cache_flush)
 *
 * UNPROTECTED cache readers (NOT thread-safe; used for debug info only)
 * cache_print
 * _class_printMethodCaches
 * _class_printDuplicateCacheEntries
 * _class_printMethodCacheStatistics
 *
 ***********************************************************************/


#if __OBJC2__

#include "objc-private.h"
#include "objc-cache.h"


/* Initial cache bucket count. INIT_CACHE_SIZE must be a power of two. */
enum {
    INIT_CACHE_SIZE_LOG2 = 2,
    INIT_CACHE_SIZE      = (1 << INIT_CACHE_SIZE_LOG2)
};

static void cache_collect_free(struct bucket_t *data, mask_t capacity);
static int _collecting_in_critical(void);
static void _garbage_make_room(void);


/***********************************************************************
* Cache statistics for OBJC_PRINT_CACHE_SETUP
**********************************************************************/
static unsigned int cache_counts[16];
static size_t cache_allocations;
static size_t cache_collections;

static void recordNewCache(mask_t capacity)
{
    size_t bucket = log2u(capacity);
    if (bucket < countof(cache_counts)) {
        cache_counts[bucket]++;
    }
    cache_allocations++;
}

static void recordDeadCache(mask_t capacity)
{
    size_t bucket = log2u(capacity);
    if (bucket < countof(cache_counts)) {
        cache_counts[bucket]--;
    }
}

/***********************************************************************
* Pointers used by compiled class objects
* These use asm to avoid conflicts with the compiler's internal declarations
**********************************************************************/

// EMPTY_BYTES includes space for a cache end marker bucket.
// This end marker doesn't actually have the wrap-around pointer 
// because cache scans always find an empty bucket before they might wrap.
// 1024 buckets is fairly common.
#if DEBUG
    // Use a smaller size to exercise heap-allocated empty caches.
#   define EMPTY_BYTES ((8+1)*16)
#else
#   define EMPTY_BYTES ((1024+1)*16)
#endif

#define stringize(x) #x
#define stringize2(x) stringize(x)

// "cache" is cache->buckets; "vtable" is cache->mask/occupied
// hack to avoid conflicts with compiler's internal declaration
asm("\n .section __TEXT,__const"
    "\n .globl __objc_empty_vtable"
    "\n .set __objc_empty_vtable, 0"
    "\n .globl __objc_empty_cache"
    "\n .align 3"
    "\n __objc_empty_cache: .space " stringize2(EMPTY_BYTES)
    );


#if __arm__  ||  __x86_64__  ||  __i386__
// objc_msgSend has few registers available.
// Cache scan increments and wraps at special end-marking bucket.
#define CACHE_END_MARKER 1
static inline mask_t cache_next(mask_t i, mask_t mask) {
    return (i+1) & mask;
}

#elif __arm64__
// objc_msgSend has lots of registers available.
// Cache scan decrements. No end marker needed.
#define CACHE_END_MARKER 0
static inline mask_t cache_next(mask_t i, mask_t mask) {
    return i ? i-1 : mask;
}

#else
#error unknown architecture
#endif


#if SUPPORT_IGNORED_SELECTOR_CONSTANT
#error sorry not implemented
#endif


// copied from dispatch_atomic_maximally_synchronizing_barrier
// fixme verify that this barrier hack does in fact work here
#if __x86_64__
#define mega_barrier() \
    do { unsigned long _clbr; __asm__ __volatile__( \
        "cpuid" \
        : "=a" (_clbr) : "0" (0) : "rbx", "rcx", "rdx", "cc", "memory" \
                                                    ); } while(0)

#elif __i386__
#define mega_barrier() \
    do { unsigned long _clbr; __asm__ __volatile__( \
        "cpuid" \
        : "=a" (_clbr) : "0" (0) : "ebx", "ecx", "edx", "cc", "memory" \
                                                    ); } while(0)

#elif __arm__  ||  __arm64__
#define mega_barrier() \
    __asm__ __volatile__( \
        "dsb    ish" \
        : : : "memory")

#else
#error unknown architecture
#endif

#if __arm64__

// Use atomic double-word instructions to update cache entries.
// This requires cache buckets not cross cache line boundaries.
#define stp(onep, twop, destp)                  \
    __asm__ ("stp %[one], %[two], [%[dest]]"    \
             : "=m" (((uint64_t *)(destp))[0]), \
               "=m" (((uint64_t *)(destp))[1])  \
             : [one] "r" (onep),                \
               [two] "r" (twop),                \
               [dest] "r" (destp)               \
             : /* no clobbers */                \
             )
#define ldp(onep, twop, srcp)                   \
    __asm__ ("ldp %[one], %[two], [%[src]]"     \
             : [one] "=r" (onep),               \
               [two] "=r" (twop)                \
             : "m" (((uint64_t *)(srcp))[0]),   \
               "m" (((uint64_t *)(srcp))[1]),   \
               [src] "r" (srcp)                 \
             : /* no clobbers */                \
             )

#endif


// Class points to cache. SEL is key. Cache buckets store SEL+IMP.
// Caches are never built in the dyld shared cache.

static inline mask_t cache_hash(cache_key_t key, mask_t mask) 
{
    return (mask_t)(key & mask);
}

cache_t *getCache(Class cls) 
{
    assert(cls);
    return &cls->cache;
}

cache_key_t getKey(SEL sel) 
{
    assert(sel);
    return (cache_key_t)sel;
}

#if __arm64__

void bucket_t::set(cache_key_t newKey, IMP newImp)
{
    assert(_key == 0  ||  _key == newKey);

    // LDP/STP guarantees that all observers get 
    // either key/imp or newKey/newImp
    stp(newKey, newImp, this);
}

#else

void bucket_t::set(cache_key_t newKey, IMP newImp)
{
    assert(_key == 0  ||  _key == newKey);

    // objc_msgSend uses key and imp with no locks.
    // It is safe for objc_msgSend to see new imp but NULL key
    // (It will get a cache miss but not dispatch to the wrong place.)
    // It is unsafe for objc_msgSend to see old imp and new key.
    // Therefore we write new imp, wait a lot, then write new key.
    
    _imp = newImp;
    
    if (_key != newKey) {
        mega_barrier();
        _key = newKey;
    }
}

#endif

void cache_t::setBucketsAndMask(struct bucket_t *newBuckets, mask_t newMask)
{
    // objc_msgSend uses mask and buckets with no locks.
    // It is safe for objc_msgSend to see new buckets but old mask.
    // (It will get a cache miss but not overrun the buckets' bounds).
    // It is unsafe for objc_msgSend to see old buckets and new mask.
    // Therefore we write new buckets, wait a lot, then write new mask.
    // objc_msgSend reads mask first, then buckets.

    // ensure other threads see buckets contents before buckets pointer
    mega_barrier();

    _buckets = newBuckets;
    
    // ensure other threads see new buckets before new mask
    mega_barrier();
    
    _mask = newMask;
    _occupied = 0;
}


struct bucket_t *cache_t::buckets() 
{
    return _buckets; 
}

mask_t cache_t::mask() 
{
    return _mask; 
}

mask_t cache_t::occupied() 
{
    return _occupied;
}

void cache_t::incrementOccupied() 
{
    _occupied++;
}

void cache_t::initializeToEmpty()
{
    bzero(this, sizeof(*this));
    _buckets = (bucket_t *)&_objc_empty_cache;
}


mask_t cache_t::capacity() 
{
    return mask() ? mask()+1 : 0; 
}


#if CACHE_END_MARKER

size_t cache_t::bytesForCapacity(uint32_t cap) 
{
    // fixme put end marker inline when capacity+1 malloc is inefficient
    return sizeof(bucket_t) * (cap + 1);
}

bucket_t *cache_t::endMarker(struct bucket_t *b, uint32_t cap) 
{
    // bytesForCapacity() chooses whether the end marker is inline or not
    return (bucket_t *)((uintptr_t)b + bytesForCapacity(cap)) - 1;
}

bucket_t *allocateBuckets(mask_t newCapacity)
{
    // Allocate one extra bucket to mark the end of the list.
    // This can't overflow mask_t because newCapacity is a power of 2.
    // fixme instead put the end mark inline when +1 is malloc-inefficient
    bucket_t *newBuckets = (bucket_t *)
        calloc(cache_t::bytesForCapacity(newCapacity), 1);

    bucket_t *end = cache_t::endMarker(newBuckets, newCapacity);

#if __arm__
    // End marker's key is 1 and imp points BEFORE the first bucket.
    // This saves an instruction in objc_msgSend.
    end->setKey((cache_key_t)(uintptr_t)1);
    end->setImp((IMP)(newBuckets - 1));
#else
    // End marker's key is 1 and imp points to the first bucket.
    end->setKey((cache_key_t)(uintptr_t)1);
    end->setImp((IMP)newBuckets);
#endif
    
    if (PrintCaches) recordNewCache(newCapacity);

    return newBuckets;
}

#else

size_t cache_t::bytesForCapacity(uint32_t cap) 
{
    return sizeof(bucket_t) * cap;
}

bucket_t *allocateBuckets(mask_t newCapacity)
{
    if (PrintCaches) recordNewCache(newCapacity);

    return (bucket_t *)calloc(cache_t::bytesForCapacity(newCapacity), 1);
}

#endif


bucket_t *emptyBucketsForCapacity(mask_t capacity, bool allocate = true)
{
    cacheUpdateLock.assertLocked();

    size_t bytes = cache_t::bytesForCapacity(capacity);

    // Use _objc_empty_cache if the buckets is small enough.
    if (bytes <= EMPTY_BYTES) {
        return (bucket_t *)&_objc_empty_cache;
    }

    // Use shared empty buckets allocated on the heap.
    static bucket_t **emptyBucketsList = nil;
    static mask_t emptyBucketsListCount = 0;
    
    mask_t index = log2u(capacity);

    if (index >= emptyBucketsListCount) {
        if (!allocate) return nil;

        mask_t newListCount = index + 1;
        bucket_t *newBuckets = (bucket_t *)calloc(bytes, 1);
        emptyBucketsList = (bucket_t**)
            realloc(emptyBucketsList, newListCount * sizeof(bucket_t *));
        // Share newBuckets for every un-allocated size smaller than index.
        // The array is therefore always fully populated.
        for (mask_t i = emptyBucketsListCount; i < newListCount; i++) {
            emptyBucketsList[i] = newBuckets;
        }
        emptyBucketsListCount = newListCount;

        if (PrintCaches) {
            _objc_inform("CACHES: new empty buckets at %p (capacity %zu)", 
                         newBuckets, (size_t)capacity);
        }
    }

    return emptyBucketsList[index];
}


bool cache_t::isConstantEmptyCache()
{
    return 
        occupied() == 0  &&  
        buckets() == emptyBucketsForCapacity(capacity(), false);
}

bool cache_t::canBeFreed()
{
    return !isConstantEmptyCache();
}


void cache_t::reallocate(mask_t oldCapacity, mask_t newCapacity)
{
    bool freeOld = canBeFreed();

    bucket_t *oldBuckets = buckets();
    bucket_t *newBuckets = allocateBuckets(newCapacity);

    // Cache's old contents are not propagated. 
    // This is thought to save cache memory at the cost of extra cache fills.
    // fixme re-measure this

    assert(newCapacity > 0);
    assert((uintptr_t)(mask_t)(newCapacity-1) == newCapacity-1);

    setBucketsAndMask(newBuckets, newCapacity - 1);
    
    if (freeOld) {
        cache_collect_free(oldBuckets, oldCapacity);
        cache_collect(false);
    }
}


void cache_t::bad_cache(id receiver, SEL sel, Class isa)
{
    // Log in separate steps in case the logging itself causes a crash.
    _objc_inform_now_and_on_crash
        ("Method cache corrupted. This may be a message to an "
         "invalid object, or a memory error somewhere else.");
    cache_t *cache = &isa->cache;
    _objc_inform_now_and_on_crash
        ("%s %p, SEL %p, isa %p, cache %p, buckets %p, "
         "mask 0x%x, occupied 0x%x", 
         receiver ? "receiver" : "unused", receiver, 
         sel, isa, cache, cache->_buckets, 
         cache->_mask, cache->_occupied);
    _objc_inform_now_and_on_crash
        ("%s %zu bytes, buckets %zu bytes", 
         receiver ? "receiver" : "unused", malloc_size(receiver), 
         malloc_size(cache->_buckets));
    _objc_inform_now_and_on_crash
        ("selector '%s'", sel_getName(sel));
    _objc_inform_now_and_on_crash
        ("isa '%s'", isa->nameForLogging());
    _objc_fatal
        ("Method cache corrupted.");
}


bucket_t * cache_t::find(cache_key_t k, id receiver)
{
    assert(k != 0);

    bucket_t *b = buckets();
    mask_t m = mask();
    mask_t begin = cache_hash(k, m);
    mask_t i = begin;
    do {
        if (b[i].key() == 0  ||  b[i].key() == k) {
            return &b[i];
        }
    } while ((i = cache_next(i, m)) != begin);

    // hack
    Class cls = (Class)((uintptr_t)this - offsetof(objc_class, cache));
    cache_t::bad_cache(receiver, (SEL)k, cls);
}


void cache_t::expand()
{
    cacheUpdateLock.assertLocked();
    
    uint32_t oldCapacity = capacity();
    uint32_t newCapacity = oldCapacity ? oldCapacity*2 : INIT_CACHE_SIZE;

    if ((uint32_t)(mask_t)newCapacity != newCapacity) {
        // mask overflow - can't grow further
        // fixme this wastes one bit of mask
        newCapacity = oldCapacity;
    }

    reallocate(oldCapacity, newCapacity);
}


static void cache_fill_nolock(Class cls, SEL sel, IMP imp, id receiver)
{
    cacheUpdateLock.assertLocked();

    // Never cache before +initialize is done
    if (!cls->isInitialized()) return;

    // Make sure the entry wasn't added to the cache by some other thread 
    // before we grabbed the cacheUpdateLock.
    if (cache_getImp(cls, sel)) return;

    cache_t *cache = getCache(cls);
    cache_key_t key = getKey(sel);

    // Use the cache as-is if it is less than 3/4 full
    mask_t newOccupied = cache->occupied() + 1;
    mask_t capacity = cache->capacity();
    if (cache->isConstantEmptyCache()) {
        // Cache is read-only. Replace it.
        cache->reallocate(capacity, capacity ?: INIT_CACHE_SIZE);
    }
    else if (newOccupied <= capacity / 4 * 3) {
        // Cache is less than 3/4 full. Use it as-is.
    }
    else {
        // Cache is too full. Expand it.
        cache->expand();
    }

    // Scan for the first unused slot and insert there.
    // There is guaranteed to be an empty slot because the 
    // minimum size is 4 and we resized at 3/4 full.
    bucket_t *bucket = cache->find(key, receiver);
    if (bucket->key() == 0) cache->incrementOccupied();
    bucket->set(key, imp);
}

void cache_fill(Class cls, SEL sel, IMP imp, id receiver)
{
#if !DEBUG_TASK_THREADS
    mutex_locker_t lock(cacheUpdateLock);
    cache_fill_nolock(cls, sel, imp, receiver);
#else
    _collecting_in_critical();
    return;
#endif
}


// Reset this entire cache to the uncached lookup by reallocating it.
// This must not shrink the cache - that breaks the lock-free scheme.
void cache_erase_nolock(Class cls)
{
    cacheUpdateLock.assertLocked();

    cache_t *cache = getCache(cls);

    mask_t capacity = cache->capacity();
    if (capacity > 0  &&  cache->occupied() > 0) {
        auto oldBuckets = cache->buckets();
        auto buckets = emptyBucketsForCapacity(capacity);
        cache->setBucketsAndMask(buckets, capacity - 1); // also clears occupied

        cache_collect_free(oldBuckets, capacity);
        cache_collect(false);
    }
}


void cache_delete(Class cls)
{
    mutex_locker_t lock(cacheUpdateLock);
    if (cls->cache.canBeFreed()) {
        if (PrintCaches) recordDeadCache(cls->cache.capacity());
        free(cls->cache.buckets());
    }
}


/***********************************************************************
* cache collection.
**********************************************************************/

#if !TARGET_OS_WIN32

// A sentinel (magic value) to report bad thread_get_state status.
// Must not be a valid PC.
// Must not be zero - thread_get_state() on a new thread returns PC == 0.
#define PC_SENTINEL  1

static uintptr_t _get_pc_for_thread(thread_t thread)
#if defined(__i386__)
{
    i386_thread_state_t state;
    unsigned int count = i386_THREAD_STATE_COUNT;
    kern_return_t okay = thread_get_state (thread, i386_THREAD_STATE, (thread_state_t)&state, &count);
    return (okay == KERN_SUCCESS) ? state.__eip : PC_SENTINEL;
}
#elif defined(__x86_64__)
{
    x86_thread_state64_t			state;
    unsigned int count = x86_THREAD_STATE64_COUNT;
    kern_return_t okay = thread_get_state (thread, x86_THREAD_STATE64, (thread_state_t)&state, &count);
    return (okay == KERN_SUCCESS) ? state.__rip : PC_SENTINEL;
}
#elif defined(__arm__)
{
    arm_thread_state_t state;
    unsigned int count = ARM_THREAD_STATE_COUNT;
    kern_return_t okay = thread_get_state (thread, ARM_THREAD_STATE, (thread_state_t)&state, &count);
    return (okay == KERN_SUCCESS) ? state.__pc : PC_SENTINEL;
}
#elif defined(__arm64__)
{
    arm_thread_state64_t state;
    unsigned int count = ARM_THREAD_STATE64_COUNT;
    kern_return_t okay = thread_get_state (thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    return (okay == KERN_SUCCESS) ? state.__pc : PC_SENTINEL;
}
#else
{
#error _get_pc_for_thread () not implemented for this architecture
}
#endif

#endif

/***********************************************************************
* _collecting_in_critical.
* Returns TRUE if some thread is currently executing a cache-reading 
* function. Collection of cache garbage is not allowed when a cache-
* reading function is in progress because it might still be using 
* the garbage memory.
**********************************************************************/
OBJC_EXPORT uintptr_t objc_entryPoints[];
OBJC_EXPORT uintptr_t objc_exitPoints[];

static int _collecting_in_critical(void)
{
#if TARGET_OS_WIN32
    return TRUE;
#else
    thread_act_port_array_t threads;
    unsigned number;
    unsigned count;
    kern_return_t ret;
    int result;

    mach_port_t mythread = pthread_mach_thread_np(pthread_self());

    // Get a list of all the threads in the current task
#if !DEBUG_TASK_THREADS
    ret = task_threads(mach_task_self(), &threads, &number);
#else
    ret = objc_task_threads(mach_task_self(), &threads, &number);
#endif

    if (ret != KERN_SUCCESS) {
        // See DEBUG_TASK_THREADS below to help debug this.
        _objc_fatal("task_threads failed (result 0x%x)\n", ret);
    }

    // Check whether any thread is in the cache lookup code
    result = FALSE;
    for (count = 0; count < number; count++)
    {
        int region;
        uintptr_t pc;

        // Don't bother checking ourselves
        if (threads[count] == mythread)
            continue;

        // Find out where thread is executing
        pc = _get_pc_for_thread (threads[count]);

        // Check for bad status, and if so, assume the worse (can't collect)
        if (pc == PC_SENTINEL)
        {
            result = TRUE;
            goto done;
        }
        
        // Check whether it is in the cache lookup code
        for (region = 0; objc_entryPoints[region] != 0; region++)
        {
            if ((pc >= objc_entryPoints[region]) &&
                (pc <= objc_exitPoints[region])) 
            {
                result = TRUE;
                goto done;
            }
        }
    }

 done:
    // Deallocate the port rights for the threads
    for (count = 0; count < number; count++) {
        mach_port_deallocate(mach_task_self (), threads[count]);
    }

    // Deallocate the thread list
    vm_deallocate (mach_task_self (), (vm_address_t) threads, sizeof(threads[0]) * number);

    // Return our finding
    return result;
#endif
}


/***********************************************************************
* _garbage_make_room.  Ensure that there is enough room for at least
* one more ref in the garbage.
**********************************************************************/

// amount of memory represented by all refs in the garbage
static size_t garbage_byte_size = 0;

// do not empty the garbage until garbage_byte_size gets at least this big
static size_t garbage_threshold = 32*1024;

// table of refs to free
static bucket_t **garbage_refs = 0;

// current number of refs in garbage_refs
static size_t garbage_count = 0;

// capacity of current garbage_refs
static size_t garbage_max = 0;

// capacity of initial garbage_refs
enum {
    INIT_GARBAGE_COUNT = 128
};

static void _garbage_make_room(void)
{
    static int first = 1;

    // Create the collection table the first time it is needed
    if (first)
    {
        first = 0;
        garbage_refs = (bucket_t**)
            malloc(INIT_GARBAGE_COUNT * sizeof(void *));
        garbage_max = INIT_GARBAGE_COUNT;
    }

    // Double the table if it is full
    else if (garbage_count == garbage_max)
    {
        garbage_refs = (bucket_t**)
            realloc(garbage_refs, garbage_max * 2 * sizeof(void *));
        garbage_max *= 2;
    }
}


/***********************************************************************
* cache_collect_free.  Add the specified malloc'd memory to the list
* of them to free at some later point.
* size is used for the collection threshold. It does not have to be 
* precisely the block's size.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static void cache_collect_free(bucket_t *data, mask_t capacity)
{
    cacheUpdateLock.assertLocked();

    if (PrintCaches) recordDeadCache(capacity);

    _garbage_make_room ();
    garbage_byte_size += cache_t::bytesForCapacity(capacity);
    garbage_refs[garbage_count++] = data;
}


/***********************************************************************
* cache_collect.  Try to free accumulated dead caches.
* collectALot tries harder to free memory.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
void cache_collect(bool collectALot)
{
    cacheUpdateLock.assertLocked();

    // Done if the garbage is not full
    if (garbage_byte_size < garbage_threshold  &&  !collectALot) {
        return;
    }

    // Synchronize collection with objc_msgSend and other cache readers
    if (!collectALot) {
        if (_collecting_in_critical ()) {
            // objc_msgSend (or other cache reader) is currently looking in
            // the cache and might still be using some garbage.
            if (PrintCaches) {
                _objc_inform ("CACHES: not collecting; "
                              "objc_msgSend in progress");
            }
            return;
        }
    } 
    else {
        // No excuses.
        while (_collecting_in_critical()) 
            ;
    }

    // No cache readers in progress - garbage is now deletable

    // Log our progress
    if (PrintCaches) {
        cache_collections++;
        _objc_inform ("CACHES: COLLECTING %zu bytes (%zu allocations, %zu collections)", garbage_byte_size, cache_allocations, cache_collections);
    }
    
    // Dispose all refs now in the garbage
    while (garbage_count--) {
        free(garbage_refs[garbage_count]);
    }
    
    // Clear the garbage count and total size indicator
    garbage_count = 0;
    garbage_byte_size = 0;

    if (PrintCaches) {
        size_t i;
        size_t total_count = 0;
        size_t total_size = 0;

        for (i = 0; i < countof(cache_counts); i++) {
            int count = cache_counts[i];
            int slots = 1 << i;
            size_t size = count * slots * sizeof(bucket_t);

            if (!count) continue;

            _objc_inform("CACHES: %4d slots: %4d caches, %6zu bytes", 
                         slots, count, size);

            total_count += count;
            total_size += size;
        }

        _objc_inform("CACHES:      total: %4zu caches, %6zu bytes", 
                     total_count, total_size);
    }
}


/***********************************************************************
* objc_task_threads
* Replacement for task_threads(). Define DEBUG_TASK_THREADS to debug 
* crashes when task_threads() is failing.
*
* A failure in task_threads() usually means somebody has botched their 
* Mach or MIG traffic. For example, somebody's error handling was wrong 
* and they left a message queued on the MIG reply port for task_threads() 
* to trip over.
*
* The code below is a modified version of task_threads(). It logs 
* the msgh_id of the reply message. The msgh_id can identify the sender 
* of the message, which can help pinpoint the faulty code.
* DEBUG_TASK_THREADS also calls collecting_in_critical() during every 
* message dispatch, which can increase reproducibility of bugs.
*
* This code can be regenerated by running 
* `mig /usr/include/mach/task.defs`.
**********************************************************************/
#if DEBUG_TASK_THREADS

#include <mach/mach.h>
#include <mach/message.h>
#include <mach/mig.h>

#define __MIG_check__Reply__task_subsystem__ 1
#define mig_internal static inline
#define __DeclareSendRpc(a, b)
#define __BeforeSendRpc(a, b)
#define __AfterSendRpc(a, b)
#define msgh_request_port       msgh_remote_port
#define msgh_reply_port         msgh_local_port

#ifndef __MachMsgErrorWithTimeout
#define __MachMsgErrorWithTimeout(_R_) { \
        switch (_R_) { \
        case MACH_SEND_INVALID_DATA: \
        case MACH_SEND_INVALID_DEST: \
        case MACH_SEND_INVALID_HEADER: \
            mig_put_reply_port(InP->Head.msgh_reply_port); \
            break; \
        case MACH_SEND_TIMED_OUT: \
        case MACH_RCV_TIMED_OUT: \
        default: \
            mig_dealloc_reply_port(InP->Head.msgh_reply_port); \
        } \
    }
#endif  /* __MachMsgErrorWithTimeout */

#ifndef __MachMsgErrorWithoutTimeout
#define __MachMsgErrorWithoutTimeout(_R_) { \
        switch (_R_) { \
        case MACH_SEND_INVALID_DATA: \
        case MACH_SEND_INVALID_DEST: \
        case MACH_SEND_INVALID_HEADER: \
            mig_put_reply_port(InP->Head.msgh_reply_port); \
            break; \
        default: \
            mig_dealloc_reply_port(InP->Head.msgh_reply_port); \
        } \
    }
#endif  /* __MachMsgErrorWithoutTimeout */


#if ( __MigTypeCheck )
#if __MIG_check__Reply__task_subsystem__
#if !defined(__MIG_check__Reply__task_threads_t__defined)
#define __MIG_check__Reply__task_threads_t__defined

mig_internal kern_return_t __MIG_check__Reply__task_threads_t(__Reply__task_threads_t *Out0P)
{

	typedef __Reply__task_threads_t __Reply;
	boolean_t msgh_simple;
#if	__MigTypeCheck
	unsigned int msgh_size;
#endif	/* __MigTypeCheck */
	if (Out0P->Head.msgh_id != 3502) {
	    if (Out0P->Head.msgh_id == MACH_NOTIFY_SEND_ONCE)
		{ return MIG_SERVER_DIED; }
	    else
		{ return MIG_REPLY_MISMATCH; }
	}

	msgh_simple = !(Out0P->Head.msgh_bits & MACH_MSGH_BITS_COMPLEX);
#if	__MigTypeCheck
	msgh_size = Out0P->Head.msgh_size;

	if ((msgh_simple || Out0P->msgh_body.msgh_descriptor_count != 1 ||
	    msgh_size != (mach_msg_size_t)sizeof(__Reply)) &&
	    (!msgh_simple || msgh_size != (mach_msg_size_t)sizeof(mig_reply_error_t) ||
	    ((mig_reply_error_t *)Out0P)->RetCode == KERN_SUCCESS))
		{ return MIG_TYPE_ERROR ; }
#endif	/* __MigTypeCheck */

	if (msgh_simple) {
		return ((mig_reply_error_t *)Out0P)->RetCode;
	}

#if	__MigTypeCheck
	if (Out0P->act_list.type != MACH_MSG_OOL_PORTS_DESCRIPTOR ||
	    Out0P->act_list.disposition != 17) {
		return MIG_TYPE_ERROR;
	}
#endif	/* __MigTypeCheck */

	return MACH_MSG_SUCCESS;
}
#endif /* !defined(__MIG_check__Reply__task_threads_t__defined) */
#endif /* __MIG_check__Reply__task_subsystem__ */
#endif /* ( __MigTypeCheck ) */


/* Routine task_threads */
static kern_return_t objc_task_threads
(
	task_t target_task,
	thread_act_array_t *act_list,
	mach_msg_type_number_t *act_listCnt
)
{

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
	} Request;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_ool_ports_descriptor_t act_list;
		/* end of the kernel processed data */
		NDR_record_t NDR;
		mach_msg_type_number_t act_listCnt;
		mach_msg_trailer_t trailer;
	} Reply;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_ool_ports_descriptor_t act_list;
		/* end of the kernel processed data */
		NDR_record_t NDR;
		mach_msg_type_number_t act_listCnt;
	} __Reply;
#ifdef  __MigPackStructs
#pragma pack()
#endif
	/*
	 * typedef struct {
	 * 	mach_msg_header_t Head;
	 * 	NDR_record_t NDR;
	 * 	kern_return_t RetCode;
	 * } mig_reply_error_t;
	 */

	union {
		Request In;
		Reply Out;
	} Mess;

	Request *InP = &Mess.In;
	Reply *Out0P = &Mess.Out;

	mach_msg_return_t msg_result;

#ifdef	__MIG_check__Reply__task_threads_t__defined
	kern_return_t check_result;
#endif	/* __MIG_check__Reply__task_threads_t__defined */

	__DeclareSendRpc(3402, "task_threads")

	InP->Head.msgh_bits =
		MACH_MSGH_BITS(19, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	/* msgh_size passed as argument */
	InP->Head.msgh_request_port = target_task;
	InP->Head.msgh_reply_port = mig_get_reply_port();
	InP->Head.msgh_id = 3402;

	__BeforeSendRpc(3402, "task_threads")
	msg_result = mach_msg(&InP->Head, MACH_SEND_MSG|MACH_RCV_MSG|MACH_MSG_OPTION_NONE, (mach_msg_size_t)sizeof(Request), (mach_msg_size_t)sizeof(Reply), InP->Head.msgh_reply_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	__AfterSendRpc(3402, "task_threads")
	if (msg_result != MACH_MSG_SUCCESS) {
		_objc_inform("task_threads received unexpected reply msgh_id 0x%zx", 
                             (size_t)Out0P->Head.msgh_id);
		__MachMsgErrorWithoutTimeout(msg_result);
		{ return msg_result; }
	}


#if	defined(__MIG_check__Reply__task_threads_t__defined)
	check_result = __MIG_check__Reply__task_threads_t((__Reply__task_threads_t *)Out0P);
	if (check_result != MACH_MSG_SUCCESS)
		{ return check_result; }
#endif	/* defined(__MIG_check__Reply__task_threads_t__defined) */

	*act_list = (thread_act_array_t)(Out0P->act_list.address);
	*act_listCnt = Out0P->act_listCnt;

	return KERN_SUCCESS;
}

// DEBUG_TASK_THREADS
#endif


// __OBJC2__
#endif
