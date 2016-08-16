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
 * _cache_getImp
 * _cache_getMethod
 *
 * Cache writers (hold cacheUpdateLock while reading or writing; not PC-checked)
 * _cache_fill         (acquires lock)
 * _cache_expand       (only called from cache_fill)
 * _cache_create       (only called from cache_expand)
 * bcopy               (only called from instrumented cache_expand)
 * flush_caches        (acquires lock)
 * _cache_flush        (only called from cache_fill and flush_caches)
 * _cache_collect_free (only called from cache_expand and cache_flush)
 *
 * UNPROTECTED cache readers (NOT thread-safe; used for debug info only)
 * _cache_print
 * _class_printMethodCaches
 * _class_printDuplicateCacheEntries
 * _class_printMethodCacheStatistics
 *
 * _class_lookupMethodAndLoadCache is a special case. It may read a 
 * method triplet out of one cache and store it in another cache. This 
 * is unsafe if the method triplet is a forward:: entry, because the 
 * triplet itself could be freed unless _class_lookupMethodAndLoadCache 
 * were PC-checked or used a lock. Additionally, storing the method 
 * triplet in both caches would result in double-freeing if both caches 
 * were flushed or expanded. The solution is for _cache_getMethod to 
 * ignore all entries whose implementation is _objc_msgForward_impcache, 
 * so _class_lookupMethodAndLoadCache cannot look at a forward:: entry
 * unsafely or place it in multiple caches.
 ***********************************************************************/

#if !__OBJC2__

#include "objc-private.h"
#include "objc-cache-old.h"
#include "hashtable2.h"

typedef struct {
    SEL name;     // same layout as struct old_method
    void *unused;
    IMP imp;  // same layout as struct old_method
} cache_entry;


/* When _class_slow_grow is non-zero, any given cache is actually grown
 * only on the odd-numbered times it becomes full; on the even-numbered
 * times, it is simply emptied and re-used.  When this flag is zero,
 * caches are grown every time. */
static const int _class_slow_grow = 1;

/* For min cache size: clear_cache=1, slow_grow=1
   For max cache size: clear_cache=0, slow_grow=0 */

/* Initial cache bucket count. INIT_CACHE_SIZE must be a power of two. */
enum {
    INIT_CACHE_SIZE_LOG2 = 2,
    INIT_CACHE_SIZE      = (1 << INIT_CACHE_SIZE_LOG2)
};


/* Amount of space required for `count` hash table buckets, knowing that
 * one entry is embedded in the cache structure itself. */
#define TABLE_SIZE(count)  ((count - 1) * sizeof(cache_entry *))


#if !TARGET_OS_WIN32
#   define CACHE_ALLOCATOR
#endif

/* Custom cache allocator parameters.
 * CACHE_REGION_SIZE must be a multiple of CACHE_QUANTUM. */
#define CACHE_ALLOCATOR_MIN 512
#define CACHE_QUANTUM (CACHE_ALLOCATOR_MIN+sizeof(struct objc_cache)-sizeof(cache_entry*))
#define CACHE_REGION_SIZE ((128*1024 / CACHE_QUANTUM) * CACHE_QUANTUM)
// #define CACHE_REGION_SIZE ((256*1024 / CACHE_QUANTUM) * CACHE_QUANTUM)

static uintptr_t cache_allocator_mask_for_size(size_t size)
{
    return (size - sizeof(struct objc_cache)) / sizeof(cache_entry *);
}

static size_t cache_allocator_size_for_mask(uintptr_t mask)
{
    size_t requested = sizeof(struct objc_cache) + TABLE_SIZE(mask+1);
    size_t actual = CACHE_QUANTUM;
    while (actual < requested) actual += CACHE_QUANTUM;
    return actual;
}


/* Cache instrumentation data. Immediately follows the cache block itself. */
#ifdef OBJC_INSTRUMENTED
typedef struct
{
    unsigned int hitCount;           // cache lookup success tally
    unsigned int hitProbes;          // sum entries checked to hit
    unsigned int maxHitProbes;       // max entries checked to hit
    unsigned int missCount;          // cache lookup no-find tally
    unsigned int missProbes;         // sum entries checked to miss
    unsigned int maxMissProbes;      // max entries checked to miss
    unsigned int flushCount;         // cache flush tally
    unsigned int flushedEntries;     // sum cache entries flushed
    unsigned int maxFlushedEntries;  // max cache entries flushed
} CacheInstrumentation;

#define CACHE_INSTRUMENTATION(cache)  (CacheInstrumentation *) &cache->buckets[cache->mask + 1];
#endif

/* Cache filling and flushing instrumentation */

static int totalCacheFills = 0;

#ifdef OBJC_INSTRUMENTED
unsigned int LinearFlushCachesCount              = 0;
unsigned int LinearFlushCachesVisitedCount       = 0;
unsigned int MaxLinearFlushCachesVisitedCount    = 0;
unsigned int NonlinearFlushCachesCount           = 0;
unsigned int NonlinearFlushCachesClassCount      = 0;
unsigned int NonlinearFlushCachesVisitedCount    = 0;
unsigned int MaxNonlinearFlushCachesVisitedCount = 0;
unsigned int IdealFlushCachesCount               = 0;
unsigned int MaxIdealFlushCachesCount            = 0;
#endif


/***********************************************************************
* A static empty cache.  All classes initially point at this cache.
* When the first message is sent it misses in the cache, and when
* the cache is grown it checks for this case and uses malloc rather
* than realloc.  This avoids the need to check for NULL caches in the
* messenger.
***********************************************************************/

struct objc_cache _objc_empty_cache =
{
    0,        // mask
    0,        // occupied
    { NULL }  // buckets
};
#ifdef OBJC_INSTRUMENTED
CacheInstrumentation emptyCacheInstrumentation = {0};
#endif


/* Local prototypes */

static bool _cache_isEmpty(Cache cache);
static Cache _cache_malloc(uintptr_t slotCount);
static Cache _cache_create(Class cls);
static Cache _cache_expand(Class cls);

static int _collecting_in_critical(void);
static void _garbage_make_room(void);
static void _cache_collect_free(void *data, size_t size);

#if defined(CACHE_ALLOCATOR)
static bool cache_allocator_is_block(void *block);
static Cache cache_allocator_calloc(size_t size);
static void cache_allocator_free(void *block);
#endif

/***********************************************************************
* Cache statistics for OBJC_PRINT_CACHE_SETUP
**********************************************************************/
static unsigned int cache_counts[16];
static size_t cache_allocations;
static size_t cache_collections;
static size_t cache_allocator_regions;

static size_t log2u(size_t x)
{
    unsigned int log;

    log = 0;
    while (x >>= 1)
        log += 1;

    return log;
}


/***********************************************************************
* _cache_isEmpty.
* Returns YES if the given cache is some empty cache.
* Empty caches should never be allocated on the heap.
**********************************************************************/
static bool _cache_isEmpty(Cache cache)
{
    return (cache == NULL  ||  cache == (Cache)&_objc_empty_cache  ||  cache->mask == 0);
}


