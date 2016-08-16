/*
 * Copyright (c) 2011 Apple Inc. All rights reserved.
 *
 * @APPLE_APACHE_LICENSE_HEADER_START@
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 * @APPLE_APACHE_LICENSE_HEADER_END@
 */
/*
    auto_zone.h
    Automatic Garbage Collection.
    Copyright (c) 2002-2011 Apple Inc. All rights reserved.
 */

#ifndef __AUTO_ZONE__
#define __AUTO_ZONE__

#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <malloc/malloc.h>
#include <Availability.h>
#include <AvailabilityMacros.h>
#include <TargetConditionals.h>

#include <dispatch/dispatch.h>

#define AUTO_EXPORT extern __attribute__((visibility("default")))

__BEGIN_DECLS

typedef malloc_zone_t auto_zone_t;
    // an auto zone carries a little more state but can be cast into a malloc_zone_t

AUTO_EXPORT auto_zone_t *auto_zone_create(const char *name)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // create an garbage collected zone.  Can be (theoretically) done more than once.
    // memory can be allocated by malloc_zone_malloc(result, size)
    // by default, this memory must be malloc_zone_free(result, ptr) as well (or generic free())

AUTO_EXPORT struct malloc_introspection_t auto_zone_introspection()
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // access the zone introspection functions independent of any particular auto zone instance.
    // this is used by tools to be able to introspect a zone in another process.
    // the introspection functions returned are required to do version checking on the zone.

#define AUTO_RETAINED_BLOCK_TYPE 0x100  /* zone enumerator returns only blocks with nonzero retain count */

/*********  External (Global) Use counting  ************/

