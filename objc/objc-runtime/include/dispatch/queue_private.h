/*
 * Copyright (c) 2008-2010 Apple Inc. All rights reserved.
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
 * IMPORTANT: This header file describes INTERNAL interfaces to libdispatch
 * which are subject to change in future releases of Mac OS X. Any applications
 * relying on these interfaces WILL break.
 */

#ifndef __DISPATCH_QUEUE_PRIVATE__
#define __DISPATCH_QUEUE_PRIVATE__

#ifndef __DISPATCH_INDIRECT__
#error "Please #include <dispatch/dispatch.h> instead of this file directly."
#include <dispatch/base.h> // for HeaderDoc
#endif

__BEGIN_DECLS


/*!
 * @enum dispatch_queue_flags_t
 *
 * @constant DISPATCH_QUEUE_OVERCOMMIT
 * The queue will create a new thread for invoking blocks, regardless of how
 * busy the computer is.
 */
enum {
	DISPATCH_QUEUE_OVERCOMMIT = 0x2ull,
};

#define DISPATCH_QUEUE_FLAGS_MASK (DISPATCH_QUEUE_OVERCOMMIT)

/*!
 * @function dispatch_queue_set_width
 *
 * @abstract
 * Set the width of concurrency for a given queue. The width of a serial queue
 * is one.
 *
 * @discussion
 * This SPI is DEPRECATED and will be removed in a future release.
 * Uses of this SPI to make a queue concurrent by setting its width to LONG_MAX
 * should be replaced by passing DISPATCH_QUEUE_CONCURRENT to
 * dispatch_queue_create().
 * Uses of this SPI to limit queue concurrency are not recommended and should
 * be replaced by alternative mechanisms such as a dispatch semaphore created
 * with the desired concurrency width.
 *
 * @param queue
 * The queue to adjust. Passing the main queue or a global concurrent queue
 * will be ignored.
 *
 * @param width
 * The new maximum width of concurrency depending on available resources.
 * If zero is passed, then the value is promoted to one.
 * Negative values are magic values that map to automatic width values.
 * Unknown negative values default to DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS.
 */
#define DISPATCH_QUEUE_WIDTH_ACTIVE_CPUS		-1
#define DISPATCH_QUEUE_WIDTH_MAX_PHYSICAL_CPUS	-2
#define DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS	-3

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void
dispatch_queue_set_width(dispatch_queue_t dq, long width); // DEPRECATED

/*!
 * @function dispatch_set_current_target_queue
 *
 * @abstract
 * Synchronously sets the target queue of the current serial queue.
 *
 * @discussion
 * This SPI is provided for a limited purpose case when calling
 * dispatch_set_target_queue() is not sufficient. It works similarly to
 * dispatch_set_target_queue() except the target queue of the current queue
 * is immediately changed so that pending blocks on the queue will run on the
 * new target queue. Calling this from outside of a block executing on a serial
 * queue is undefined.
 *
 * @param queue
 * The new target queue for the object. The queue is retained, and the
 * previous target queue, if any, is released.
 * If queue is DISPATCH_TARGET_QUEUE_DEFAULT, set the object's target queue
 * to the default target queue for the given object type.
 */

__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_5_0)
DISPATCH_EXPORT DISPATCH_NOTHROW
void
dispatch_set_current_target_queue(dispatch_queue_t queue);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT const struct dispatch_queue_offsets_s {
	// always add new fields at the end
	const uint16_t dqo_version;
	const uint16_t dqo_label;
	const uint16_t dqo_label_size;
	const uint16_t dqo_flags;
	const uint16_t dqo_flags_size;
	const uint16_t dqo_serialnum;
	const uint16_t dqo_serialnum_size;
	const uint16_t dqo_width;
	const uint16_t dqo_width_size;
	const uint16_t dqo_running;
	const uint16_t dqo_running_size;
} dispatch_queue_offsets;


__END_DECLS

#endif