/***********************************************************************
* _cache_malloc.
*
* Called from _cache_create() and cache_expand()
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static Cache _cache_malloc(uintptr_t slotCount)
{
    Cache new_cache;
    size_t size;

    cacheUpdateLock.assertLocked();

    // Allocate table (why not check for failure?)
    size = sizeof(struct objc_cache) + TABLE_SIZE(slotCount);
#if defined(OBJC_INSTRUMENTED)
    // Custom cache allocator can't handle instrumentation.
    size += sizeof(CacheInstrumentation);
    new_cache = calloc(size, 1);
    new_cache->mask = slotCount - 1;
#elif !defined(CACHE_ALLOCATOR)
    // fixme cache allocator implementation isn't 64-bit clean
    new_cache = calloc(size, 1);
    new_cache->mask = (unsigned int)(slotCount - 1);
#else
    if (size < CACHE_ALLOCATOR_MIN) {
        new_cache = (Cache)calloc(size, 1);
        new_cache->mask = slotCount - 1;
        // occupied and buckets and instrumentation are all zero
    } else {
        new_cache = cache_allocator_calloc(size);
        // mask is already set
        // occupied and buckets and instrumentation are all zero
    }
#endif

    if (PrintCaches) {
        size_t bucket = log2u(slotCount);
        if (bucket < sizeof(cache_counts) / sizeof(cache_counts[0])) {
            cache_counts[bucket]++;
        }
        cache_allocations++;
    }

    return new_cache;
}

/***********************************************************************
* _cache_free_block.
*
* Called from _cache_free() and _cache_collect_free().
* block may be a cache or a forward:: entry.
* If block is a cache, forward:: entries it points to will NOT be freed.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static inline int isPowerOf2(unsigned long l) { return 1 == __builtin_popcountl(l); }
static void _cache_free_block(void *block)
{
    cacheUpdateLock.assertLocked();

#if !TARGET_OS_WIN32
    if (PrintCaches) {
        Cache cache = (Cache)block;
        size_t slotCount = cache->mask + 1;
        if (isPowerOf2(slotCount)) {
            size_t bucket = log2u(slotCount);
            if (bucket < sizeof(cache_counts) / sizeof(cache_counts[0])) {
                cache_counts[bucket]--;
            }
        }
    }
#endif

#if defined(CACHE_ALLOCATOR)
    if (cache_allocator_is_block(block)) {
        cache_allocator_free(block);
    } else 
#endif
    {
        free(block);
    }
}


/***********************************************************************
* _cache_free.
*
* Called from _objc_remove_classes_in_image().
* forward:: entries in the cache ARE freed.
* Cache locks: cacheUpdateLock must NOT be held by the caller.
**********************************************************************/
void _cache_free(Cache cache)
{
    unsigned int i;

    mutex_locker_t lock(cacheUpdateLock);

    for (i = 0; i < cache->mask + 1; i++) {
        cache_entry *entry = (cache_entry *)cache->buckets[i];
        if (entry  &&  entry->imp == _objc_msgForward_impcache) {
            _cache_free_block(entry);
        }
    }
    
    _cache_free_block(cache);
}


/***********************************************************************
* _cache_create.
*
* Called from _cache_expand().
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static Cache _cache_create(Class cls)
{
    Cache new_cache;

    cacheUpdateLock.assertLocked();

    // Allocate new cache block
    new_cache = _cache_malloc(INIT_CACHE_SIZE);

    // Install the cache
    cls->cache = new_cache;

    // Clear the grow flag so that we will re-use the current storage,
    // rather than actually grow the cache, when expanding the cache
    // for the first time
    if (_class_slow_grow) {
        cls->setShouldGrowCache(false);
    }

    // Return our creation
    return new_cache;
}


/***********************************************************************
* _cache_expand.
*
* Called from _cache_fill ()
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static Cache _cache_expand(Class cls)
{
    Cache old_cache;
    Cache new_cache;
    uintptr_t slotCount;
    uintptr_t index;

    cacheUpdateLock.assertLocked();

    // First growth goes from empty cache to a real one
    old_cache = cls->cache;
    if (_cache_isEmpty(old_cache))
        return _cache_create (cls);

    if (_class_slow_grow) {
        // Cache grows every other time only.
        if (cls->shouldGrowCache()) {
            // Grow the cache this time. Don't grow next time.
            cls->setShouldGrowCache(false);
        } 
        else {
            // Reuse the current cache storage this time. Do grow next time.
            cls->setShouldGrowCache(true);

            // Clear the valid-entry counter
            old_cache->occupied = 0;

            // Invalidate all the cache entries
            for (index = 0; index < old_cache->mask + 1; index += 1)
            {
                // Remember what this entry was, so we can possibly
                // deallocate it after the bucket has been invalidated
                cache_entry *oldEntry = (cache_entry *)old_cache->buckets[index];
                
                // Skip invalid entry
                if (!oldEntry)
                    continue;

                // Invalidate this entry
                old_cache->buckets[index] = NULL;

                // Deallocate "forward::" entry
                if (oldEntry->imp == _objc_msgForward_impcache) {
                    _cache_collect_free (oldEntry, sizeof(cache_entry));
                }
            }

            // Return the same old cache, freshly emptied
            return old_cache;
        }
    }

    // Double the cache size
    slotCount = (old_cache->mask + 1) << 1;

    new_cache = _cache_malloc(slotCount);

#ifdef OBJC_INSTRUMENTED
    // Propagate the instrumentation data
    {
        CacheInstrumentation *oldCacheData;
        CacheInstrumentation *newCacheData;

        oldCacheData = CACHE_INSTRUMENTATION(old_cache);
        newCacheData = CACHE_INSTRUMENTATION(new_cache);
        bcopy ((const char *)oldCacheData, (char *)newCacheData, sizeof(CacheInstrumentation));
    }
#endif

    // Deallocate "forward::" entries from the old cache
    for (index = 0; index < old_cache->mask + 1; index++) {
        cache_entry *entry = (cache_entry *)old_cache->buckets[index];
        if (entry && entry->imp == _objc_msgForward_impcache) {
            _cache_collect_free (entry, sizeof(cache_entry));
        }
    }

    // Install new cache
    cls->cache = new_cache;

    // Deallocate old cache, try freeing all the garbage
    _cache_collect_free (old_cache, old_cache->mask * sizeof(cache_entry *));
    _cache_collect(false);

    return new_cache;
}


/***********************************************************************
* _cache_fill.  Add the specified method to the specified class' cache.
* Returns NO if the cache entry wasn't added: cache was busy, 
*  class is still being initialized, new entry is a duplicate.
*
* Called only from _class_lookupMethodAndLoadCache and
* class_respondsToMethod and _cache_addForwardEntry.
*
* Cache locks: cacheUpdateLock must not be held.
**********************************************************************/
bool _cache_fill(Class cls, Method smt, SEL sel)
{
    uintptr_t newOccupied;
    uintptr_t index;
    cache_entry **buckets;
    cache_entry *entry;
    Cache cache;

    cacheUpdateLock.assertUnlocked();

    // Never cache before +initialize is done
    if (!cls->isInitialized()) {
        return NO;
    }

    // Keep tally of cache additions
    totalCacheFills += 1;

    mutex_locker_t lock(cacheUpdateLock);

    entry = (cache_entry *)smt;

    cache = cls->cache;

    // Make sure the entry wasn't added to the cache by some other thread 
    // before we grabbed the cacheUpdateLock.
    // Don't use _cache_getMethod() because _cache_getMethod() doesn't 
    // return forward:: entries.
    if (_cache_getImp(cls, sel)) {
        return NO; // entry is already cached, didn't add new one
    }

    // Use the cache as-is if it is less than 3/4 full
    newOccupied = cache->occupied + 1;
    if ((newOccupied * 4) <= (cache->mask + 1) * 3) {
        // Cache is less than 3/4 full.
        cache->occupied = (unsigned int)newOccupied;
    } else {
        // Cache is too full. Expand it.
        cache = _cache_expand (cls);

        // Account for the addition
        cache->occupied += 1;
    }

    // Scan for the first unused slot and insert there.
    // There is guaranteed to be an empty slot because the 
    // minimum size is 4 and we resized at 3/4 full.
    buckets = (cache_entry **)cache->buckets;
    for (index = CACHE_HASH(sel, cache->mask); 
         buckets[index] != NULL; 
         index = (index+1) & cache->mask)
    {
        // empty
    }
    buckets[index] = entry;

    return YES; // successfully added new cache entry
}