AUTO_EXPORT void auto_zone_retain(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT unsigned int auto_zone_release(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT unsigned int auto_zone_retain_count(auto_zone_t *zone, const void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // All pointer in the auto zone have an explicit retain count
    // Objects will not be collected when the retain count is non-zero

/*********  Object information  ************/

AUTO_EXPORT const void *auto_zone_base_pointer(auto_zone_t *zone, const void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // return base of interior pointer  (or NULL).
AUTO_EXPORT boolean_t auto_zone_is_valid_pointer(auto_zone_t *zone, const void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // is this a pointer to the base of an allocated block?
AUTO_EXPORT size_t auto_zone_size(auto_zone_t *zone, const void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

/*********  Write-barrier   ************/

AUTO_EXPORT boolean_t auto_zone_set_write_barrier(auto_zone_t *zone, const void *dest, const void *new_value)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // must be used when an object field/slot in the auto zone is set to another object in the auto zone
    // returns true if the dest was a valid target whose write-barrier was set

AUTO_EXPORT boolean_t auto_zone_atomicCompareAndSwap(auto_zone_t *zone, void *existingValue, void *newValue, void *volatile *location, boolean_t isGlobal, boolean_t issueBarrier)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // Atomically update a location with a new GC value.  These use OSAtomicCompareAndSwapPtr{Barrier} with appropriate write-barrier interlocking logic.

AUTO_EXPORT boolean_t auto_zone_atomicCompareAndSwapPtr(auto_zone_t *zone, void *existingValue, void *newValue, void *volatile *location, boolean_t issueBarrier)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);
    // Atomically update a location with a new GC value.  These use OSAtomicCompareAndSwapPtr{Barrier} with appropriate write-barrier interlocking logic.
    // This version checks location, and if it points into global storage, registers a root.

AUTO_EXPORT void *auto_zone_write_barrier_memmove(auto_zone_t *zone, void *dst, const void *src, size_t size)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // copy content from an arbitrary source area to an arbitrary destination area
    // marking write barrier if necessary

/*********  Read-barrier   ************/

AUTO_EXPORT void *auto_zone_strong_read_barrier(auto_zone_t *zone, void **source)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

/*********  Statistics  ************/

typedef uint64_t auto_date_t;

typedef struct {
    auto_date_t     total_duration;
    auto_date_t     scan_duration;
    auto_date_t     enlivening_duration;
    auto_date_t     finalize_duration;
    auto_date_t     reclaim_duration;
} auto_collection_durations_t;

typedef struct {
    /* Memory usage */
    malloc_statistics_t malloc_statistics;
    /* GC stats */
    // version 0
    uint32_t            version;            // set to 1 before calling
    /* When there is an array, 0 stands for full collection, 1 for generational */
    size_t              num_collections[2];
    boolean_t           last_collection_was_generational;
    size_t              bytes_in_use_after_last_collection[2];
    size_t              bytes_allocated_after_last_collection[2];
    size_t              bytes_freed_during_last_collection[2];
    // durations
    auto_collection_durations_t total[2];   // running total of each field
    auto_collection_durations_t last[2];    // most recent result
    auto_collection_durations_t maximum[2]; // on a per item basis, the max.  Thus, total != scan + finalize ...
    // version 1 additions
    size_t              thread_collections_total;
    size_t              thread_blocks_recovered_total;
    size_t              thread_bytes_recovered_total;
} auto_statistics_t;

AUTO_EXPORT void auto_zone_statistics(auto_zone_t *zone, auto_statistics_t *stats)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_5_0,__IPHONE_5_0);
    // set version to 0

/*********  Garbage Collection   ************/

enum {
    AUTO_COLLECT_RATIO_COLLECTION        = (0 << 0), // run generational or full depending on applying AUTO_COLLECTION_RATIO
    AUTO_COLLECT_GENERATIONAL_COLLECTION = (1 << 0), // collect young objects. Internal only.
    AUTO_COLLECT_FULL_COLLECTION         = (2 << 0), // collect entire heap. Internal only.
    AUTO_COLLECT_EXHAUSTIVE_COLLECTION   = (3 << 0), // run full collections until object count stabilizes.
    AUTO_COLLECT_SYNCHRONOUS             = (1 << 2), // block caller until scanning is finished.
    AUTO_COLLECT_IF_NEEDED               = (1 << 3), // only collect if AUTO_COLLECTION_THRESHOLD exceeded.
};
typedef uint32_t auto_collection_mode_t;

enum {
    AUTO_LOG_COLLECTIONS = (1 << 1),        // log block statistics whenever a collection occurs
    AUTO_LOG_TIMINGS = (1 << 2),            // log timing data whenever a collection occurs
    AUTO_LOG_REGIONS = (1 << 4),            // log whenever a new region is allocated
    AUTO_LOG_UNUSUAL = (1 << 5),            // log unusual circumstances
    AUTO_LOG_WEAK = (1 << 6),               // log weak reference manipulation
    AUTO_LOG_ALL = (~0u),
    AUTO_LOG_NONE = 0
};
typedef uint32_t auto_log_mask_t;

enum {
    AUTO_HEAP_HOLES_SHRINKING       = 1,        // total size of holes is approaching zero
    AUTO_HEAP_HOLES_EXHAUSTED       = 2,        // all holes exhausted, will use hitherto unused memory in "subzone"
    AUTO_HEAP_SUBZONE_EXHAUSTED     = 3,        // will add subzone
    AUTO_HEAP_REGION_EXHAUSTED      = 4,        // no more subzones available, need to add region
    AUTO_HEAP_ARENA_EXHAUSTED       = 5,        // arena exhausted.  (64-bit only)
};
typedef uint32_t auto_heap_growth_info_t;

typedef struct auto_zone_cursor *auto_zone_cursor_t;
typedef void (*auto_zone_foreach_object_t) (auto_zone_cursor_t cursor, void (*op) (void *ptr, void *data), void* data);

typedef struct {
    uint32_t        version;                    // sizeof(auto_collection_control_t)
    void            (*batch_invalidate) (auto_zone_t *zone, auto_zone_foreach_object_t foreach, auto_zone_cursor_t cursor, size_t cursor_size);
        // After unreached objects are found, collector calls this routine with internal context.
        // Typically, one enters a try block to call back into the collector with a function pointer to be used to
        // invalidate each object.  This amortizes the cost of the try block as well as allows the collector to use
        // efficient contexts.
    void            (*resurrect) (auto_zone_t *zone, void *ptr);
        // Objects on the garbage list may be assigned into live objects in an attempted resurrection.  This is not allowed.
        // This function, if supplied, is called for these objects to turn them into zombies.  The zombies may well hold
        // pointers to other objects on the garbage list.  No attempt is made to preserved these objects beyond this collection.
    const unsigned char* (*layout_for_address)(auto_zone_t *zone, void *ptr);
        // The collector assumes that the first word of every "object" is a class pointer.
        // For each class pointer discovered this function is called to return a layout, or NULL
        // if the object should be scanned conservatively.
        // The layout format is nibble pairs {skipcount, scancount}  XXX
    const unsigned char* (*weak_layout_for_address)(auto_zone_t *zone, void *ptr);
        // called once for each allocation encountered for which we don't know the weak layout
        // the callee returns a weak layout for the allocation or NULL if the allocation has no weak references.
    char*           (*name_for_address) (auto_zone_t *zone, vm_address_t base, vm_address_t offset);
        // if supplied, is used during logging for errors such as resurrections
    auto_log_mask_t log;
        // set to auto_log_mask_t bits as desired
    boolean_t       disable_generational;
        // if true, ignores requests to do generational GC.
    boolean_t       malloc_stack_logging;
        // if true, logs allocations for malloc stack logging.  Automatically set if MallocStackLogging{NoCompact} is set
    void            (*scan_external_callout)(void *context, void (*scanner)(void *context, void *start, void *end)) DEPRECATED_ATTRIBUTE;
        // no longer used
        
    void            (*will_grow)(auto_zone_t *zone, auto_heap_growth_info_t) DEPRECATED_ATTRIBUTE;
        // no longer used
    
    size_t          collection_threshold;
        // if_needed threshold: collector will initiate a collection after this number of bytes is allocated.
    size_t          full_vs_gen_frequency;
        // after full_vs_gen_frequency generational collections, a full collection will occur, if the if_needed threshold exceeded
    const char*     (*name_for_object) (auto_zone_t *zone, void *object);
        // provides a type name for an AUTO_OBJECT
} auto_collection_control_t;

AUTO_EXPORT auto_collection_control_t *auto_collection_parameters(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // FIXME: API is to get the control struct and slam it
    // sets a parameter that decides when callback gets called

AUTO_EXPORT void auto_collector_disable(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT void auto_collector_reenable(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
    // these two functions turn off/on the collector
    // default is on
    // use with great care.

AUTO_EXPORT boolean_t auto_zone_is_enabled(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT boolean_t auto_zone_is_collecting(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

AUTO_EXPORT void auto_collect(auto_zone_t *zone, auto_collection_mode_t mode, void *collection_context) 
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_5_0,__IPHONE_5_0);
    // deprecated, use auto_zone_collect() instead

AUTO_EXPORT void auto_collect_multithreaded(auto_zone_t *zone)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_5_0,__IPHONE_5_0);
    // deprecated


// Options to auto_zone_collect().
enum {
    /* 
       Request a collection with no options. This produces an advisory collection request which 
       allows the collector to choose what collection is performed (or none) based on its internal 
       heuristics. This is generally the only option that should be used in production code. 
       All other options are intended primarily to support debugging and unit tests and may change 
       meaning without notice.
     */
    AUTO_ZONE_COLLECT_NO_OPTIONS = 0,
    
    // The low order nibble specifies a request for a global heap collection. 
    // Note that the ordinal value is significant. Higher numbered collection modes can override lower numbered.
    AUTO_ZONE_COLLECT_RATIO_COLLECTION          = 1, // requests either a generational or a full collection, based on memory use heuristics.
    AUTO_ZONE_COLLECT_GENERATIONAL_COLLECTION   = 2, // requests a generational heap collection.
    AUTO_ZONE_COLLECT_FULL_COLLECTION           = 3, // requests a full heap collection.
    AUTO_ZONE_COLLECT_EXHAUSTIVE_COLLECTION     = 4, // requests an exhaustive heap collection.
    
    AUTO_ZONE_COLLECT_GLOBAL_MODE_MAX           = AUTO_ZONE_COLLECT_EXHAUSTIVE_COLLECTION, // the highest numbered global mode
    AUTO_ZONE_COLLECT_GLOBAL_MODE_COUNT         = AUTO_ZONE_COLLECT_EXHAUSTIVE_COLLECTION+1, // the highest numbered global mode
    AUTO_ZONE_COLLECT_GLOBAL_COLLECTION_MODE_MASK       = 0xf,
    
    
    // These bits requests a local collections be performed on the calling thread. It is permitted to request both a local collection and a global collection, in which case both will be performed.
    
    AUTO_ZONE_COLLECT_LOCAL_COLLECTION           = (1<<8),  // perform a normal thread local collection
    
    AUTO_ZONE_COLLECT_COALESCE                   = (1<<15), // allows the request to be skipped if a collection is in progress
};

/*
   auto_zone_collect() is the entry point to request a collection.

   Normally AUTO_ZONE_COLLECT_NO_OPTIONS should be passed for options. This indicates the call is an advisory 
   collection request and the collector is free to perform any action it deems fit (including none). This is 
   the only option that should be used in shipping production code. The other options provide fine grained control of
   the collector intended for debugging and unit tests. Misuse of these options can degrade performance. 
 */
typedef intptr_t auto_zone_options_t;
AUTO_EXPORT void auto_zone_collect(auto_zone_t *zone, auto_zone_options_t options)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#ifdef __BLOCKS__
AUTO_EXPORT void auto_zone_collect_and_notify(auto_zone_t *zone, auto_zone_options_t options, dispatch_queue_t callback_queue, dispatch_block_t completion_callback)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

/*
    auto_zone_compact() is the entry point to request a stop-the-world compaction of the heap. This can only be called from binaries
    which are marked by the linker (see <rdar://problem/7421695>) as supporting compaction. Currently there are no options to control
    compaction, but you can pass a queue/block callback pair that will be invoked after compaction finishes.
 */

enum {
    AUTO_ZONE_COMPACT_NO_OPTIONS = 0,
    AUTO_ZONE_COMPACT_IF_IDLE = 1,          /* primes compaction to start after delay, if no dispatch threads intervene. */
    AUTO_ZONE_COMPACT_ANALYZE = 2,          /* runs a compaction analysis to file specified by environment variable. */
};

typedef uintptr_t auto_zone_compact_options_t;

#ifdef __BLOCKS__
AUTO_EXPORT void auto_zone_compact(auto_zone_t *zone, auto_zone_compact_options_t options, dispatch_queue_t callback_queue, dispatch_block_t completion_callback)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

/*
    Compaction is enabled by default. The client runtime should call auto_zone_disable_compaction() when it detects that code that
    is incompatible with compaction has been loaded. This is safe to call immediately after auto_zone_create().
 */
AUTO_EXPORT void auto_zone_disable_compaction(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

/*
   External resource tracking.
 
   The garbage collector tracks use of collectable memory. But it may be necessary to trigger garbage collections
   based on use of other resources not tracked by the garbage collector, such as file descriptors. The garbage
   collector provides this interface to register other resources tracking systems so the collector can query
   if collection is needed. The garbage collector will periodically call all registered should_collect() blocks
   and if any of them return true a collection cycle will execute. (However, the collector stops querying
   external resource trackers once it has determined that a collection is necessary. In many cases the collector
   will collect due to memory use without querying any external resource trackers at all.)
 
   Resource tracking implementations should take care to avoid running collections continuously based on high
   resource use when no resources are recovered. One strategy is to track resources allocated since the last 
   triggered collection instead of a total allocation count.
 */

/*
   Register should_collect() as an external resource tracker. The string passed in description is used
   as a descriptive name for the resource tracker. When an external resource tracker triggers a collection the
   description string appears in the log if AUTO_LOG_COLLECTIONS is enabled. The description string is copied.
 */
#ifdef __BLOCKS__
AUTO_EXPORT void auto_zone_register_resource_tracker(auto_zone_t *zone, const char *description, boolean_t (^should_collect)(void))
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

/*
   Unregister a should_collect() block that was previously registered with auto_zone_register_resource_tracker().
   The garbage collector will no longer query the resource tracker.
 */
AUTO_EXPORT void auto_zone_unregister_resource_tracker(auto_zone_t *zone, const char *description)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);


/*
   auto_zone_reap_all_local_blocks() will immediately finalize and reclaim all blocks which are thread local to the calling thread.
   No scanning or other liveness analysis will be performed. This function can be called as an optimization in the very specific
   case where it is known that the stack cannot be rooting any blocks, such as a pthread event loop. (Note that this cannot be called
   from a thread created by NSThread.)
 */
AUTO_EXPORT void auto_zone_reap_all_local_blocks(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Block Memory Type Flags
// =======================
// Blocks of memory allocated by auto_zone_allocate_object() are broadly classified as scanned/unscanned
// and object/non-object. When objects become garbage, they are finalized by calling the batch_invalidate() callback.
// For scanned objects, the collector uses the layout_for_address callback, to obtain a layout map that describes which
// pointer sized words should be scanned, and which should be ignored. Scanned objects may also contain weak references
// which are created via auto_assign_weak_reference(). The weak_layout_for_address callback is used to automatically
// unregister non-NULL weak references in weak_unregister_with_layout(). Finally, the pointers_only bit applies only for
// scanned memory and indicates that all otherwise unspecified fields are pointers, the most interesting consequence is that
// they can be relocated during compaction.
//
// These flags are represented by auto_memory_type_t. see the comments below for the legal flag combinations. Once allocated,
// SPI is provided to change the bits in only proscribed ways; to turn off "object" treatment; to turn off scanning;
// to turn on all-pointers.

enum {
    AUTO_TYPE_UNKNOWN =     -1,                                             // this is an error value
    // memory type bits.
    AUTO_UNSCANNED =        (1 << 0),
    AUTO_OBJECT =           (1 << 1),
    AUTO_POINTERS_ONLY =    (1 << 2),
    // allowed combinations of flags.
    AUTO_MEMORY_SCANNED = !AUTO_UNSCANNED,                                  // conservatively scanned memory
    AUTO_MEMORY_UNSCANNED = AUTO_UNSCANNED,                                 // unscanned memory (bits)
    AUTO_MEMORY_ALL_POINTERS = AUTO_POINTERS_ONLY,                          // scanned array of pointers
    AUTO_MEMORY_ALL_WEAK_POINTERS = (AUTO_UNSCANNED | AUTO_POINTERS_ONLY),  // unscanned, weak array of pointers
    AUTO_OBJECT_SCANNED = AUTO_OBJECT,                                      // object memory, exactly scanned with layout maps, conservatively scanned remainder, will be finalized
    AUTO_OBJECT_UNSCANNED = AUTO_OBJECT | AUTO_UNSCANNED,                   // unscanned object memory, will be finalized
    AUTO_OBJECT_ALL_POINTERS = AUTO_OBJECT | AUTO_POINTERS_ONLY             // object memory, exactly scanned with layout maps, all-pointers scanned remainder, will be finalized
};
typedef int32_t auto_memory_type_t;

AUTO_EXPORT auto_memory_type_t auto_zone_get_layout_type(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

AUTO_EXPORT void* auto_zone_allocate_object(auto_zone_t *zone, size_t size, auto_memory_type_t type, boolean_t initial_refcount_to_one, boolean_t clear)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

/* Batch allocator. Returns number of blocks allocated, which may be 0. */
/* All blocks have the given memory type and initial reference count, and all blocks are zeroed. */
AUTO_EXPORT unsigned auto_zone_batch_allocate(auto_zone_t *zone, size_t size, auto_memory_type_t type, boolean_t initial_refcount_to_one, boolean_t clear, void **results, unsigned num_requested)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Create copy of AUTO_MEMORY object preserving "scanned" attribute
// If not auto memory then create unscanned memory copy
AUTO_EXPORT void *auto_zone_create_copy(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);


AUTO_EXPORT void auto_zone_register_thread(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

AUTO_EXPORT void auto_zone_unregister_thread(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

AUTO_EXPORT void auto_zone_assert_thread_registered(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);

AUTO_EXPORT void auto_zone_register_datasegment(auto_zone_t *zone, void *address, size_t size)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_unregister_datasegment(auto_zone_t *zone, void *address, size_t size)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);


// Weak references

// The collector maintains a weak reference system.
// Essentially, locations in which references are stored are registered along with the reference itself.
// The location should not be within scanned GC memory.
// After a collection, before finalization, all registered locations are examined and any containing references to
// newly discovered garbage will be "zeroed" and the registration cancelled.
//
// Reading values from locations must be done through the weak read function because there is a race with such
// reads and the collector having just determined that that value read is in fact otherwise garbage.
//
// The address of a callback block may be supplied optionally.  If supplied, if the location is zeroed, the callback
// block is queued to be called later with the arguments supplied in the callback block.  The same callback block both
// can and should be used as an aggregation point.  A table of weak locations could supply each registration with the
// same pointer to a callback block that will call that table if items are zerod.  The callbacks are made before
// finalization.  Note that only thread-safe operations may be performed by this callback.
//
// It is important to cancel all registrations before deallocating the memory containing locations or callback blocks.
// Cancellation is done by calling the registration function with a NULL "reference" parameter for that location.

#if defined(AUTO_USE_NEW_WEAK_CALLBACK)
typedef struct new_auto_weak_callback_block auto_weak_callback_block_t;
#else
typedef struct old_auto_weak_callback_block auto_weak_callback_block_t;
#endif

struct new_auto_weak_callback_block {
    void    *isa;                                           // provides layout for exact scanning.
    auto_weak_callback_block_t *next;                       // must be set to zero before first use.
    void   (*callback_function)(void *__strong target);
    void    *__strong target;
};

struct old_auto_weak_callback_block {
    auto_weak_callback_block_t *next;                       // must be set to zero before first use.
    void (*callback_function)(void *arg1, void *arg2);
    void *arg1;
    void *arg2;
} DEPRECATED_ATTRIBUTE;

AUTO_EXPORT void auto_assign_weak_reference(auto_zone_t *zone, const void *value, const void **location, auto_weak_callback_block_t *block)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

// Read a weak-reference, informing the collector that it is now strongly referenced.
AUTO_EXPORT void* auto_read_weak_reference(auto_zone_t *zone, void **referrer)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

// Compaction notification

// Registers an observer that gets called whenever pointers are updated (by compaction) inside a block.
// This could be used to trigger rehashing a hash table. The implementation isn't particularly efficient.
#ifdef __BLOCKS__
AUTO_EXPORT void auto_zone_set_compaction_observer(auto_zone_t *zone, void *block, void (^observer) (void))
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

// Global references

AUTO_EXPORT void auto_zone_add_root(auto_zone_t *zone, void *address_of_root_ptr, void *value)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_remove_root(auto_zone_t *zone, void *address_of_root_ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);

AUTO_EXPORT void auto_zone_root_write_barrier(auto_zone_t *zone, void *address_of_possible_root_ptr, void *value)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);


// Associative references.

// This informs the collector that an object A wishes to associate one or more secondary objects with object A's lifetime.
// This can be used to implement GC-safe associations that will neither cause uncollectable cycles, nor suffer the limitations
// of weak references.

AUTO_EXPORT void auto_zone_set_associative_ref(auto_zone_t *zone, void *object, void *key, void *value)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT void *auto_zone_get_associative_ref(auto_zone_t *zone, void *object,  void *key)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_erase_associative_refs(auto_zone_t *zone, void *object)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);

AUTO_EXPORT size_t auto_zone_get_associative_hash(auto_zone_t *zone, void *object)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Enumerates all known object, value pairs associated with the key parameter. Calls the specified block while the
// assocations table locks are held, therefore adding/removing assocations will likely crash.
#ifdef __BLOCKS__
AUTO_EXPORT void auto_zone_enumerate_associative_refs(auto_zone_t *zone, void *key, boolean_t (^block) (void *object, void *value))
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

// Collection Checking

// Collection checking is a debugging tool by which developers can verify that blocks are collecting as expected.
// When collection checking is enabled the program can report memory blocks to the collector
// that are expected to collect soon using auto_zone_track_pointer().
// The program can detect which of these blocks were not collected by calling auto_zone_enumerate_uncollected().
// Pointers that survive more than a few collections can be investigated as leaks.
// While collection checking is enabled collector performance is degraded and memory use is increased.
// While most garbage objects are detected and collected in just one collection attempt, there are
// cases where several collections are required to reclaim a memory block even though it has no references.
// Note also that a conservative stack reference is never cleared by running more collections.

// Enable/disable collection checking. An "enabled" counter is maintained, so calls should be paried if desired.
// Disabling collection checking and causes all previously tracked blocks to be unregistered (no longer tracked).
AUTO_EXPORT boolean_t auto_zone_enable_collection_checking(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_disable_collection_checking(auto_zone_t *zone)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

// Inform the collector that the pointer is expected to collect soon. pointer will subsequently be reported by 
// auto_zone_enumerate_uncollected() until it is collected.
// Note that pointer is still rooted on the stack in the scope where auto_zone_block_should_collect() is called.
AUTO_EXPORT void auto_zone_track_pointer(auto_zone_t *zone, void *pointer)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

#ifdef __BLOCKS__
typedef struct {
    boolean_t is_object;
    size_t survived_count;
} auto_zone_collection_checking_info;

// Typedef for a handler block used to report uncollected memory. The collector provides: 
// pointer - the memory block in question, which was previously passed to auto_zone_track_pointer()
// info - a pointer to a auto_zone_collection_checking_info struct containing:
//    is_object - true if the block was allocated as an object, false if it is not an object
//    survived_count - a minimum count of collections the block has survived (the actual count may be higher)
typedef void (^auto_zone_collection_checking_callback_t)(void *pointer, auto_zone_collection_checking_info *info);

// Enumerate the memory blocks that were previously passed to auto_zone_track_pointer(). 
// Any which have not been collected are reported using the callback.
// The callback may be NULL, in which case the uncollected blocks are simply logged.
AUTO_EXPORT void auto_zone_enumerate_uncollected(auto_zone_t *zone, auto_zone_collection_checking_callback_t callback)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif



/***** SPI ******/
    
AUTO_EXPORT boolean_t auto_zone_is_finalized(auto_zone_t *zone, const void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_set_nofinalize(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_set_unscanned(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_set_scan_exactly(auto_zone_t *zone, void *ptr)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_clear_stack(auto_zone_t *zone, unsigned long options)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);

// Reference count logging support for ObjectAlloc et. al.

enum {
    AUTO_RETAIN_EVENT = 14,
    AUTO_RELEASE_EVENT = 15
};
AUTO_EXPORT void (*__auto_reference_logger)(uint32_t eventtype, void *ptr, uintptr_t data)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);


// Reference tracing

// referrer_base[referrer_offset]  ->  referent
typedef struct 
{
    vm_address_t referent;
    vm_address_t referrer_base;
    intptr_t     referrer_offset;
} auto_reference_t;

typedef void (*auto_reference_recorder_t)(auto_zone_t *zone, void *ctx, 
                                          auto_reference_t reference);

AUTO_EXPORT void auto_enumerate_references(auto_zone_t *zone, void *referent, 
                                      auto_reference_recorder_t callback, 
                                      void *stack_bottom, void *ctx)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);


AUTO_EXPORT void **auto_weak_find_first_referrer(auto_zone_t *zone, void **location, unsigned long count)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_5_0);


/************ DEPRECATED ***********/
    
AUTO_EXPORT auto_zone_t *auto_zone(void) 
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_5_0,__IPHONE_5_0);
    // returns a pointer to the first garbage collected zone created.


/************ DELETED ***********/

AUTO_EXPORT void auto_zone_stats(void)
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT void auto_zone_start_monitor(boolean_t force)
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT void auto_zone_set_class_list(int (*get_class_list)(void **buffer, int count))
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT void auto_zone_write_stats(FILE *f)
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT char *auto_zone_stats_string()
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT double auto_zone_utilization(auto_zone_t *zone) 
    UNAVAILABLE_ATTRIBUTE;
AUTO_EXPORT unsigned auto_zone_touched_size(auto_zone_t *zone) 
    UNAVAILABLE_ATTRIBUTE;
    

/************* EXPERIMENTAL *********/
#ifdef __BLOCKS__

typedef void (^auto_zone_stack_dump)(const void *base, unsigned long byte_size);
typedef void (^auto_zone_register_dump)(const void *base, unsigned long byte_size);
typedef void (^auto_zone_node_dump)(const void *address, unsigned long size, unsigned int layout, unsigned long refcount);
typedef void (^auto_zone_root_dump)(const void **address);
typedef void (^auto_zone_weak_dump)(const void **address, const void *item);

// Instruments.app utility; causes significant disruption.
// This is SPI for Apple's use only.  Can and likely will change without regard to 3rd party use.
AUTO_EXPORT void auto_zone_dump(auto_zone_t *zone,
            auto_zone_stack_dump stack_dump,
            auto_zone_register_dump register_dump,
            auto_zone_node_dump thread_local_node_dump, // unsupported
            auto_zone_root_dump root_dump,
            auto_zone_node_dump global_node_dump,
            auto_zone_weak_dump weak_dump)
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_5,__MAC_10_7, __IPHONE_5_0,__IPHONE_5_0);

// auto_zone_dump() is now deprecated, use auto_zone_visit() instead.

typedef struct {
    void *begin;
    void *end;
} auto_address_range_t;

typedef struct {
    uint32_t version;                    // sizeof(auto_zone_visitor_t)
    void (^visit_thread)(pthread_t thread, auto_address_range_t stack_range, auto_address_range_t registers);
    void (^visit_node)(const void *address, size_t size, auto_memory_type_t type, uint32_t refcount, boolean_t is_thread_local);
    void (^visit_root)(const void **address);
    void (^visit_weak)(const void *value, void *const*location, auto_weak_callback_block_t *callback);
    void (^visit_association)(const void *object, const void *key, const void *value);
} auto_zone_visitor_t;

AUTO_EXPORT void auto_zone_visit(auto_zone_t *zone, auto_zone_visitor_t *visitor)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

enum {
    auto_is_not_auto  =    0,
    auto_is_auto      =    (1 << 1),   // always on for a start of a node
    auto_is_local     =    (1 << 2),   // is/was node local
};

typedef int auto_probe_results_t;

// Instruments.app utility; causes significant disruption.
// This is SPI for Apple's use only.  Can and likely will change without regard to 3rd party use.
AUTO_EXPORT auto_probe_results_t auto_zone_probe_unlocked(auto_zone_t *zone, void *address)
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);
AUTO_EXPORT void auto_zone_scan_exact(auto_zone_t *zone, void *address, void (^callback)(void *base, unsigned long byte_offset, void *candidate))
     __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_5_0);

#endif

__END_DECLS

#endif /* __AUTO_ZONE__ */
