/*
 * Copyright (c) 2009 Apple Inc.  All Rights Reserved.
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


#ifndef _OBJC_ABI_H
#define _OBJC_ABI_H

/* 
 * WARNING  DANGER  HAZARD  BEWARE  EEK
 * 
 * Everything in this file is for Apple Internal use only.
 * These will change in arbitrary OS updates and in unpredictable ways.
 * When your program breaks, you get to keep both pieces.
 */

/*
 * objc-abi.h: Declarations for functions used by compiler codegen.
 */

#include <malloc/malloc.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>

/* Runtime startup. */

// Old static initializer. Used by old crt1.o and old bug workarounds.
OBJC_EXPORT void _objcInit(void)
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);


/* Properties */

// Read or write an object property. Not all object properties use these.
OBJC_EXPORT id objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, BOOL atomic)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_setProperty(id self, SEL _cmd, ptrdiff_t offset, id newValue, BOOL atomic, signed char shouldCopy)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

OBJC_EXPORT void objc_setProperty_atomic(id self, SEL _cmd, id newValue, ptrdiff_t offset)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
    OBJC_GC_UNAVAILABLE;
OBJC_EXPORT void objc_setProperty_nonatomic(id self, SEL _cmd, id newValue, ptrdiff_t offset)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
    OBJC_GC_UNAVAILABLE;
OBJC_EXPORT void objc_setProperty_atomic_copy(id self, SEL _cmd, id newValue, ptrdiff_t offset)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
    OBJC_GC_UNAVAILABLE;
OBJC_EXPORT void objc_setProperty_nonatomic_copy(id self, SEL _cmd, id newValue, ptrdiff_t offset)
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0)
    OBJC_GC_UNAVAILABLE;


// Read or write a non-object property. Not all uses are C structs, 
// and not all C struct properties use this.
OBJC_EXPORT void objc_copyStruct(void *dest, const void *src, ptrdiff_t size, BOOL atomic, BOOL hasStrong)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

// Perform a copy of a C++ object using striped locks. Used by non-POD C++ typed atomic properties.
OBJC_EXPORT void objc_copyCppObjectAtomic(void *dest, const void *src, void (*copyHelper) (void *dest, const void *source))
    __OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_6_0);

/* Classes. */
#if __OBJC2__
OBJC_EXPORT IMP _objc_empty_vtable
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
#endif
OBJC_EXPORT struct objc_cache _objc_empty_cache
    __OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);


/* Messages */

#if __OBJC2__
// objc_msgSendSuper2() takes the current search class, not its superclass.
OBJC_EXPORT id objc_msgSendSuper2(struct objc_super *super, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);
OBJC_EXPORT void objc_msgSendSuper2_stret(struct objc_super *super, SEL op,...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

// objc_msgSend_noarg() may be faster for methods with no additional arguments.
OBJC_EXPORT id objc_msgSend_noarg(id self, SEL _cmd)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#endif

#if __OBJC2__
// Debug messengers. Messengers used by the compiler have a debug flavor that 
// may perform extra sanity checking. 
// Old objc_msgSendSuper() does not have a debug version; this is OBJC2 only.
// *_fixup() do not have debug versions; use non-fixup only for debug mode.
OBJC_EXPORT id objc_msgSend_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
OBJC_EXPORT id objc_msgSendSuper2_debug(struct objc_super *super, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
OBJC_EXPORT void objc_msgSend_stret_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
OBJC_EXPORT void objc_msgSendSuper2_stret_debug(struct objc_super *super, SEL op,...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

# if defined(__i386__)
OBJC_EXPORT double objc_msgSend_fpret_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
# elif defined(__x86_64__)
OBJC_EXPORT long double objc_msgSend_fpret_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#  if __STDC_VERSION__ >= 199901L
OBJC_EXPORT _Complex long double objc_msgSend_fp2ret_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#  else
OBJC_EXPORT void objc_msgSend_fp2ret_debug(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);
#  endif
# endif

#endif

#if __OBJC2__  &&  defined(__x86_64__)
// objc_msgSend_fixup() is used for vtable-dispatchable call sites.
OBJC_EXPORT id objc_msgSend_fixup(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT void objc_msgSend_stret_fixup(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT id objc_msgSendSuper2_fixup(struct objc_super *super, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT void objc_msgSendSuper2_stret_fixup(struct objc_super *super, SEL op,...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
OBJC_EXPORT long double objc_msgSend_fpret_fixup(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
# if __STDC_VERSION__ >= 199901L
OBJC_EXPORT _Complex long double objc_msgSend_fp2ret_fixup(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
# else
OBJC_EXPORT void objc_msgSend_fp2ret_fixup(id self, SEL op, ...)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_NA);
# endif
#endif

/* C++-compatible exception handling. */
#if __OBJC2__

// fixme these conflict with C++ compiler's internal definitions
#if !defined(__cplusplus)

// Vtable for C++ exception typeinfo for Objective-C types.
OBJC_EXPORT const void *objc_ehtype_vtable[]
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

// C++ exception typeinfo for type `id`.
OBJC_EXPORT struct objc_typeinfo OBJC_EHTYPE_id
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

#endif

// Exception personality function for Objective-C and Objective-C++ code.
struct _Unwind_Exception;
struct _Unwind_Context;
OBJC_EXPORT int
__objc_personality_v0(int version,
                      int actions,
                      uint64_t exceptionClass,
                      struct _Unwind_Exception *exceptionObject,
                      struct _Unwind_Context *context)
    __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

#endif

/* ARR */

OBJC_EXPORT id objc_retainBlock(id)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_5_0);

#endif
