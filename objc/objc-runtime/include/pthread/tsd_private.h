/*
 * Copyright (c) 2003-2013 Apple Inc. All rights reserved.
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
/*
 * Copyright 1996 1995 by Open Software Foundation, Inc. 1997 1996 1995 1994 1993 1992 1991
 *              All Rights Reserved
 *
 * Permission to use, copy, modify, and distribute this software and
 * its documentation for any purpose and without fee is hereby granted,
 * provided that the above copyright notice appears in all copies and
 * that both the copyright notice and this permission notice appear in
 * supporting documentation.
 *
 * OSF DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE.
 *
 * IN NO EVENT SHALL OSF BE LIABLE FOR ANY SPECIAL, INDIRECT, OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN ACTION OF CONTRACT,
 * NEGLIGENCE, OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
 * WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
/*
 * MkLinux
 */

#ifndef __PTHREAD_TSD_H__
#define __PTHREAD_TSD_H__

#ifndef __ASSEMBLER__

#include <System/machine/cpu_capabilities.h>
#include <sys/cdefs.h>
#include <TargetConditionals.h>
#include <os/tsd.h>
#include <pthread/spinlock_private.h>

#ifndef __TSD_MACH_THREAD_SELF
#define __TSD_MACH_THREAD_SELF 3
#endif

#ifndef __TSD_THREAD_QOS_CLASS
#define __TSD_THREAD_QOS_CLASS 4
#endif

/* Constant TSD slots for inline pthread_getspecific() usage. */

/* Keys 0 - 9 are for Libsyscall/libplatform usage */
#define _PTHREAD_TSD_SLOT_PTHREAD_SELF __TSD_THREAD_SELF
#define _PTHREAD_TSD_SLOT_ERRNO __TSD_ERRNO
#define _PTHREAD_TSD_SLOT_MIG_REPLY __TSD_MIG_REPLY
#define _PTHREAD_TSD_SLOT_MACH_THREAD_SELF __TSD_MACH_THREAD_SELF
#define _PTHREAD_TSD_SLOT_PTHREAD_QOS_CLASS	__TSD_THREAD_QOS_CLASS
//#define _PTHREAD_TSD_SLOT_SEMAPHORE_CACHE__TSD_SEMAPHORE_CACHE

//#define _PTHREAD_TSD_RESERVED_SLOT_COUNT _PTHREAD_TSD_RESERVED_SLOT_COUNT

/* Keys 10 - 29 are for Libc/Libsystem internal usage */
/* used as __pthread_tsd_first + Num  */
#define __PTK_LIBC_LOCALE_KEY		10
#define __PTK_LIBC_TTYNAME_KEY		11
#define __PTK_LIBC_LOCALTIME_KEY	12
#define __PTK_LIBC_GMTIME_KEY		13
#define __PTK_LIBC_GDTOA_BIGINT_KEY	14
#define __PTK_LIBC_PARSEFLOAT_KEY	15
/* for usage by dyld */
#define __PTK_LIBC_DYLD_Unwind_SjLj_Key	18

/* Keys 20-29 for libdispatch usage */
#define __PTK_LIBDISPATCH_KEY0		20
#define __PTK_LIBDISPATCH_KEY1		21
#define __PTK_LIBDISPATCH_KEY2		22
#define __PTK_LIBDISPATCH_KEY3		23
#define __PTK_LIBDISPATCH_KEY4		24
#define __PTK_LIBDISPATCH_KEY5		25
#define __PTK_LIBDISPATCH_KEY6		26
#define __PTK_LIBDISPATCH_KEY7		27
#define __PTK_LIBDISPATCH_KEY8		28
#define __PTK_LIBDISPATCH_KEY9		29

/* Keys 30-255 for Non Libsystem usage */

