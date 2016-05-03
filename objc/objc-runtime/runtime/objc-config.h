/*
 * Copyright (c) 1999-2002, 2005-2008 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_CONFIG_H_
#define _OBJC_CONFIG_H_

#include <TargetConditionals.h>

// Avoid the !NDEBUG double negative.
#if !NDEBUG
#   define DEBUG 1
#else
#   define DEBUG 0
#endif

// Define SUPPORT_GC=1 to enable garbage collection.
// Be sure to edit OBJC_NO_GC and OBJC_NO_GC_API in objc-api.h as well.
#if TARGET_OS_EMBEDDED  ||  TARGET_OS_IPHONE  ||  TARGET_OS_WIN32  ||  (TARGET_OS_MAC && __x86_64h__)
#   define SUPPORT_GC 0
#else
#   define SUPPORT_GC 1
#endif

// Define SUPPORT_ZONES=1 to enable malloc zone support in NXHashTable.
#if TARGET_OS_EMBEDDED  ||  TARGET_OS_IPHONE
#   define SUPPORT_ZONES 0
#else
#   define SUPPORT_ZONES 1
#endif

// Define SUPPORT_MOD=1 to use the mod operator in NXHashTable and objc-sel-set
#if defined(__arm__)
#   define SUPPORT_MOD 0
#else
#   define SUPPORT_MOD 1
#endif

// Define SUPPORT_PREOPT=1 to enable dyld shared cache optimizations
#if TARGET_OS_WIN32  ||  TARGET_IPHONE_SIMULATOR
#   define SUPPORT_PREOPT 0
#else
#   define SUPPORT_PREOPT 1
#endif

// Define SUPPORT_TAGGED_POINTERS=1 to enable tagged pointer objects
// Be sure to edit tagged pointer SPI in objc-internal.h as well.
#if !(__OBJC2__  &&  __LP64__)
#   define SUPPORT_TAGGED_POINTERS 0
#else
#   define SUPPORT_TAGGED_POINTERS 1
#endif

// Define SUPPORT_MSB_TAGGED_POINTERS to use the MSB 
// as the tagged pointer marker instead of the LSB.
// Be sure to edit tagged pointer SPI in objc-internal.h as well.
#if !SUPPORT_TAGGED_POINTERS  ||  !TARGET_OS_IPHONE
#   define SUPPORT_MSB_TAGGED_POINTERS 0
#else
#   define SUPPORT_MSB_TAGGED_POINTERS 1
#endif

// Define SUPPORT_NONPOINTER_ISA=1 to enable extra data in the isa field.
#if !__LP64__  ||  TARGET_OS_WIN32  ||  TARGET_IPHONE_SIMULATOR
#   define SUPPORT_NONPOINTER_ISA 0
#else
#   define SUPPORT_NONPOINTER_ISA 1
#endif

// Define SUPPORT_FIXUP=1 to repair calls sites for fixup dispatch.
// Fixup messaging itself is no longer supported.
// Be sure to edit objc-abi.h as well (objc_msgSend*_fixup)
// Note TARGET_OS_MAC is also set for iOS simulator.
#if !__x86_64__  ||  !TARGET_OS_MAC
#   define SUPPORT_FIXUP 0
#else
#   define SUPPORT_FIXUP 1
#endif

// Define SUPPORT_IGNORED_SELECTOR_CONSTANT to remap GC-ignored selectors.
// Good: fast ignore in objc_msgSend. Bad: disable shared cache optimizations
// Now used only for old-ABI GC.
// This is required for binary compatibility on 32-bit Mac: rdar://13757938
#if __OBJC2__  ||  !SUPPORT_GC
#   define SUPPORT_IGNORED_SELECTOR_CONSTANT 0
#else
#   define SUPPORT_IGNORED_SELECTOR_CONSTANT 1
#   if defined(__i386__)
#       define kIgnore 0xfffeb010
#   else
#       error unknown architecture
#   endif
#endif

// Define SUPPORT_ZEROCOST_EXCEPTIONS to use "zero-cost" exceptions for OBJC2.
// Be sure to edit objc-exception.h as well (objc_add/removeExceptionHandler)
#if !__OBJC2__  ||  (defined(__arm__)  &&  __USING_SJLJ_EXCEPTIONS__)
#   define SUPPORT_ZEROCOST_EXCEPTIONS 0
#else
#   define SUPPORT_ZEROCOST_EXCEPTIONS 1
#endif

// Define SUPPORT_ALT_HANDLERS if you're using zero-cost exceptions 
// but also need to support AppKit's alt-handler scheme
// Be sure to edit objc-exception.h as well (objc_add/removeExceptionHandler)
#if !SUPPORT_ZEROCOST_EXCEPTIONS  ||  TARGET_OS_IPHONE  ||  TARGET_OS_EMBEDDED
#   define SUPPORT_ALT_HANDLERS 0
#else
#   define SUPPORT_ALT_HANDLERS 1
#endif

// Define SUPPORT_RETURN_AUTORELEASE to optimize autoreleased return values
#if !__OBJC2__  ||  TARGET_OS_WIN32
#   define SUPPORT_RETURN_AUTORELEASE 0
#else
#   define SUPPORT_RETURN_AUTORELEASE 1
#endif

// Define SUPPORT_STRET on architectures that need separate struct-return ABI.
#if defined(__arm64__)
#   define SUPPORT_STRET 0
#else
#   define SUPPORT_STRET 1
#endif

// Define SUPPORT_MESSAGE_LOGGING to enable NSObjCMessageLoggingEnabled
#if TARGET_OS_WIN32  ||  TARGET_OS_EMBEDDED
#   define SUPPORT_MESSAGE_LOGGING 0
#else
#   define SUPPORT_MESSAGE_LOGGING 1
#endif

// Define SUPPORT_QOS_HACK to work around deadlocks due to QoS bugs.
#if !__OBJC2__  ||  TARGET_OS_WIN32
#   define SUPPORT_QOS_HACK 0
#else
#   define SUPPORT_QOS_HACK 1
#endif

// OBJC_INSTRUMENTED controls whether message dispatching is dynamically
// monitored.  Monitoring introduces substantial overhead.
// NOTE: To define this condition, do so in the build command, NOT by
// uncommenting the line here.  This is because objc-class.h heeds this
// condition, but objc-class.h can not #include this file (objc-config.h)
// because objc-class.h is public and objc-config.h is not.
//#define OBJC_INSTRUMENTED

#endif
