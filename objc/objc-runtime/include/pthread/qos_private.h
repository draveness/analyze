/*
 * Copyright (c) 2013-2014 Apple Inc. All rights reserved.
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

#ifndef _QOS_PRIVATE_H
#define _QOS_PRIVATE_H

#include <pthread/qos.h>
#include <sys/qos_private.h>

#if __DARWIN_C_LEVEL >= __DARWIN_C_FULL
// allow __DARWIN_C_LEVEL to turn off the use of mach_port_t
#include <mach/port.h>
#endif

// pthread_priority_t is an on opaque integer that is guaranteed to be ordered such that
// combations of QoS classes and relative priorities are ordered numerically, according to
// their combined priority.
typedef unsigned long pthread_priority_t;

// masks for splitting the handling the contents of a pthread_priority_t, the mapping from
// qos_class_t to the class bits, however, is intentionally not exposed.
#define _PTHREAD_PRIORITY_FLAGS_MASK		(~0xffffff)
#define _PTHREAD_PRIORITY_QOS_CLASS_MASK	0x00ffff00
#define _PTHREAD_PRIORITY_QOS_CLASS_SHIFT	(8ull)
#define _PTHREAD_PRIORITY_PRIORITY_MASK		0x000000ff
#define _PTHREAD_PRIORITY_PRIORITY_SHIFT	(0)

#define _PTHREAD_PRIORITY_OVERCOMMIT_FLAG	0x80000000
#define _PTHREAD_PRIORITY_INHERIT_FLAG		0x40000000
#define _PTHREAD_PRIORITY_ROOTQUEUE_FLAG	0x20000000
#define _PTHREAD_PRIORITY_ENFORCE_FLAG		0x10000000
#define _PTHREAD_PRIORITY_OVERRIDE_FLAG		0x08000000

// redeffed here to avoid leaving __QOS_ENUM defined in the public header
#define __QOS_ENUM(name, type, ...) enum { __VA_ARGS__ }; typedef type name##_t
#define __QOS_AVAILABLE_STARTING(x, y)

#if defined(__has_feature) && defined(__has_extension)
#if __has_feature(objc_fixed_enum) || __has_extension(cxx_strong_enums)
#undef __QOS_ENUM
#define __QOS_ENUM(name, type, ...) typedef enum : type { __VA_ARGS__ } name##_t
#endif
#if __has_feature(enumerator_attributes)
#undef __QOS_AVAILABLE_STARTING
#define __QOS_AVAILABLE_STARTING __OSX_AVAILABLE_STARTING
#endif
#endif

__QOS_ENUM(_pthread_set_flags, unsigned int,
   _PTHREAD_SET_SELF_QOS_FLAG
		   __QOS_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0) = 0x1,
   _PTHREAD_SET_SELF_VOUCHER_FLAG
		   __QOS_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0) = 0x2,
   _PTHREAD_SET_SELF_FIXEDPRIORITY_FLAG
		   __QOS_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0) = 0x4,
);

#undef __QOS_ENUM
#undef __QOS_AVAILABLE_STARTING

#ifndef KERNEL

__BEGIN_DECLS

/*!
 * @function pthread_set_qos_class_np
 *
 * @abstract
 * Sets the requested QOS class and relative priority of the current thread.
 *
 * @discussion
 * The QOS class and relative priority represent an overall combination of
 * system quality of service attributes on a thread.
 *
 * Subsequent calls to interfaces such as pthread_setschedparam() that are
 * incompatible or in conflict with the QOS class system will unset the QOS
 * class requested with this interface and pthread_get_qos_class_np() will
 * return QOS_CLASS_UNSPECIFIED thereafter. A thread so modified is permanently
 * opted-out of the QOS class system and calls to this function to request a QOS
 * class for such a thread will fail and return EPERM.
 *
 * @param __pthread
 * The current thread as returned by pthread_self().
 * EINVAL will be returned if any other thread is provided.
 *
 * @param __qos_class
 * A QOS class value:
 *	- QOS_CLASS_USER_INTERACTIVE
 *	- QOS_CLASS_USER_INITIATED
 *	- QOS_CLASS_DEFAULT
 *	- QOS_CLASS_UTILITY
 *	- QOS_CLASS_BACKGROUND
 *	- QOS_CLASS_MAINTENANCE
 * EINVAL will be returned if any other value is provided.
 *
 * @param __relative_priority
 * A relative priority within the QOS class. This value is a negative offset
 * from the maximum supported scheduler priority for the given class.
 * EINVAL will be returned if the value is greater than zero or less than
 * QOS_MIN_RELATIVE_PRIORITY.
 *
 * @return
 * Zero if successful, othwerise an errno value.
 */
__OSX_AVAILABLE_BUT_DEPRECATED_MSG(__MAC_10_10, __MAC_10_10, __IPHONE_8_0, __IPHONE_8_0, \
		"Use pthread_set_qos_class_self_np() instead")
int
pthread_set_qos_class_np(pthread_t __pthread,
						 qos_class_t __qos_class,
						 int __relative_priority);

/* Private interfaces for libdispatch to encode/decode specific values of pthread_priority_t. */

// Encode a class+priority pair into a pthread_priority_t,
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
pthread_priority_t
_pthread_qos_class_encode(qos_class_t qos_class, int relative_priority, unsigned long flags);

// Decode a pthread_priority_t into a class+priority pair.
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
qos_class_t
_pthread_qos_class_decode(pthread_priority_t priority, int *relative_priority, unsigned long *flags);

// Encode a legacy workqueue API priority into a pthread_priority_t
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
pthread_priority_t
_pthread_qos_class_encode_workqueue(int queue_priority, unsigned long flags);

#if __DARWIN_C_LEVEL >= __DARWIN_C_FULL
// Set QoS or voucher, or both, on pthread_self()
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
_pthread_set_properties_self(_pthread_set_flags_t flags, pthread_priority_t priority, mach_port_t voucher);

// Set self to fixed priority without disturbing QoS or priority
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_8_0)
int
pthread_set_fixedpriority_self(void);

#endif

__END_DECLS

#endif // KERNEL

#endif //_QOS_PRIVATE_H