/* Keys 30-39 for Graphic frameworks usage */
#define _PTHREAD_TSD_SLOT_OPENGL	30	/* backwards compat sake */
#define __PTK_FRAMEWORK_OPENGL_KEY	30
#define __PTK_FRAMEWORK_GRAPHICS_KEY1	31
#define __PTK_FRAMEWORK_GRAPHICS_KEY2	32
#define __PTK_FRAMEWORK_GRAPHICS_KEY3	33
#define __PTK_FRAMEWORK_GRAPHICS_KEY4	34
#define __PTK_FRAMEWORK_GRAPHICS_KEY5	35
#define __PTK_FRAMEWORK_GRAPHICS_KEY6	36
#define __PTK_FRAMEWORK_GRAPHICS_KEY7	37
#define __PTK_FRAMEWORK_GRAPHICS_KEY8	38
#define __PTK_FRAMEWORK_GRAPHICS_KEY9	39

/* Keys 40-49 for Objective-C runtime usage */
#define __PTK_FRAMEWORK_OBJC_KEY0	40
#define __PTK_FRAMEWORK_OBJC_KEY1	41
#define __PTK_FRAMEWORK_OBJC_KEY2	42
#define __PTK_FRAMEWORK_OBJC_KEY3	43
#define __PTK_FRAMEWORK_OBJC_KEY4	44
#define __PTK_FRAMEWORK_OBJC_KEY5	45
#define __PTK_FRAMEWORK_OBJC_KEY6	46
#define __PTK_FRAMEWORK_OBJC_KEY7	47
#define __PTK_FRAMEWORK_OBJC_KEY8	48
#define __PTK_FRAMEWORK_OBJC_KEY9	49

/* Keys 50-59 for Core Foundation usage */
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY0	50
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY1	51
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY2	52
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY3	53
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY4	54
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY5	55
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY6	56
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY7	57
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY8	58
#define __PTK_FRAMEWORK_COREFOUNDATION_KEY9	59

/* Keys 60-69 for Foundation usage */
#define __PTK_FRAMEWORK_FOUNDATION_KEY0		60
#define __PTK_FRAMEWORK_FOUNDATION_KEY1		61
#define __PTK_FRAMEWORK_FOUNDATION_KEY2		62
#define __PTK_FRAMEWORK_FOUNDATION_KEY3		63
#define __PTK_FRAMEWORK_FOUNDATION_KEY4		64
#define __PTK_FRAMEWORK_FOUNDATION_KEY5		65
#define __PTK_FRAMEWORK_FOUNDATION_KEY6		66
#define __PTK_FRAMEWORK_FOUNDATION_KEY7		67
#define __PTK_FRAMEWORK_FOUNDATION_KEY8		68
#define __PTK_FRAMEWORK_FOUNDATION_KEY9		69

/* Keys 70-79 for Core Animation/QuartzCore usage */
#define __PTK_FRAMEWORK_QUARTZCORE_KEY0		70
#define __PTK_FRAMEWORK_QUARTZCORE_KEY1		71
#define __PTK_FRAMEWORK_QUARTZCORE_KEY2		72
#define __PTK_FRAMEWORK_QUARTZCORE_KEY3		73
#define __PTK_FRAMEWORK_QUARTZCORE_KEY4		74
#define __PTK_FRAMEWORK_QUARTZCORE_KEY5		75
#define __PTK_FRAMEWORK_QUARTZCORE_KEY6		76
#define __PTK_FRAMEWORK_QUARTZCORE_KEY7		77
#define __PTK_FRAMEWORK_QUARTZCORE_KEY8		78
#define __PTK_FRAMEWORK_QUARTZCORE_KEY9		79


/* Keys 80-89 for CoreData */
#define __PTK_FRAMEWORK_COREDATA_KEY0		80
#define __PTK_FRAMEWORK_COREDATA_KEY1		81
#define __PTK_FRAMEWORK_COREDATA_KEY2		82
#define __PTK_FRAMEWORK_COREDATA_KEY3		83
#define __PTK_FRAMEWORK_COREDATA_KEY4		84
#define __PTK_FRAMEWORK_COREDATA_KEY5		85
#define __PTK_FRAMEWORK_COREDATA_KEY6		86
#define __PTK_FRAMEWORK_COREDATA_KEY7		87
#define __PTK_FRAMEWORK_COREDATA_KEY8		88
#define __PTK_FRAMEWORK_COREDATA_KEY9		89

