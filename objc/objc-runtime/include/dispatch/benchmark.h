/*
 * Copyright (c) 2008-2009 Apple Inc. All rights reserved.
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

#ifndef __DISPATCH_BENCHMARK__
#define __DISPATCH_BENCHMARK__

#ifndef __DISPATCH_INDIRECT__
#error "Please #include <dispatch/dispatch.h> instead of this file directly."
#include <dispatch/base.h> // for HeaderDoc
#endif

__BEGIN_DECLS

/*!
 * @function dispatch_benchmark
 *
 * @abstract
 * Count the average number of cycles a given block takes to execute.
 *
 * @param count
 * The number of times to serially execute the given block.
 *
 * @param block
 * The block to execute.
 *
 * @result
 * The approximate number of cycles the block takes to execute.
 *
 * @discussion
 * This function is for debugging and performance analysis work. For the best
 * results, pass a high count value to dispatch_benchmark(). When benchmarking
 * concurrent code, please compare the serial version of the code against the
 * concurrent version, and compare the concurrent version on different classes
 * of hardware. Please look for inflection points with various data sets and
 * keep the following facts in mind:
 *
 * 1) Code bound by computational bandwidth may be inferred by proportional
 *    changes in performance as concurrency is increased.
 * 2) Code bound by memory bandwidth may be inferred by negligible changes in
 *    performance as concurrency is increased.
 * 3) Code bound by critical sections may be inferred by retrograde changes in
 *    performance as concurrency is increased.
 * 3a) Intentional: locks, mutexes, and condition variables.
 * 3b) Accidental: unrelated and frequently modified data on the same
 *     cache-line.
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL2 DISPATCH_NOTHROW
uint64_t
dispatch_benchmark(size_t count, void (^block)(void));
#endif

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL3 DISPATCH_NOTHROW
uint64_t
dispatch_benchmark_f(size_t count, void *ctxt, void (*func)(void *));

__END_DECLS

#endif
