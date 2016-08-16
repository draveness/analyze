/*
 * Copyright (c) 2007, 2012 Apple Inc. All rights reserved.
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

#ifndef __PTHREAD_WORKQUEUE_H__
#define __PTHREAD_WORKQUEUE_H__

#include <sys/cdefs.h>
#include <Availability.h>
#include <pthread/pthread.h>
#include <pthread/qos.h>
#ifndef _PTHREAD_BUILDING_PTHREAD_
#include <pthread/qos_private.h>
#endif

#define PTHREAD_WORKQUEUE_SPI_VERSION 20140730

/* Feature checking flags, returned by _pthread_workqueue_supported()
 *
 * Note: These bits should match the definition of PTHREAD_FEATURE_*
 * bits defined in libpthread/kern/kern_internal.h */

#define WORKQ_FEATURE_DISPATCHFUNC	0x01	// pthread_workqueue_setdispatch_np is supported (or not)
#define WORKQ_FEATURE_FINEPRIO		0x02	// fine grained pthread workq priorities
#define WORKQ_FEATURE_MAINTENANCE	0x10	// QOS class maintenance

/* Legacy dispatch priority bands */

#define WORKQ_NUM_PRIOQUEUE	4

#define WORKQ_HIGH_PRIOQUEUE	0	// high priority queue
#define WORKQ_DEFAULT_PRIOQUEUE	1	// default priority queue
#define WORKQ_LOW_PRIOQUEUE	2	// low priority queue
#define WORKQ_BG_PRIOQUEUE	3	// background priority queue
#define WORKQ_NON_INTERACTIVE_PRIOQUEUE 128 // libdispatch SPI level

/* Legacy dispatch workqueue function flags */
#define WORKQ_ADDTHREADS_OPTION_OVERCOMMIT 0x00000001

__BEGIN_DECLS

// Legacy callback prototype, used with pthread_workqueue_setdispatch_np
typedef void (*pthread_workqueue_function_t)(int queue_priority, int options, void *ctxt);
// New callback prototype, used with pthread_workqueue_init
typedef void (*pthread_workqueue_function2_t)(pthread_priority_t priority);

// Initialises the pthread workqueue subsystem, passing the new-style callback prototype,
// the dispatchoffset and an unused flags field.
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_workqueue_init(pthread_workqueue_function2_t func, int offset, int flags);

// Non-zero enables kill on current thread, zero disables it.
__OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_2)
int
__pthread_workqueue_setkill(int);

// Dispatch function to be called when new worker threads are created.
__OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
int
pthread_workqueue_setdispatch_np(pthread_workqueue_function_t worker_func);

// Dispatch offset to be set in the kernel.
__OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0)
void
pthread_workqueue_setdispatchoffset_np(int offset);

// Request additional worker threads.
__OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
int
pthread_workqueue_addthreads_np(int queue_priority, int options, int numthreads);

// Retrieve the supported pthread feature set
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_workqueue_supported(void);

// Request worker threads (fine grained priority)
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_workqueue_addthreads(int numthreads, pthread_priority_t priority);

// Apply a QoS override without allocating userspace memory
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_override_qos_class_start_direct(mach_port_t thread, pthread_priority_t priority);

// Drop a corresponding QoS override made above.
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_override_qos_class_end_direct(mach_port_t thread);

// Apply a QoS override on a given workqueue thread.
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_workqueue_override_start_direct(mach_port_t thread, pthread_priority_t priority);

// Drop all QoS overrides on the current workqueue thread.
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_workqueue_override_reset(void);

// Apply a QoS override on a given thread (can be non-workqueue as well) with a resource/queue token
__OSX_AVAILABLE_STARTING(__MAC_10_10_2, __IPHONE_NA)
int
_pthread_workqueue_asynchronous_override_add(mach_port_t thread, pthread_priority_t priority, void *resource);

// Reset overrides for the given resource for the current thread
__OSX_AVAILABLE_STARTING(__MAC_10_10_2, __IPHONE_NA)
int
_pthread_workqueue_asynchronous_override_reset_self(void *resource);

// Reset overrides for all resources for the current thread
__OSX_AVAILABLE_STARTING(__MAC_10_10_2, __IPHONE_NA)
int
_pthread_workqueue_asynchronous_override_reset_all_self(void);

__END_DECLS

#endif // __PTHREAD_WORKQUEUE_H__
