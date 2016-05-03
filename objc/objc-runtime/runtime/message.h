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

#ifndef _OBJC_MESSAGE_H
#define _OBJC_MESSAGE_H

#pragma GCC system_header

#include <objc/objc.h>
#include <objc/runtime.h>

#pragma GCC system_header

#ifndef OBJC_SUPER
#define OBJC_SUPER

/// Specifies the superclass of an instance. 
struct objc_super {
    /// Specifies an instance of a class.
    __unsafe_unretained id receiver;

    /// Specifies the particular superclass of the instance to message. 
#if !defined(__cplusplus)  &&  !__OBJC2__
    /* For compatibility with old objc-runtime.h header */
    __unsafe_unretained Class class;
#else
    __unsafe_unretained Class super_class;
#endif
    /* super_class is the first class to search */
};
#endif


/* Basic Messaging Primitives
 *
 * On some architectures, use objc_msgSend_stret for some struct return types.
 * On some architectures, use objc_msgSend_fpret for some float return types.
 * On some architectures, use objc_msgSend_fp2ret for some float return types.
 *
 * These functions must be cast to an appropriate function pointer type 
 * before being called. 
 */
#if !OBJC_OLD_DISPATCH_PROTOTYPES
OBJC_EXPORT void objc_msgSend(void /* id self, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
OBJC_EXPORT void objc_msgSendSuper(void /* struct objc_super *super, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
#else
/** 
 * Sends a message with a simple return value to an instance of a class.
 * 
 * @param self A pointer to the instance of the class that is to receive the message.
 * @param op The selector of the method that handles the message.
 * @param ... 
 *   A variable argument list containing the arguments to the method.
 * 
 * @return The return value of the method.
 * 
 * @note When it encounters a method call, the compiler generates a call to one of the
 *  functions \c objc_msgSend, \c objc_msgSend_stret, \c objc_msgSendSuper, or \c objc_msgSendSuper_stret.
 *  Messages sent to an object’s superclass (using the \c super keyword) are sent using \c objc_msgSendSuper; 
 *  other messages are sent using \c objc_msgSend. Methods that have data structures as return values
 *  are sent using \c objc_msgSendSuper_stret and \c objc_msgSend_stret.
 */
OBJC_EXPORT id objc_msgSend(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
/** 
 * Sends a message with a simple return value to the superclass of an instance of a class.
 * 
 * @param super A pointer to an \c objc_super data structure. Pass values identifying the
 *  context the message was sent to, including the instance of the class that is to receive the
 *  message and the superclass at which to start searching for the method implementation.
 * @param op A pointer of type SEL. Pass the selector of the method that will handle the message.
 * @param ...
 *   A variable argument list containing the arguments to the method.
 * 
 * @return The return value of the method identified by \e op.
 * 
 * @see objc_msgSend
 */
OBJC_EXPORT id objc_msgSendSuper(struct objc_super *super, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
#endif


/* Struct-returning Messaging Primitives
 *
 * Use these functions to call methods that return structs on the stack. 
 * On some architectures, some structures are returned in registers. 
 * Consult your local function call ABI documentation for details.
 * 
 * These functions must be cast to an appropriate function pointer type 
 * before being called. 
 */
#if !OBJC_OLD_DISPATCH_PROTOTYPES
OBJC_EXPORT void objc_msgSend_stret(void /* id self, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;
OBJC_EXPORT void objc_msgSendSuper_stret(void /* struct objc_super *super, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;
#else
/** 
 * Sends a message with a data-structure return value to an instance of a class.
 * 
 * @see objc_msgSend
 */
OBJC_EXPORT void objc_msgSend_stret(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;

/** 
 * Sends a message with a data-structure return value to the superclass of an instance of a class.
 * 
 * @see objc_msgSendSuper
 */
OBJC_EXPORT void objc_msgSendSuper_stret(struct objc_super *super, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;
#endif


/* Floating-point-returning Messaging Primitives
 * 
 * Use these functions to call methods that return floating-point values 
 * on the stack. 
 * Consult your local function call ABI documentation for details.
 * 
 * arm:    objc_msgSend_fpret not used
 * i386:   objc_msgSend_fpret used for `float`, `double`, `long double`.
 * x86-64: objc_msgSend_fpret used for `long double`.
 *
 * arm:    objc_msgSend_fp2ret not used
 * i386:   objc_msgSend_fp2ret not used
 * x86-64: objc_msgSend_fp2ret used for `_Complex long double`.
 *
 * These functions must be cast to an appropriate function pointer type 
 * before being called. 
 */
#if !OBJC_OLD_DISPATCH_PROTOTYPES

# if defined(__i386__)

OBJC_EXPORT void objc_msgSend_fpret(void /* id self, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_2_0);

# elif defined(__x86_64__)

OBJC_EXPORT void objc_msgSend_fpret(void /* id self, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_msgSend_fp2ret(void /* id self, SEL op, ... */ )
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

# endif

// !OBJC_OLD_DISPATCH_PROTOTYPES
#else
// OBJC_OLD_DISPATCH_PROTOTYPES
# if defined(__i386__)

/** 
 * Sends a message with a floating-point return value to an instance of a class.
 * 
 * @see objc_msgSend
 * @note On the i386 platform, the ABI for functions returning a floating-point value is
 *  incompatible with that for functions returning an integral type. On the i386 platform, therefore, 
 *  you must use \c objc_msgSend_fpret for functions returning non-integral type. For \c float or 
 *  \c long \c double return types, cast the function to an appropriate function pointer type first.
 */
OBJC_EXPORT double objc_msgSend_fpret(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_4, __IPHONE_2_0);

/* Use objc_msgSendSuper() for fp-returning messages to super. */
/* See also objc_msgSendv_fpret() below. */

# elif defined(__x86_64__)
/** 
 * Sends a message with a floating-point return value to an instance of a class.
 * 
 * @see objc_msgSend
 */
OBJC_EXPORT long double objc_msgSend_fpret(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

#  if __STDC_VERSION__ >= 199901L
OBJC_EXPORT _Complex long double objc_msgSend_fp2ret(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
#  else
OBJC_EXPORT void objc_msgSend_fp2ret(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
#  endif

/* Use objc_msgSendSuper() for fp-returning messages to super. */
/* See also objc_msgSendv_fpret() below. */

# endif

// OBJC_OLD_DISPATCH_PROTOTYPES
#endif


/* Direct Method Invocation Primitives
 * Use these functions to call the implementation of a given Method.
 * This is faster than calling method_getImplementation() and method_getName().
 *
 * The receiver must not be nil.
 *
 * These functions must be cast to an appropriate function pointer type 
 * before being called. 
 */
#if !OBJC_OLD_DISPATCH_PROTOTYPES
OBJC_EXPORT void method_invoke(void /* id receiver, Method m, ... */ ) 
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void method_invoke_stret(void /* id receiver, Method m, ... */ ) 
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;
#else
OBJC_EXPORT id method_invoke(id receiver, Method m, ...) 
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void method_invoke_stret(id receiver, Method m, ...) 
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0)
    OBJC_ARM64_UNAVAILABLE;
#endif


/* Message Forwarding Primitives
 * Use these functions to forward a message as if the receiver did not 
 * respond to it. 
 *
 * The receiver must not be nil.
 * 
 * class_getMethodImplementation() may return (IMP)_objc_msgForward.
 * class_getMethodImplementation_stret() may return (IMP)_objc_msgForward_stret
 * 
 * These functions must be cast to an appropriate function pointer type 
 * before being called. 
 *
 * Before Mac OS X 10.6, _objc_msgForward must not be called directly 
 * but may be compared to other IMP values.
 */
#if !OBJC_OLD_DISPATCH_PROTOTYPES
OBJC_EXPORT void _objc_msgForward(void /* id receiver, SEL sel, ... */ ) 
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
OBJC_EXPORT void _objc_msgForward_stret(void /* id receiver, SEL sel, ... */ ) 
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_0)
    OBJC_ARM64_UNAVAILABLE;
#else
OBJC_EXPORT id _objc_msgForward(id receiver, SEL sel, ...) 
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
OBJC_EXPORT void _objc_msgForward_stret(id receiver, SEL sel, ...) 
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_0)
    OBJC_ARM64_UNAVAILABLE;
#endif


/* Variable-argument Messaging Primitives
 *
 * Use these functions to call methods with a list of arguments, such 
 * as the one passed to forward:: .
 *
 * The contents of the argument list are architecture-specific. 
 * Consult your local function call ABI documentation for details.
 * 
 * These functions must be cast to an appropriate function pointer type 
 * before being called, except for objc_msgSendv_stret() which must not 
 * be cast to a struct-returning type.
 */

typedef void* marg_list;

OBJC_EXPORT id objc_msgSendv(id self, SEL op, size_t arg_size, marg_list arg_frame) OBJC2_UNAVAILABLE;
OBJC_EXPORT void objc_msgSendv_stret(void *stretAddr, id self, SEL op, size_t arg_size, marg_list arg_frame) OBJC2_UNAVAILABLE;
/* Note that objc_msgSendv_stret() does not return a structure type, 
 * and should not be cast to do so. This is unlike objc_msgSend_stret() 
 * and objc_msgSendSuper_stret().
 */
#if defined(__i386__)
OBJC_EXPORT double objc_msgSendv_fpret(id self, SEL op, unsigned arg_size, marg_list arg_frame) OBJC2_UNAVAILABLE;
#endif


/* The following marg_list macros are of marginal utility. They
 * are included for compatibility with the old objc-class.h header. */

#if !__OBJC2__

#define marg_prearg_size	0

#define marg_malloc(margs, method) \
	do { \
		margs = (marg_list *)malloc (marg_prearg_size + ((7 + method_getSizeOfArguments(method)) & ~7)); \
	} while (0)

#define marg_free(margs) \
	do { \
		free(margs); \
	} while (0)
	
#define marg_adjustedOffset(method, offset) \
	(marg_prearg_size + offset)

#define marg_getRef(margs, offset, type) \
	( (type *)((char *)margs + marg_adjustedOffset(method,offset) ) )

#define marg_getValue(margs, offset, type) \
	( *marg_getRef(margs, offset, type) )

#define marg_setValue(margs, offset, type, value) \
	( marg_getValue(margs, offset, type) = (value) )

#endif

#endif
