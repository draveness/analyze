/*
 * Copyright (c) 2002-2003, 2006-2007 Apple Inc.  All Rights Reserved.
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

#ifndef __OBJC_EXCEPTION_H_
#define __OBJC_EXCEPTION_H_

#include <objc/objc.h>
#include <stdint.h>

#if !__OBJC2__

// compiler reserves a setjmp buffer + 4 words as localExceptionData

OBJC_EXPORT void objc_exception_throw(id exception)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);
OBJC_EXPORT void objc_exception_try_enter(void *localExceptionData)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);
OBJC_EXPORT void objc_exception_try_exit(void *localExceptionData)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);
OBJC_EXPORT id objc_exception_extract(void *localExceptionData)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);
OBJC_EXPORT int objc_exception_match(Class exceptionClass, id exception)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);


typedef struct {
    int version;
    void (*throw_exc)(id);		// version 0
    void (*try_enter)(void *);	// version 0
    void (*try_exit)(void *);	// version 0
    id	 (*extract)(void *);	// version 0
    int	(*match)(Class, id);	// version 0
} objc_exception_functions_t;

// get table; version tells how many
OBJC_EXPORT void objc_exception_get_functions(objc_exception_functions_t *table)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);

// set table
OBJC_EXPORT void objc_exception_set_functions(objc_exception_functions_t *table)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_NA);


// !__OBJC2__
#else
// __OBJC2__

typedef id (*objc_exception_preprocessor)(id exception);
typedef int (*objc_exception_matcher)(Class catch_type, id exception);
typedef void (*objc_uncaught_exception_handler)(id exception);
typedef void (*objc_exception_handler)(id unused, void *context);

/** 
 * Throw a runtime exception. This function is inserted by the compiler
 * where \c @throw would otherwise be.
 * 
 * @param exception The exception to be thrown.
 */
OBJC_EXPORT void objc_exception_throw(id exception)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_exception_rethrow(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT id objc_begin_catch(void *exc_buf)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_end_catch(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_terminate(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0);

OBJC_EXPORT objc_exception_preprocessor objc_setExceptionPreprocessor(objc_exception_preprocessor fn)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT objc_exception_matcher objc_setExceptionMatcher(objc_exception_matcher fn)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT objc_uncaught_exception_handler objc_setUncaughtExceptionHandler(objc_uncaught_exception_handler fn)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

// Not for iOS.
OBJC_EXPORT uintptr_t objc_addExceptionHandler(objc_exception_handler fn, void *context)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT void objc_removeExceptionHandler(uintptr_t token)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);

// __OBJC2__
#endif

#endif  // __OBJC_EXCEPTION_H_