/* Keys 90-94 for JavaScriptCore Collection */
#define __PTK_FRAMEWORK_JAVASCRIPTCORE_KEY0		90
#define __PTK_FRAMEWORK_JAVASCRIPTCORE_KEY1		91
#define __PTK_FRAMEWORK_JAVASCRIPTCORE_KEY2		92
#define __PTK_FRAMEWORK_JAVASCRIPTCORE_KEY3		93
#define __PTK_FRAMEWORK_JAVASCRIPTCORE_KEY4		94
/* Keys 95 for CoreText */
#define __PTK_FRAMEWORK_CORETEXT_KEY0			95

/* Keys 110-119 for Garbage Collection */
#define __PTK_FRAMEWORK_GC_KEY0		110
#define __PTK_FRAMEWORK_GC_KEY1		111
#define __PTK_FRAMEWORK_GC_KEY2		112
#define __PTK_FRAMEWORK_GC_KEY3		113
#define __PTK_FRAMEWORK_GC_KEY4		114
#define __PTK_FRAMEWORK_GC_KEY5		115
#define __PTK_FRAMEWORK_GC_KEY6		116
#define __PTK_FRAMEWORK_GC_KEY7		117
#define __PTK_FRAMEWORK_GC_KEY8		118
#define __PTK_FRAMEWORK_GC_KEY9		119

/* Keys 210 - 229 are for libSystem usage within the iOS Simulator */
/* They are offset from their corresponding libSystem keys by 200 */
#define __PTK_LIBC_SIM_LOCALE_KEY	210
#define __PTK_LIBC_SIM_TTYNAME_KEY	211
#define __PTK_LIBC_SIM_LOCALTIME_KEY	212
#define __PTK_LIBC_SIM_GMTIME_KEY	213
#define __PTK_LIBC_SIM_GDTOA_BIGINT_KEY	214
#define __PTK_LIBC_SIM_PARSEFLOAT_KEY	215

__BEGIN_DECLS

extern void *pthread_getspecific(unsigned long);
extern int pthread_setspecific(unsigned long, const void *);
/* setup destructor function for static key as it is not created with pthread_key_create() */
extern int pthread_key_init_np(int, void (*)(void *));

#if PTHREAD_LAYOUT_SPI

/* SPI intended for CoreSymbolication only */

__OSX_AVAILABLE_STARTING(__MAC_10_10,__IPHONE_8_0)
extern const struct pthread_layout_offsets_s {
    // always add new fields at the end
    const uint16_t plo_version;
    // either of the next two fields may be 0; use whichever is set
    // bytes from pthread_t to base of tsd
    const uint16_t plo_pthread_tsd_base_offset;
    // bytes from pthread_t to a pointer to base of tsd
    const uint16_t plo_pthread_tsd_base_address_offset;
    const uint16_t plo_pthread_tsd_entry_size;
} pthread_layout_offsets;

#endif // PTHREAD_LAYOUT_SPI
__END_DECLS

#if TARGET_IPHONE_SIMULATOR

__header_always_inline int
_pthread_has_direct_tsd(void)
{
    return 0;
}

#define _pthread_getspecific_direct(key) pthread_getspecific((key))
#define _pthread_setspecific_direct(key, val) pthread_setspecific((key), (val))

#else  /* TARGET_IPHONE_SIMULATOR */

__header_always_inline int
_pthread_has_direct_tsd(void)
{
    return 1;
}

/* To be used with static constant keys only */
__header_always_inline void *
_pthread_getspecific_direct(unsigned long slot)
{
    return _os_tsd_get_direct(slot);
}

/* To be used with static constant keys only */
__header_always_inline int
_pthread_setspecific_direct(unsigned long slot, void * val)
{
    return _os_tsd_set_direct(slot, val);
}

#endif /* TARGET_IPHONE_SIMULATOR */

#endif /* ! __ASSEMBLER__ */
#endif /* __PTHREAD_TSD_H__ */