/***********************************************************************
* _cache_addForwardEntry
* Add a forward:: entry  for the given selector to cls's method cache.
* Does nothing if the cache addition fails for any reason.
* Called from class_respondsToMethod and _class_lookupMethodAndLoadCache.
* Cache locks: cacheUpdateLock must not be held.
**********************************************************************/
void _cache_addForwardEntry(Class cls, SEL sel)
{
    cache_entry *smt;
  
    smt = (cache_entry *)malloc(sizeof(cache_entry));
    smt->name = sel;
    smt->imp = _objc_msgForward_impcache;
    if (! _cache_fill(cls, (Method)smt, sel)) {  // fixme hack
        // Entry not added to cache. Don't leak the method struct.
        free(smt);
    }
}


/***********************************************************************
* _cache_addIgnoredEntry
* Add an entry for the ignored selector to cls's method cache.
* Does nothing if the cache addition fails for any reason.
* Returns the ignored IMP.
* Cache locks: cacheUpdateLock must not be held.
**********************************************************************/
#if SUPPORT_GC  &&  !SUPPORT_IGNORED_SELECTOR_CONSTANT
static cache_entry *alloc_ignored_entries(void)
{
    cache_entry *e = (cache_entry *)malloc(5 * sizeof(cache_entry));
    e[0] = (cache_entry){ @selector(retain),     0,(IMP)&_objc_ignored_method};
    e[1] = (cache_entry){ @selector(release),    0,(IMP)&_objc_ignored_method};
    e[2] = (cache_entry){ @selector(autorelease),0,(IMP)&_objc_ignored_method};
    e[3] = (cache_entry){ @selector(retainCount),0,(IMP)&_objc_ignored_method};
    e[4] = (cache_entry){ @selector(dealloc),    0,(IMP)&_objc_ignored_method};
    return e;
}
#endif

IMP _cache_addIgnoredEntry(Class cls, SEL sel)
{
    cache_entry *entryp = NULL;

#if !SUPPORT_GC
    _objc_fatal("selector ignored with GC off");
#elif SUPPORT_IGNORED_SELECTOR_CONSTANT
    static cache_entry entry = { (SEL)kIgnore, 0, (IMP)&_objc_ignored_method };
    entryp = &entry;
    assert(sel == (SEL)kIgnore);
#else
    // hack
    int i;
    static cache_entry *entries;
    INIT_ONCE_PTR(entries, alloc_ignored_entries(), free(v));

    assert(ignoreSelector(sel));
    for (i = 0; i < 5; i++) {
        if (sel == entries[i].name) { 
            entryp = &entries[i];
            break;
        }
    }
    if (!entryp) _objc_fatal("selector %s (%p) is not ignored", 
                             sel_getName(sel), sel);
#endif

    _cache_fill(cls, (Method)entryp, sel);
    return entryp->imp;
}


