/*
 * Copyright (c) 2008-2011 Apple Inc. All rights reserved.
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

#ifndef __DISPATCH_PRIVATE__
#define __DISPATCH_PRIVATE__

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_MAC
#include <mach/boolean.h>
#include <mach/mach.h>
#include <mach/message.h>
#endif
#if HAVE_UNISTD_H
#include <unistd.h>
#endif
#if HAVE_SYS_CDEFS_H
#include <sys/cdefs.h>
#endif
#include <pthread.h>

#define DISPATCH_NO_LEGACY 1
#ifdef DISPATCH_LEGACY // <rdar://problem/7366725>
#error "Dispatch legacy API unavailable."
#endif

#ifndef __DISPATCH_BUILDING_DISPATCH__
#include_next <dispatch/dispatch.h>

// Workaround <rdar://problem/6597365/>
#ifndef __DISPATCH_PUBLIC__
#include "/usr/include/dispatch/dispatch.h"
#endif

#ifndef __DISPATCH_INDIRECT__
#define __DISPATCH_INDIRECT__
#endif

#include <dispatch/benchmark.h>
#include <dispatch/queue_private.h>
#include <dispatch/source_private.h>

#undef __DISPATCH_INDIRECT__

#endif /* !__DISPATCH_BUILDING_DISPATCH__ */

/* LEGACY: Use DISPATCH_API_VERSION */
#define LIBDISPATCH_VERSION DISPATCH_API_VERSION

__BEGIN_DECLS

DISPATCH_EXPORT DISPATCH_NOTHROW
void
libdispatch_init(void);

#if TARGET_OS_MAC
#define DISPATCH_COCOA_COMPAT 1
#if DISPATCH_COCOA_COMPAT

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_CONST DISPATCH_WARN_RESULT DISPATCH_NOTHROW
mach_port_t
_dispatch_get_main_queue_port_4CF(void);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NOTHROW
void
_dispatch_main_queue_callback_4CF(mach_msg_header_t *msg);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT
void (*dispatch_begin_thread_4GC)(void);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT
void (*dispatch_end_thread_4GC)(void);

__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT
void (*dispatch_no_worker_threads_4GC)(void);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT
void *(*_dispatch_begin_NSAutoReleasePool)(void);

__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT
void (*_dispatch_end_NSAutoReleasePool)(void *);

#define _dispatch_time_after_nsec(t) \
		dispatch_time(DISPATCH_TIME_NOW, (t))
#define _dispatch_time_after_usec(t) \
		dispatch_time(DISPATCH_TIME_NOW, (t) * NSEC_PER_USEC)
#define _dispatch_time_after_msec(t) \
		dispatch_time(DISPATCH_TIME_NOW, (t) * NSEC_PER_MSEC)
#define _dispatch_time_after_sec(t) \
		dispatch_time(DISPATCH_TIME_NOW, (t) * NSEC_PER_SEC)

#endif
#endif /* TARGET_OS_MAC */

/* pthreads magic */

DISPATCH_EXPORT DISPATCH_NOTHROW void dispatch_atfork_prepare(void);
DISPATCH_EXPORT DISPATCH_NOTHROW void dispatch_atfork_parent(void);
DISPATCH_EXPORT DISPATCH_NOTHROW void dispatch_atfork_child(void);

#if TARGET_OS_MAC
/*
 * Extract the context pointer from a mach message trailer.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_PURE DISPATCH_WARN_RESULT DISPATCH_NONNULL_ALL
DISPATCH_NOTHROW
void *
dispatch_mach_msg_get_context(mach_msg_header_t *msg);
#endif /* TARGET_OS_MAC */

__END_DECLS

#endif