/***********************************************************************
* _cache_flush.  Invalidate all valid entries in the given class' cache.
*
* Called from flush_caches() and _cache_fill()
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
void _cache_flush(Class cls)
{
    Cache cache;
    unsigned int index;

    cacheUpdateLock.assertLocked();

    // Locate cache.  Ignore unused cache.
    cache = cls->cache;
    if (_cache_isEmpty(cache)) return;

#ifdef OBJC_INSTRUMENTED
    {
        CacheInstrumentation *cacheData;

        // Tally this flush
        cacheData = CACHE_INSTRUMENTATION(cache);
        cacheData->flushCount += 1;
        cacheData->flushedEntries += cache->occupied;
        if (cache->occupied > cacheData->maxFlushedEntries)
            cacheData->maxFlushedEntries = cache->occupied;
    }
#endif

    // Traverse the cache
    for (index = 0; index <= cache->mask; index += 1)
    {
        // Remember what this entry was, so we can possibly
        // deallocate it after the bucket has been invalidated
        cache_entry *oldEntry = (cache_entry *)cache->buckets[index];

        // Invalidate this entry
        cache->buckets[index] = NULL;

        // Deallocate "forward::" entry
        if (oldEntry && oldEntry->imp == _objc_msgForward_impcache)
            _cache_collect_free (oldEntry, sizeof(cache_entry));
    }

    // Clear the valid-entry counter
    cache->occupied = 0;
}


/***********************************************************************
* flush_cache.  Flushes the instance method cache for class cls only.
* Use flush_caches() if cls might have in-use subclasses.
**********************************************************************/
void flush_cache(Class cls)
{
    if (cls) {
        mutex_locker_t lock(cacheUpdateLock);
        _cache_flush(cls);
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

// UNIX03 compliance hack (4508809)
#if !__DARWIN_UNIX03
#define __srr0 srr0
#define __eip eip
#endif

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
    ret = task_threads (mach_task_self (), &threads, &number);
    if (ret != KERN_SUCCESS)
    {
        _objc_fatal("task_thread failed (result %d)\n", ret);
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
static size_t garbage_threshold = 1024;

// table of refs to free
static void **garbage_refs = 0;

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
        garbage_refs = (void**)
            malloc(INIT_GARBAGE_COUNT * sizeof(void *));
        garbage_max = INIT_GARBAGE_COUNT;
    }

    // Double the table if it is full
    else if (garbage_count == garbage_max)
    {
        garbage_refs = (void**)
            realloc(garbage_refs, garbage_max * 2 * sizeof(void *));
        garbage_max *= 2;
    }
}


/***********************************************************************
* _cache_collect_free.  Add the specified malloc'd memory to the list
* of them to free at some later point.
* size is used for the collection threshold. It does not have to be 
* precisely the block's size.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static void _cache_collect_free(void *data, size_t size)
{
    cacheUpdateLock.assertLocked();

    _garbage_make_room ();
    garbage_byte_size += size;
    garbage_refs[garbage_count++] = data;
}


/***********************************************************************
* _cache_collect.  Try to free accumulated dead caches.
* collectALot tries harder to free memory.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
void _cache_collect(bool collectALot)
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
        _objc_inform ("CACHES: COLLECTING %zu bytes (%zu regions, %zu allocations, %zu collections)", garbage_byte_size, cache_allocator_regions, cache_allocations, cache_collections);
    }
    
    // Dispose all refs now in the garbage
    while (garbage_count--) {
        _cache_free_block(garbage_refs[garbage_count]);
    }
    
    // Clear the garbage count and total size indicator
    garbage_count = 0;
    garbage_byte_size = 0;

    if (PrintCaches) {
        size_t i;
        size_t total = 0;
        size_t ideal_total = 0;
        size_t malloc_total = 0;
        size_t local_total = 0;

        for (i = 0; i < sizeof(cache_counts) / sizeof(cache_counts[0]); i++) {
            int count = cache_counts[i];
            int slots = 1 << i;
            size_t size = sizeof(struct objc_cache) + TABLE_SIZE(slots);
            size_t ideal = size;
#if TARGET_OS_WIN32
            size_t malloc = size;
#else
            size_t malloc = malloc_good_size(size);
#endif
            size_t local = size < CACHE_ALLOCATOR_MIN ? malloc : cache_allocator_size_for_mask(cache_allocator_mask_for_size(size));

            if (!count) continue;

            _objc_inform("CACHES: %4d slots: %4d caches, %6zu / %6zu / %6zu bytes ideal/malloc/local, %6zu / %6zu bytes wasted malloc/local", slots, count, ideal*count, malloc*count, local*count, malloc*count-ideal*count, local*count-ideal*count);

            total += count;
            ideal_total += ideal*count;
            malloc_total += malloc*count;
            local_total += local*count;
        }

        _objc_inform("CACHES:      total: %4zu caches, %6zu / %6zu / %6zu bytes ideal/malloc/local, %6zu / %6zu bytes wasted malloc/local", total, ideal_total, malloc_total, local_total, malloc_total-ideal_total, local_total-ideal_total);
    }
}





#if defined(CACHE_ALLOCATOR)

/***********************************************************************
* Custom method cache allocator.
* Method cache block sizes are 2^slots+2 words, which is a pessimal 
* case for the system allocator. It wastes 504 bytes per cache block 
* with 128 or more slots, which adds up to tens of KB for an AppKit process.
* To save memory, the custom cache allocator below is used.
* 
* The cache allocator uses 128 KB allocation regions. Few processes will 
* require a second region. Within a region, allocation is address-ordered 
* first fit.
* 
* The cache allocator uses a quantum of 520.
* Cache block ideal sizes: 520, 1032, 2056, 4104
* Cache allocator sizes:   520, 1040, 2080, 4160
*
* Because all blocks are known to be genuine method caches, the ordinary 
* cache->mask and cache->occupied fields are used as block headers. 
* No out-of-band headers are maintained. The number of blocks will 
* almost always be fewer than 200, so for simplicity there is no free 
* list or other optimization.
* 
* Block in use: mask != 0, occupied != -1 (mask indicates block size)
* Block free:   mask != 0, occupied == -1 (mask is precisely block size)
* 
* No cache allocator functions take any locks. Instead, the caller 
* must hold the cacheUpdateLock.
* 
* fixme with 128 KB regions and 520 B min block size, an allocation
* bitmap would be only 32 bytes - better than free list?
**********************************************************************/

typedef struct cache_allocator_block {
    uintptr_t size;
    uintptr_t state;
    struct cache_allocator_block *nextFree;
} cache_allocator_block;

typedef struct cache_allocator_region {
    cache_allocator_block *start;
    cache_allocator_block *end;    // first non-block address
    cache_allocator_block *freeList;
    struct cache_allocator_region *next;
} cache_allocator_region;

static cache_allocator_region *cacheRegion = NULL;


/***********************************************************************
* cache_allocator_add_region
* Allocates and returns a new region that can hold at least size 
*   bytes of large method caches. 
* The actual size will be rounded up to a CACHE_QUANTUM boundary, 
*   with a minimum of CACHE_REGION_SIZE. 
* The new region is lowest-priority for new allocations. Callers that 
*   know the other regions are already full should allocate directly 
*   into the returned region.
**********************************************************************/
static cache_allocator_region *cache_allocator_add_region(size_t size)
{
    vm_address_t addr;
    cache_allocator_block *b;
    cache_allocator_region **rgnP;
    cache_allocator_region *newRegion = (cache_allocator_region *)
        calloc(1, sizeof(cache_allocator_region));

    // Round size up to quantum boundary, and apply the minimum size.
    size += CACHE_QUANTUM - (size % CACHE_QUANTUM);
    if (size < CACHE_REGION_SIZE) size = CACHE_REGION_SIZE;

    // Allocate the region
    addr = (vm_address_t)calloc(size, 1);
    newRegion->start = (cache_allocator_block *)addr;
    newRegion->end = (cache_allocator_block *)(addr + size);

    // Mark the first block: free and covers the entire region
    b = newRegion->start;
    b->size = size;
    b->state = (uintptr_t)-1;
    b->nextFree = NULL;
    newRegion->freeList = b;

    // Add to end of the linked list of regions.
    // Other regions should be re-used before this one is touched.
    newRegion->next = NULL;
    rgnP = &cacheRegion;
    while (*rgnP) {
        rgnP = &(**rgnP).next;
    }
    *rgnP = newRegion;

    cache_allocator_regions++;

    return newRegion;
}


/***********************************************************************
* cache_allocator_coalesce
* Attempts to coalesce a free block with the single free block following 
* it in the free list, if any.
**********************************************************************/
static void cache_allocator_coalesce(cache_allocator_block *block)
{
    if (block->size + (uintptr_t)block == (uintptr_t)block->nextFree) {
        block->size += block->nextFree->size;
        block->nextFree = block->nextFree->nextFree;
    }
}


/***********************************************************************
* cache_region_calloc
* Attempt to allocate a size-byte block in the given region. 
* Allocation is first-fit. The free list is already fully coalesced.
* Returns NULL if there is not enough room in the region for the block.
**********************************************************************/
static void *cache_region_calloc(cache_allocator_region *rgn, size_t size)
{
    cache_allocator_block **blockP;
    uintptr_t mask;

    // Save mask for allocated block, then round size 
    // up to CACHE_QUANTUM boundary
    mask = cache_allocator_mask_for_size(size);
    size = cache_allocator_size_for_mask(mask);

    // Search the free list for a sufficiently large free block.

    for (blockP = &rgn->freeList; 
         *blockP != NULL; 
         blockP = &(**blockP).nextFree) 
    {
        cache_allocator_block *block = *blockP;
        if (block->size < size) continue;  // not big enough

        // block is now big enough. Allocate from it.

        // Slice off unneeded fragment of block, if any, 
        // and reconnect the free list around block.
        if (block->size - size >= CACHE_QUANTUM) {
            cache_allocator_block *leftover = 
                (cache_allocator_block *)(size + (uintptr_t)block);
            leftover->size = block->size - size;
            leftover->state = (uintptr_t)-1;
            leftover->nextFree = block->nextFree;
            *blockP = leftover;
        } else {
            *blockP = block->nextFree;
        }
            
        // block is now exactly the right size.

        bzero(block, size);
        block->size = mask;  // Cache->mask
        block->state = 0;    // Cache->occupied

        return block;
    }

    // No room in this region.
    return NULL;
}


/***********************************************************************
* cache_allocator_calloc
* Custom allocator for large method caches (128+ slots)
* The returned cache block already has cache->mask set. 
* cache->occupied and the cache contents are zero.
* Cache locks: cacheUpdateLock must be held by the caller
**********************************************************************/
static Cache cache_allocator_calloc(size_t size)
{
    cache_allocator_region *rgn;

    cacheUpdateLock.assertLocked();

    for (rgn = cacheRegion; rgn != NULL; rgn = rgn->next) {
        void *p = cache_region_calloc(rgn, size);
        if (p) {
            return (Cache)p;
        }
    }

    // No regions or all regions full - make a region and try one more time
    // In the unlikely case of a cache over 256KB, it will get its own region.
    return (Cache)cache_region_calloc(cache_allocator_add_region(size), size);
}


/***********************************************************************
* cache_allocator_region_for_block
* Returns the cache allocator region that ptr points into, or NULL.
**********************************************************************/
static cache_allocator_region *cache_allocator_region_for_block(cache_allocator_block *block) 
{
    cache_allocator_region *rgn;
    for (rgn = cacheRegion; rgn != NULL; rgn = rgn->next) {
        if (block >= rgn->start  &&  block < rgn->end) return rgn;
    }
    return NULL;
}


/***********************************************************************
* cache_allocator_is_block
* If ptr is a live block from the cache allocator, return YES
* If ptr is a block from some other allocator, return NO.
* If ptr is a dead block from the cache allocator, result is undefined.
* Cache locks: cacheUpdateLock must be held by the caller
**********************************************************************/
static bool cache_allocator_is_block(void *ptr)
{
    cacheUpdateLock.assertLocked();
    return (cache_allocator_region_for_block((cache_allocator_block *)ptr) != NULL);
}

/***********************************************************************
* cache_allocator_free
* Frees a block allocated by the cache allocator.
* Cache locks: cacheUpdateLock must be held by the caller.
**********************************************************************/
static void cache_allocator_free(void *ptr)
{
    cache_allocator_block *dead = (cache_allocator_block *)ptr;
    cache_allocator_block *cur;
    cache_allocator_region *rgn;

    cacheUpdateLock.assertLocked();

    if (! (rgn = cache_allocator_region_for_block(dead))) {
        // free of non-pointer
        _objc_inform("cache_allocator_free of non-pointer %p", dead);
        return;
    }    

    dead->size = cache_allocator_size_for_mask(dead->size);
    dead->state = (uintptr_t)-1;

    if (!rgn->freeList  ||  rgn->freeList > dead) {
        // dead block belongs at front of free list
        dead->nextFree = rgn->freeList;
        rgn->freeList = dead;
        cache_allocator_coalesce(dead);
        return;
    }

    // dead block belongs in the middle or end of free list
    for (cur = rgn->freeList; cur != NULL; cur = cur->nextFree) {
        cache_allocator_block *ahead = cur->nextFree;
        
        if (!ahead  ||  ahead > dead) {
            // cur and ahead straddle dead, OR dead belongs at end of free list
            cur->nextFree = dead;
            dead->nextFree = ahead;
            
            // coalesce into dead first in case both succeed
            cache_allocator_coalesce(dead);
            cache_allocator_coalesce(cur);
            return;
        }
    }

    // uh-oh
    _objc_inform("cache_allocator_free of non-pointer %p", ptr);
}

// defined(CACHE_ALLOCATOR)
#endif

/***********************************************************************
* Cache instrumentation and debugging
**********************************************************************/

#ifdef OBJC_INSTRUMENTED
enum {
    CACHE_HISTOGRAM_SIZE	= 512
};

unsigned int	CacheHitHistogram [CACHE_HISTOGRAM_SIZE];
unsigned int	CacheMissHistogram [CACHE_HISTOGRAM_SIZE];
#endif


/***********************************************************************
* _cache_print.
**********************************************************************/
static void _cache_print(Cache cache)
{
    uintptr_t index;
    uintptr_t count;

    count = cache->mask + 1;
    for (index = 0; index < count; index += 1) {
        cache_entry *entry = (cache_entry *)cache->buckets[index];
        if (entry) {
            if (entry->imp == _objc_msgForward_impcache)
                printf ("does not recognize: \n");
            printf ("%s\n", sel_getName(entry->name));
        }
    }
}


/***********************************************************************
* _class_printMethodCaches.
**********************************************************************/
void _class_printMethodCaches(Class cls)
{
    if (_cache_isEmpty(cls->cache)) {
        printf("no instance-method cache for class %s\n",cls->nameForLogging());
    } else {
        printf("instance-method cache for class %s:\n", cls->nameForLogging());
        _cache_print(cls->cache);
    }

    if (_cache_isEmpty(cls->ISA()->cache)) {
        printf("no class-method cache for class %s\n", cls->nameForLogging());
    } else {
        printf ("class-method cache for class %s:\n", cls->nameForLogging());
        _cache_print(cls->ISA()->cache);
    }
}


#if 0
#warning fixme


/***********************************************************************
* _class_printDuplicateCacheEntries.
**********************************************************************/
void _class_printDuplicateCacheEntries(bool detail)
{
    NXHashState state;
    Class cls;
    unsigned int duplicates;
    unsigned int index1;
    unsigned int index2;
    unsigned int mask;
    unsigned int count;
    unsigned int isMeta;
    Cache cache;


    printf ("Checking for duplicate cache entries \n");

    // Outermost loop - iterate over all classes
    state = NXInitHashState (class_hash);
    duplicates = 0;
    while (NXNextHashState (class_hash, &state, (void **) &cls))
    {
        // Control loop - do given class' cache, then its isa's cache
        for (isMeta = 0; isMeta <= 1; isMeta += 1)
        {
            // Select cache of interest and make sure it exists
            cache = (isMeta ? cls->ISA : cls)->cache;
            if (_cache_isEmpty(cache))
                continue;

            // Middle loop - check each entry in the given cache
            mask  = cache->mask;
            count = mask + 1;
            for (index1 = 0; index1 < count; index1 += 1)
            {
                // Skip invalid entry
                if (!cache->buckets[index1])
                    continue;

                // Inner loop - check that given entry matches no later entry
                for (index2 = index1 + 1; index2 < count; index2 += 1)
                {
                    // Skip invalid entry
                    if (!cache->buckets[index2])
                        continue;

                    // Check for duplication by method name comparison
                    if (strcmp ((char *) cache->buckets[index1]->name),
                                (char *) cache->buckets[index2]->name)) == 0)
                    {
                        if (detail)
                            printf ("%s %s\n", cls->nameForLogging(), sel_getName(cache->buckets[index1]->name));
                        duplicates += 1;
                        break;
                    }
                }
            }
        }
    }

    // Log the findings
    printf ("duplicates = %d\n", duplicates);
    printf ("total cache fills = %d\n", totalCacheFills);
}


/***********************************************************************
* PrintCacheHeader.
**********************************************************************/
static void PrintCacheHeader(void)
{
#ifdef OBJC_INSTRUMENTED
    printf ("Cache  Cache  Slots  Avg    Max   AvgS  MaxS  AvgS  MaxS  TotalD   AvgD  MaxD  TotalD   AvgD  MaxD  TotD  AvgD  MaxD\n");
    printf ("Size   Count  Used   Used   Used  Hit   Hit   Miss  Miss  Hits     Prbs  Prbs  Misses   Prbs  Prbs  Flsh  Flsh  Flsh\n");
    printf ("-----  -----  -----  -----  ----  ----  ----  ----  ----  -------  ----  ----  -------  ----  ----  ----  ----  ----\n");
#else
    printf ("Cache  Cache  Slots  Avg    Max   AvgS  MaxS  AvgS  MaxS\n");
    printf ("Size   Count  Used   Used   Used  Hit   Hit   Miss  Miss\n");
    printf ("-----  -----  -----  -----  ----  ----  ----  ----  ----\n");
#endif
}


/***********************************************************************
* PrintCacheInfo.
**********************************************************************/
static void PrintCacheInfo(unsigned int cacheSize,
                           unsigned int cacheCount,
                           unsigned int slotsUsed,
                           float avgUsed, unsigned int maxUsed,
                           float avgSHit, unsigned int maxSHit,
                           float avgSMiss, unsigned int maxSMiss
#ifdef OBJC_INSTRUMENTED
                           , unsigned int totDHits,
                           float avgDHit,
                           unsigned int maxDHit,
                           unsigned int totDMisses,
                           float avgDMiss,
                           unsigned int maxDMiss,
                           unsigned int totDFlsh,
                           float avgDFlsh,
                           unsigned int maxDFlsh
#endif
                           )
{
#ifdef OBJC_INSTRUMENTED
    printf ("%5u  %5u  %5u  %5.1f  %4u  %4.1f  %4u  %4.1f  %4u  %7u  %4.1f  %4u  %7u  %4.1f  %4u  %4u  %4.1f  %4u\n",
#else
            printf ("%5u  %5u  %5u  %5.1f  %4u  %4.1f  %4u  %4.1f  %4u\n",
#endif
                    cacheSize, cacheCount, slotsUsed, avgUsed, maxUsed, avgSHit, maxSHit, avgSMiss, maxSMiss
#ifdef OBJC_INSTRUMENTED
                    , totDHits, avgDHit, maxDHit, totDMisses, avgDMiss, maxDMiss, totDFlsh, avgDFlsh, maxDFlsh
#endif
                    );
            
}


#ifdef OBJC_INSTRUMENTED
/***********************************************************************
* PrintCacheHistogram.  Show the non-zero entries from the specified
* cache histogram.
**********************************************************************/
static void PrintCacheHistogram(char *title,
                                unsigned int *firstEntry,
                                unsigned int entryCount)
{
    unsigned int index;
    unsigned int *thisEntry;

    printf ("%s\n", title);
    printf ("    Probes    Tally\n");
    printf ("    ------    -----\n");
    for (index = 0, thisEntry = firstEntry;
         index < entryCount;
         index += 1, thisEntry += 1)
    {
        if (*thisEntry == 0)
            continue;

        printf ("    %6d    %5d\n", index, *thisEntry);
    }
}
#endif


/***********************************************************************
* _class_printMethodCacheStatistics.
**********************************************************************/

#define MAX_LOG2_SIZE   32
#define MAX_CHAIN_SIZE  100

void _class_printMethodCacheStatistics(void)
{
    unsigned int isMeta;
    unsigned int index;
    NXHashState state;
    Class cls;
    unsigned int totalChain;
    unsigned int totalMissChain;
    unsigned int maxChain;
    unsigned int maxMissChain;
    unsigned int classCount;
    unsigned int negativeEntryCount;
    unsigned int cacheExpandCount;
    unsigned int cacheCountBySize[2][MAX_LOG2_SIZE]        = {{0}};
    unsigned int totalEntriesBySize[2][MAX_LOG2_SIZE]      = {{0}};
    unsigned int maxEntriesBySize[2][MAX_LOG2_SIZE]        = {{0}};
    unsigned int totalChainBySize[2][MAX_LOG2_SIZE]        = {{0}};
    unsigned int totalMissChainBySize[2][MAX_LOG2_SIZE]    = {{0}};
    unsigned int totalMaxChainBySize[2][MAX_LOG2_SIZE]     = {{0}};
    unsigned int totalMaxMissChainBySize[2][MAX_LOG2_SIZE] = {{0}};
    unsigned int maxChainBySize[2][MAX_LOG2_SIZE]          = {{0}};
    unsigned int maxMissChainBySize[2][MAX_LOG2_SIZE]      = {{0}};
    unsigned int chainCount[MAX_CHAIN_SIZE]                = {0};
    unsigned int missChainCount[MAX_CHAIN_SIZE]            = {0};
#ifdef OBJC_INSTRUMENTED
    unsigned int hitCountBySize[2][MAX_LOG2_SIZE]          = {{0}};
    unsigned int hitProbesBySize[2][MAX_LOG2_SIZE]         = {{0}};
    unsigned int maxHitProbesBySize[2][MAX_LOG2_SIZE]      = {{0}};
    unsigned int missCountBySize[2][MAX_LOG2_SIZE]         = {{0}};
    unsigned int missProbesBySize[2][MAX_LOG2_SIZE]        = {{0}};
    unsigned int maxMissProbesBySize[2][MAX_LOG2_SIZE]     = {{0}};
    unsigned int flushCountBySize[2][MAX_LOG2_SIZE]        = {{0}};
    unsigned int flushedEntriesBySize[2][MAX_LOG2_SIZE]    = {{0}};
    unsigned int maxFlushedEntriesBySize[2][MAX_LOG2_SIZE] = {{0}};
#endif

    printf ("Printing cache statistics\n");

    // Outermost loop - iterate over all classes
    state = NXInitHashState (class_hash);
    classCount = 0;
    negativeEntryCount = 0;
    cacheExpandCount = 0;
    while (NXNextHashState (class_hash, &state, (void **) &cls))
    {
        // Tally classes
        classCount += 1;

        // Control loop - do given class' cache, then its isa's cache
        for (isMeta = 0; isMeta <= 1; isMeta += 1)
        {
            Cache cache;
            unsigned int mask;
            unsigned int log2Size;
            unsigned int entryCount;

            // Select cache of interest
            cache = (isMeta ? cls->ISA : cls)->cache;

            // Ignore empty cache... should we?
            if (_cache_isEmpty(cache))
                continue;

            // Middle loop - do each entry in the given cache
            mask = cache->mask;
            entryCount = 0;
            totalChain = 0;
            totalMissChain = 0;
            maxChain = 0;
            maxMissChain = 0;
            for (index = 0; index < mask + 1; index += 1)
            {
                cache_entry **buckets;
                cache_entry *entry;
                unsigned int hash;
                unsigned int methodChain;
                unsigned int methodMissChain;
                unsigned int index2;

                // If entry is invalid, the only item of
                // interest is that future insert hashes
                // to this entry can use it directly.
                buckets = (cache_entry **)cache->buckets;
                if (!buckets[index])
                {
                    missChainCount[0] += 1;
                    continue;
                }

                entry = buckets[index];

                // Tally valid entries
                entryCount += 1;

                // Tally "forward::" entries
                if (entry->imp == _objc_msgForward_impcache)
                    negativeEntryCount += 1;

                // Calculate search distance (chain length) for this method
                // The chain may wrap around to the beginning of the table.
                hash = CACHE_HASH(entry->name, mask);
                if (index >= hash) methodChain = index - hash;
                else methodChain = (mask+1) + index - hash;

                // Tally chains of this length
                if (methodChain < MAX_CHAIN_SIZE)
                    chainCount[methodChain] += 1;

                // Keep sum of all chain lengths
                totalChain += methodChain;

                // Record greatest chain length
                if (methodChain > maxChain)
                    maxChain = methodChain;

                // Calculate search distance for miss that hashes here
                index2 = index;
                while (buckets[index2])
                {
                    index2 += 1;
                    index2 &= mask;
                }
                methodMissChain = ((index2 - index) & mask);

                // Tally miss chains of this length
                if (methodMissChain < MAX_CHAIN_SIZE)
                    missChainCount[methodMissChain] += 1;

                // Keep sum of all miss chain lengths in this class
                totalMissChain += methodMissChain;

                // Record greatest miss chain length
                if (methodMissChain > maxMissChain)
                    maxMissChain = methodMissChain;
            }

            // Factor this cache into statistics about caches of the same
            // type and size (all caches are a power of two in size)
            log2Size = log2u (mask + 1);
            cacheCountBySize[isMeta][log2Size] += 1;
            totalEntriesBySize[isMeta][log2Size] += entryCount;
            if (entryCount > maxEntriesBySize[isMeta][log2Size])
                maxEntriesBySize[isMeta][log2Size] = entryCount;
            totalChainBySize[isMeta][log2Size] += totalChain;
            totalMissChainBySize[isMeta][log2Size] += totalMissChain;
            totalMaxChainBySize[isMeta][log2Size] += maxChain;
            totalMaxMissChainBySize[isMeta][log2Size] += maxMissChain;
            if (maxChain > maxChainBySize[isMeta][log2Size])
                maxChainBySize[isMeta][log2Size] = maxChain;
            if (maxMissChain > maxMissChainBySize[isMeta][log2Size])
                maxMissChainBySize[isMeta][log2Size] = maxMissChain;
#ifdef OBJC_INSTRUMENTED
            {
                CacheInstrumentation *cacheData;

                cacheData = CACHE_INSTRUMENTATION(cache);
                hitCountBySize[isMeta][log2Size] += cacheData->hitCount;
                hitProbesBySize[isMeta][log2Size] += cacheData->hitProbes;
                if (cacheData->maxHitProbes > maxHitProbesBySize[isMeta][log2Size])
                    maxHitProbesBySize[isMeta][log2Size] = cacheData->maxHitProbes;
                missCountBySize[isMeta][log2Size] += cacheData->missCount;
                missProbesBySize[isMeta][log2Size] += cacheData->missProbes;
                if (cacheData->maxMissProbes > maxMissProbesBySize[isMeta][log2Size])
                    maxMissProbesBySize[isMeta][log2Size] = cacheData->maxMissProbes;
                flushCountBySize[isMeta][log2Size] += cacheData->flushCount;
                flushedEntriesBySize[isMeta][log2Size] += cacheData->flushedEntries;
                if (cacheData->maxFlushedEntries > maxFlushedEntriesBySize[isMeta][log2Size])
                    maxFlushedEntriesBySize[isMeta][log2Size] = cacheData->maxFlushedEntries;
            }
#endif
            // Caches start with a power of two number of entries, and grow by doubling, so
            // we can calculate the number of times this cache has expanded
            cacheExpandCount += log2Size - INIT_CACHE_SIZE_LOG2;
        }
    }

    {
        unsigned int cacheCountByType[2] = {0};
        unsigned int totalCacheCount     = 0;
        unsigned int totalEntries        = 0;
        unsigned int maxEntries          = 0;
        unsigned int totalSlots          = 0;
#ifdef OBJC_INSTRUMENTED
        unsigned int totalHitCount       = 0;
        unsigned int totalHitProbes      = 0;
        unsigned int maxHitProbes        = 0;
        unsigned int totalMissCount      = 0;
        unsigned int totalMissProbes     = 0;
        unsigned int maxMissProbes       = 0;
        unsigned int totalFlushCount     = 0;
        unsigned int totalFlushedEntries = 0;
        unsigned int maxFlushedEntries   = 0;
#endif

        totalChain = 0;
        maxChain = 0;
        totalMissChain = 0;
        maxMissChain = 0;

        // Sum information over all caches
        for (isMeta = 0; isMeta <= 1; isMeta += 1)
        {
            for (index = 0; index < MAX_LOG2_SIZE; index += 1)
            {
                cacheCountByType[isMeta] += cacheCountBySize[isMeta][index];
                totalEntries += totalEntriesBySize[isMeta][index];
                totalSlots += cacheCountBySize[isMeta][index] * (1 << index);
                totalChain += totalChainBySize[isMeta][index];
                if (maxEntriesBySize[isMeta][index] > maxEntries)
                    maxEntries = maxEntriesBySize[isMeta][index];
                if (maxChainBySize[isMeta][index] > maxChain)
                    maxChain   = maxChainBySize[isMeta][index];
                totalMissChain += totalMissChainBySize[isMeta][index];
                if (maxMissChainBySize[isMeta][index] > maxMissChain)
                    maxMissChain = maxMissChainBySize[isMeta][index];
#ifdef OBJC_INSTRUMENTED
                totalHitCount += hitCountBySize[isMeta][index];
                totalHitProbes += hitProbesBySize[isMeta][index];
                if (maxHitProbesBySize[isMeta][index] > maxHitProbes)
                    maxHitProbes = maxHitProbesBySize[isMeta][index];
                totalMissCount += missCountBySize[isMeta][index];
                totalMissProbes += missProbesBySize[isMeta][index];
                if (maxMissProbesBySize[isMeta][index] > maxMissProbes)
                    maxMissProbes = maxMissProbesBySize[isMeta][index];
                totalFlushCount += flushCountBySize[isMeta][index];
                totalFlushedEntries += flushedEntriesBySize[isMeta][index];
                if (maxFlushedEntriesBySize[isMeta][index] > maxFlushedEntries)
                    maxFlushedEntries = maxFlushedEntriesBySize[isMeta][index];
#endif
            }

            totalCacheCount += cacheCountByType[isMeta];
        }

        // Log our findings
        printf ("There are %u classes\n", classCount);

        for (isMeta = 0; isMeta <= 1; isMeta += 1)
        {
            // Number of this type of class
            printf    ("\nThere are %u %s-method caches, broken down by size (slot count):\n",
                       cacheCountByType[isMeta],
                       isMeta ? "class" : "instance");

            // Print header
            PrintCacheHeader ();

            // Keep format consistent even if there are caches of this kind
            if (cacheCountByType[isMeta] == 0)
            {
                printf ("(none)\n");
                continue;
            }

            // Usage information by cache size
            for (index = 0; index < MAX_LOG2_SIZE; index += 1)
            {
                unsigned int cacheCount;
                unsigned int cacheSlotCount;
                unsigned int cacheEntryCount;

                // Get number of caches of this type and size
                cacheCount = cacheCountBySize[isMeta][index];
                if (cacheCount == 0)
                    continue;

                // Get the cache slot count and the total number of valid entries
                cacheSlotCount  = (1 << index);
                cacheEntryCount = totalEntriesBySize[isMeta][index];

                // Give the analysis
                PrintCacheInfo (cacheSlotCount,
                                cacheCount,
                                cacheEntryCount,
                                (float) cacheEntryCount / (float) cacheCount,
                                maxEntriesBySize[isMeta][index],
                                (float) totalChainBySize[isMeta][index] / (float) cacheEntryCount,
                                maxChainBySize[isMeta][index],
                                (float) totalMissChainBySize[isMeta][index] / (float) (cacheCount * cacheSlotCount),
                                maxMissChainBySize[isMeta][index]
#ifdef OBJC_INSTRUMENTED
                                , hitCountBySize[isMeta][index],
                                hitCountBySize[isMeta][index] ?
                                (float) hitProbesBySize[isMeta][index] / (float) hitCountBySize[isMeta][index] : 0.0,
                                maxHitProbesBySize[isMeta][index],
                                missCountBySize[isMeta][index],
                                missCountBySize[isMeta][index] ?
                                (float) missProbesBySize[isMeta][index] / (float) missCountBySize[isMeta][index] : 0.0,
                                maxMissProbesBySize[isMeta][index],
                                flushCountBySize[isMeta][index],
                                flushCountBySize[isMeta][index] ?
                                (float) flushedEntriesBySize[isMeta][index] / (float) flushCountBySize[isMeta][index] : 0.0,
                                maxFlushedEntriesBySize[isMeta][index]
#endif
                                );
            }
        }

        // Give overall numbers
        printf ("\nCumulative:\n");
        PrintCacheHeader ();
        PrintCacheInfo (totalSlots,
                        totalCacheCount,
                        totalEntries,
                        (float) totalEntries / (float) totalCacheCount,
                        maxEntries,
                        (float) totalChain / (float) totalEntries,
                        maxChain,
                        (float) totalMissChain / (float) totalSlots,
                        maxMissChain
#ifdef OBJC_INSTRUMENTED
                        , totalHitCount,
                        totalHitCount ?
                        (float) totalHitProbes / (float) totalHitCount : 0.0,
                        maxHitProbes,
                        totalMissCount,
                        totalMissCount ?
                        (float) totalMissProbes / (float) totalMissCount : 0.0,
                        maxMissProbes,
                        totalFlushCount,
                        totalFlushCount ?
                        (float) totalFlushedEntries / (float) totalFlushCount : 0.0,
                        maxFlushedEntries
#endif
                        );

        printf ("\nNumber of \"forward::\" entries: %d\n", negativeEntryCount);
        printf ("Number of cache expansions: %d\n", cacheExpandCount);
#ifdef OBJC_INSTRUMENTED
        printf ("flush_caches:   total calls  total visits  average visits  max visits  total classes  visits/class\n");
        printf ("                -----------  ------------  --------------  ----------  -------------  -------------\n");
        printf ("  linear        %11u  %12u  %14.1f  %10u  %13u  %12.2f\n",
                LinearFlushCachesCount,
                LinearFlushCachesVisitedCount,
                LinearFlushCachesCount ?
                (float) LinearFlushCachesVisitedCount / (float) LinearFlushCachesCount : 0.0,
                MaxLinearFlushCachesVisitedCount,
                LinearFlushCachesVisitedCount,
                1.0);
        printf ("  nonlinear     %11u  %12u  %14.1f  %10u  %13u  %12.2f\n",
                NonlinearFlushCachesCount,
                NonlinearFlushCachesVisitedCount,
                NonlinearFlushCachesCount ?
                (float) NonlinearFlushCachesVisitedCount / (float) NonlinearFlushCachesCount : 0.0,
                MaxNonlinearFlushCachesVisitedCount,
                NonlinearFlushCachesClassCount,
                NonlinearFlushCachesClassCount ?
                (float) NonlinearFlushCachesVisitedCount / (float) NonlinearFlushCachesClassCount : 0.0);
        printf ("  ideal         %11u  %12u  %14.1f  %10u  %13u  %12.2f\n",
                LinearFlushCachesCount + NonlinearFlushCachesCount,
                IdealFlushCachesCount,
                LinearFlushCachesCount + NonlinearFlushCachesCount ?
                (float) IdealFlushCachesCount / (float) (LinearFlushCachesCount + NonlinearFlushCachesCount) : 0.0,
                MaxIdealFlushCachesCount,
                LinearFlushCachesVisitedCount + NonlinearFlushCachesClassCount,
                LinearFlushCachesVisitedCount + NonlinearFlushCachesClassCount ?
                (float) IdealFlushCachesCount / (float) (LinearFlushCachesVisitedCount + NonlinearFlushCachesClassCount) : 0.0);

        PrintCacheHistogram ("\nCache hit histogram:",  &CacheHitHistogram[0],  CACHE_HISTOGRAM_SIZE);
        PrintCacheHistogram ("\nCache miss histogram:", &CacheMissHistogram[0], CACHE_HISTOGRAM_SIZE);
#endif

#if 0
        printf ("\nLookup chains:");
        for (index = 0; index < MAX_CHAIN_SIZE; index += 1)
        {
            if (chainCount[index] != 0)
                printf ("  %u:%u", index, chainCount[index]);
        }

        printf ("\nMiss chains:");
        for (index = 0; index < MAX_CHAIN_SIZE; index += 1)
        {
            if (missChainCount[index] != 0)
                printf ("  %u:%u", index, missChainCount[index]);
        }

        printf ("\nTotal memory usage for cache data structures: %lu bytes\n",
                totalCacheCount * (sizeof(struct objc_cache) - sizeof(cache_entry *)) +
                totalSlots * sizeof(cache_entry *) +
                negativeEntryCount * sizeof(cache_entry));
#endif
    }
}

#endif


// !__OBJC2__
#endif
