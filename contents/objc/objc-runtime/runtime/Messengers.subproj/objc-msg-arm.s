/*
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Copyright (c) 1999-2007 Apple Computer, Inc.  All Rights Reserved.
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
/********************************************************************
 * 
 *  objc-msg-arm.s - ARM code to support objc messaging
 *
 ********************************************************************/

#ifdef __arm__
	
#include <arm/arch.h>

#ifndef _ARM_ARCH_7
#   error requires armv7
#endif

// Set FP=1 on architectures that pass parameters in floating-point registers
#if __ARM_ARCH_7K__
#   define FP 1
#else
#   define FP 0
#endif

#if FP

#   if !__ARM_NEON__
#       error sorry
#   endif

#   define FP_RETURN_ZERO \
	vmov.i32  q0, #0  ; \
	vmov.i32  q1, #0  ; \
	vmov.i32  q2, #0  ; \
	vmov.i32  q3, #0

#   define FP_SAVE \
	vpush	{q0-q3}

#   define FP_RESTORE \
	vpop	{q0-q3}

#else

#   define FP_RETURN_ZERO
#   define FP_SAVE
#   define FP_RESTORE

#endif

.syntax unified	
	
#define MI_EXTERN(var) \
	.non_lazy_symbol_pointer                        ;\
L ## var ## $$non_lazy_ptr:                              ;\
	.indirect_symbol var                            ;\
	.long 0

#define MI_GET_EXTERN(reg,var)  \
	movw	reg, :lower16:(L##var##$$non_lazy_ptr-4f-4)  ;\
	movt	reg, :upper16:(L##var##$$non_lazy_ptr-4f-4)  ;\
4:	add	reg, pc                                     ;\
	ldr	reg, [reg]

#define MI_CALL_EXTERNAL(var)    \
	MI_GET_EXTERN(r12,var)  ;\
	blx     r12

	
#define MI_GET_ADDRESS(reg,var)  \
	movw	reg, :lower16:(var-4f-4)  ;\
	movt	reg, :upper16:(var-4f-4)  ;\
4:	add	reg, pc                                     ;\


MI_EXTERN(__class_lookupMethodAndLoadCache3)
MI_EXTERN(___objc_error)


.data

// _objc_entryPoints and _objc_exitPoints are used by method dispatch
// caching code to figure out whether any threads are actively 
// in the cache for dispatching.  The labels surround the asm code
// that do cache lookups.  The tables are zero-terminated.

.align 2
.private_extern _objc_entryPoints
_objc_entryPoints:
	.long   _cache_getImp
	.long   _objc_msgSend
	.long   _objc_msgSend_stret
	.long   _objc_msgSendSuper
	.long   _objc_msgSendSuper_stret
	.long   _objc_msgSendSuper2
	.long   _objc_msgSendSuper2_stret
	.long   0

.private_extern _objc_exitPoints
_objc_exitPoints:
	.long   LGetImpExit
	.long   LMsgSendExit
	.long   LMsgSendStretExit
	.long   LMsgSendSuperExit
	.long   LMsgSendSuperStretExit
	.long   LMsgSendSuper2Exit
	.long   LMsgSendSuper2StretExit
	.long   0


/********************************************************************
* List every exit insn from every messenger for debugger use.
* Format:
* (
*   1 word instruction's address
*   1 word type (ENTER or FAST_EXIT or SLOW_EXIT or NIL_EXIT)
* )
* 1 word zero
*
* ENTER is the start of a dispatcher
* FAST_EXIT is method dispatch
* SLOW_EXIT is uncached method lookup
* NIL_EXIT is returning zero from a message sent to nil
* These must match objc-gdb.h.
********************************************************************/
	
#define ENTER     1
#define FAST_EXIT 2
#define SLOW_EXIT 3
#define NIL_EXIT  4

.section __DATA,__objc_msg_break
.globl _gdb_objc_messenger_breakpoints
_gdb_objc_messenger_breakpoints:
// contents populated by the macros below

.macro MESSENGER_START
4:
	.section __DATA,__objc_msg_break
	.long 4b
	.long ENTER
	.text
.endmacro
.macro MESSENGER_END_FAST
4:
	.section __DATA,__objc_msg_break
	.long 4b
	.long FAST_EXIT
	.text
.endmacro
.macro MESSENGER_END_SLOW
4:
	.section __DATA,__objc_msg_break
	.long 4b
	.long SLOW_EXIT
	.text
.endmacro
.macro MESSENGER_END_NIL
4:
	.section __DATA,__objc_msg_break
	.long 4b
	.long NIL_EXIT
	.text
.endmacro

	
/********************************************************************
 * Names for relative labels
 * DO NOT USE THESE LABELS ELSEWHERE
 * Reserved labels: 8: 9:
 ********************************************************************/
#define LCacheMiss 	8
#define LCacheMiss_f 	8f
#define LCacheMiss_b 	8b
#define LNilReceiver 	9
#define LNilReceiver_f 	9f
#define LNilReceiver_b 	9b


/********************************************************************
 * Macro parameters
 ********************************************************************/

#define NORMAL 0
#define FPRET 1
#define FP2RET 2
#define GETIMP 3
#define STRET 4
#define SUPER 5
#define SUPER2 6
#define SUPER_STRET 7
#define SUPER2_STRET 8


/********************************************************************
 *
 * Structure definitions.
 *
 ********************************************************************/

/* objc_super parameter to sendSuper */
#define RECEIVER         0
#define CLASS            4

/* Selected field offsets in class structure */
#define ISA              0
#define SUPERCLASS       4
#define CACHE            8
#define CACHE_MASK      12

/* Selected field offsets in method structure */
#define METHOD_NAME      0
#define METHOD_TYPES     4
#define METHOD_IMP       8


//////////////////////////////////////////////////////////////////////
//
// ENTRY		functionName
//
// Assembly directives to begin an exported function.
//
// Takes: functionName - name of the exported function
//////////////////////////////////////////////////////////////////////

.macro ENTRY /* name */
	.text
	.thumb
	.align 5
	.globl    _$0
	.thumb_func
_$0:	
.endmacro

.macro STATIC_ENTRY /*name*/
	.text
	.thumb
	.align 5
	.private_extern _$0
	.thumb_func
_$0:	
.endmacro
	
	
//////////////////////////////////////////////////////////////////////
//
// END_ENTRY	functionName
//
// Assembly directives to end an exported function.  Just a placeholder,
// a close-parenthesis for ENTRY, until it is needed for something.
//
// Takes: functionName - name of the exported function
//////////////////////////////////////////////////////////////////////

.macro END_ENTRY /* name */
.endmacro


/////////////////////////////////////////////////////////////////////
//
// CacheLookup	return-type
//
// Locate the implementation for a selector in a class's method cache.
//
// Takes: 
//	  $0 = NORMAL, STRET, SUPER, SUPER_STRET, SUPER2, SUPER2_STRET, GETIMP
//	  r0 or r1 (STRET) = receiver
//	  r1 or r2 (STRET) = selector
//	  r9 = class to search in
//
// On exit: r9 and r12 clobbered
//	    (found) calls or returns IMP, eq/ne/r9 set for forwarding
//	    (not found) jumps to LCacheMiss
//
/////////////////////////////////////////////////////////////////////
	
.macro CacheHit

.if $0 == GETIMP
	ldr	r0, [r9, #4]		// r0 = bucket->imp
	MI_GET_ADDRESS(r1, __objc_msgSend_uncached_impcache)
	teq	r0, r1
	it	eq
	moveq	r0, #0			// don't return msgSend_uncached
	bx	lr			// return imp
.elseif $0 == NORMAL
	ldr	r12, [r9, #4]		// r12 = bucket->imp
					// eq already set for nonstret forward
	MESSENGER_END_FAST
	bx	r12			// call imp
.elseif $0 == STRET
	ldr	r12, [r9, #4]		// r12 = bucket->imp
	movs	r9, #1			// r9=1, Z=0 for stret forwarding
	MESSENGER_END_FAST
	bx	r12			// call imp
.elseif $0 == SUPER
	ldr	r12, [r9, #4]		// r12 = bucket->imp
	ldr	r9, [r0, #CLASS]	// r9 = class to search for forwarding
	ldr	r0, [r0, #RECEIVER]	// fetch real receiver
	tst	r12, r12		// set ne for forwarding (r12!=0)
	MESSENGER_END_FAST
	bx	r12			// call imp
.elseif $0 == SUPER2
	ldr	r12, [r9, #4]		// r12 = bucket->imp
	ldr	r9, [r0, #CLASS]
	ldr	r9, [r9, #SUPERCLASS]	// r9 = class to search for forwarding
	ldr	r0, [r0, #RECEIVER]	// fetch real receiver
	tst	r12, r12		// set ne for forwarding (r12!=0)
	MESSENGER_END_FAST
	bx	r12			// call imp
.elseif $0 == SUPER_STRET
	ldr	r12, [r9, #4]		// r12 = bucket->imp
	ldr	r9, [r1, #CLASS]	// r9 = class to search for forwarding
	orr	r9, r9, #1		// r9 = class|1 for super_stret forward
	ldr	r1, [r1, #RECEIVER]	// fetch real receiver
	tst	r12, r12		// set ne for forwarding (r12!=0)
	MESSENGER_END_FAST
	bx	r12			// call imp
.elseif $0 == SUPER2_STRET
	ldr	r12, [r9, #4]		// r12 = bucket->imp
	ldr	r9, [r1, #CLASS]	// r9 = class to search for forwarding
	ldr	r9, [r9, #SUPERCLASS]	// r9 = class to search for forwarding
	orr	r9, r9, #1		// r9 = class|1 for super_stret forward
	ldr	r1, [r1, #RECEIVER]	// fetch real receiver
	tst	r12, r12		// set ne for forwarding (r12!=0)
	MESSENGER_END_FAST
	bx	r12			// call imp
.else
.abort oops
.endif

.endmacro
	
.macro CacheLookup
	
	ldrh	r12, [r9, #CACHE_MASK]	// r12 = mask
	ldr	r9, [r9, #CACHE]	// r9 = buckets
.if $0 == STRET  ||  $0 == SUPER_STRET
	and	r12, r12, r2		// r12 = index = SEL & mask
.else
	and	r12, r12, r1		// r12 = index = SEL & mask
.endif
	add	r9, r9, r12, LSL #3	// r9 = bucket = buckets+index*8
	ldr	r12, [r9]		// r12 = bucket->sel
2:
.if $0 == STRET  ||  $0 == SUPER_STRET
	teq	r12, r2
.else
	teq	r12, r1
.endif
	bne	1f
	CacheHit $0
1:	
	cmp	r12, #1
	blo	LCacheMiss_f		// if (bucket->sel == 0) cache miss
	it	eq			// if (bucket->sel == 1) cache wrap
	ldreq	r9, [r9, #4]		// bucket->imp is before first bucket
	ldr	r12, [r9, #8]!		// r12 = (++bucket)->sel
	b	2b

.endmacro


/********************************************************************
 * IMP cache_getImp(Class cls, SEL sel)
 *
 * On entry:    r0 = class whose cache is to be searched
 *              r1 = selector to search for
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

	STATIC_ENTRY cache_getImp

	mov	r9, r0
	CacheLookup GETIMP		// returns IMP on success
	
LCacheMiss:
	mov     r0, #0          	// return nil if cache miss
	bx	lr

LGetImpExit: 
	END_ENTRY cache_getImp


/********************************************************************
 *
 * id objc_msgSend(id self, SEL	_cmd,...);
 *
 ********************************************************************/

	ENTRY objc_msgSend
	MESSENGER_START
	
	cbz	r0, LNilReceiver_f

	ldr	r9, [r0]		// r9 = self->isa
	CacheLookup NORMAL
	// calls IMP or LCacheMiss

LCacheMiss:
	MESSENGER_END_SLOW
	ldr	r9, [r0, #ISA]		// class = receiver->isa
	b	__objc_msgSend_uncached

LNilReceiver:
	// r0 is already zero
	mov	r1, #0
	mov	r2, #0
	mov	r3, #0
	FP_RETURN_ZERO
	MESSENGER_END_NIL
	bx	lr	

LMsgSendExit:
	END_ENTRY objc_msgSend


/********************************************************************
 * id		objc_msgSend_noarg(id self, SEL op)
 *
 * On entry: r0 is the message receiver,
 *           r1 is the selector
 ********************************************************************/

	ENTRY objc_msgSend_noarg
	b 	_objc_msgSend
	END_ENTRY objc_msgSend_noarg


/********************************************************************
 * void objc_msgSend_stret(void *st_addr, id self, SEL op, ...);
 *
 * objc_msgSend_stret is the struct-return form of msgSend.
 * The ABI calls for r0 to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry: r0 is the address where the structure is returned,
 *           r1 is the message receiver,
 *           r2 is the selector
 ********************************************************************/

	ENTRY objc_msgSend_stret
	MESSENGER_START
	
	cbz	r1, LNilReceiver_f

	ldr	r9, [r1]		// r9 = self->isa
	CacheLookup STRET
	// calls IMP or LCacheMiss

LCacheMiss:	
	MESSENGER_END_SLOW
	ldr	r9, [r1]		// r9 = self->isa
	b	__objc_msgSend_stret_uncached

LNilReceiver:
	MESSENGER_END_NIL
	bx	lr
	
LMsgSendStretExit:
	END_ENTRY objc_msgSend_stret


/********************************************************************
 * id objc_msgSendSuper(struct objc_super *super, SEL op, ...)
 *
 * struct objc_super {
 *     id receiver;
 *     Class cls;	// the class to search
 * }
 ********************************************************************/

	ENTRY objc_msgSendSuper
	MESSENGER_START
	
	ldr	r9, [r0, #CLASS]	// r9 = struct super->class
	CacheLookup SUPER
	// calls IMP or LCacheMiss

LCacheMiss:
	MESSENGER_END_SLOW
	ldr	r9, [r0, #CLASS]	// r9 = struct super->class
	ldr	r0, [r0, #RECEIVER]	// load real receiver
	b	__objc_msgSend_uncached
	
LMsgSendSuperExit:
	END_ENTRY objc_msgSendSuper


/********************************************************************
 * id objc_msgSendSuper2(struct objc_super *super, SEL op, ...)
 *
 * struct objc_super {
 *     id receiver;
 *     Class cls;	// SUBCLASS of the class to search
 * }
 ********************************************************************/
	
	ENTRY objc_msgSendSuper2
	MESSENGER_START
	
	ldr	r9, [r0, #CLASS]	// class = struct super->class
	ldr     r9, [r9, #SUPERCLASS]   // class = class->superclass
	CacheLookup SUPER2
	// calls IMP or LCacheMiss

LCacheMiss:
	MESSENGER_END_SLOW
	ldr	r9, [r0, #CLASS]	// class = struct super->class
	ldr     r9, [r9, #SUPERCLASS]   // class = class->superclass
	ldr	r0, [r0, #RECEIVER]	// load real receiver
	b	__objc_msgSend_uncached
	
LMsgSendSuper2Exit:
	END_ENTRY objc_msgSendSuper2


/********************************************************************
 * void objc_msgSendSuper_stret(void *st_addr, objc_super *self, SEL op, ...);
 *
 * objc_msgSendSuper_stret is the struct-return form of msgSendSuper.
 * The ABI calls for r0 to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry: r0 is the address where the structure is returned,
 *           r1 is the address of the objc_super structure,
 *           r2 is the selector
 ********************************************************************/

	ENTRY objc_msgSendSuper_stret
	MESSENGER_START
	
	ldr     r9, [r1, #CLASS]	// r9 = struct super->class
	CacheLookup SUPER_STRET
	// calls IMP or LCacheMiss

LCacheMiss:
	MESSENGER_END_SLOW
	ldr     r9, [r1, #CLASS]	// r9 = struct super->class
	ldr     r1, [r1, #RECEIVER]	// load real receiver
	b	__objc_msgSend_stret_uncached

LMsgSendSuperStretExit:
	END_ENTRY objc_msgSendSuper_stret


/********************************************************************
 * id objc_msgSendSuper2_stret
 ********************************************************************/

	ENTRY objc_msgSendSuper2_stret
	MESSENGER_START
	
	ldr     r9, [r1, #CLASS]	// class = struct super->class
	ldr     r9, [r9, #SUPERCLASS]	// class = class->superclass
	CacheLookup SUPER2_STRET

LCacheMiss:
	MESSENGER_END_SLOW
	ldr     r9, [r1, #CLASS]	// class = struct super->class
	ldr     r9, [r9, #SUPERCLASS]	// class = class->superclass
	ldr	r1, [r1, #RECEIVER]	// load real receiver
	b	__objc_msgSend_stret_uncached
	
LMsgSendSuper2StretExit:
	END_ENTRY objc_msgSendSuper2_stret


/********************************************************************
 *
 * _objc_msgSend_uncached_impcache
 * Used to erase method cache entries in-place by 
 * bouncing them to the uncached lookup.
 *
 * _objc_msgSend_uncached
 * _objc_msgSend_stret_uncached
 * The uncached lookup.
 *
 ********************************************************************/
	
	STATIC_ENTRY _objc_msgSend_uncached_impcache
	// Method cache version

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band Z is 0 (EQ) for normal, 1 (NE) for stret and/or super
	// Out-of-band r9 is 1 for stret, cls for super, cls|1 for super_stret
	// Note objc_msgForward_impcache uses the same parameters

	MESSENGER_START
	nop
	MESSENGER_END_SLOW
	
	ite	eq
	ldreq	r9, [r0]		// normal: r9 = class = self->isa
	tstne	r9, #1			// low bit clear?
	beq	__objc_msgSend_uncached	// super: r9 is already the class
					// stret or super_stret
	eors	r9, r9, #1		// clear low bit
	it	eq			// r9 now zero?
	ldreq	r9, [r1]		// stret: r9 = class = self->isa
					// super_stret: r9 is already the class
	b	__objc_msgSend_stret_uncached

	END_ENTRY _objc_msgSend_uncached_impcache


	STATIC_ENTRY _objc_msgSend_uncached

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band r9 is the class to search

	stmfd	sp!, {r0-r3,r7,lr}
	add     r7, sp, #16
	sub     sp, #8			// align stack
	FP_SAVE
					// receiver already in r0
					// selector already in r1
	mov	r2, r9			// class to search

	MI_CALL_EXTERNAL(__class_lookupMethodAndLoadCache3)
	mov     r12, r0			// r12 = IMP

	movs	r9, #0			// r9=0, Z=1 for nonstret forwarding
	FP_RESTORE
	add     sp, #8			// align stack
	ldmfd	sp!, {r0-r3,r7,lr}
	bx	r12

	END_ENTRY _objc_msgSend_uncached


	STATIC_ENTRY _objc_msgSend_stret_uncached

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band r9 is the class to search
	
	stmfd	sp!, {r0-r3,r7,lr}
	add     r7, sp, #16
	sub     sp, #8			// align stack
	FP_SAVE

	mov 	r0, r1			// receiver
	mov 	r1, r2			// selector
	mov	r2, r9			// class to search

	MI_CALL_EXTERNAL(__class_lookupMethodAndLoadCache3)
	mov     r12, r0			// r12 = IMP

	movs	r9, #1			// r9=1, Z=0 for stret forwarding
	FP_RESTORE
	add     sp, #8			// align stack
	ldmfd	sp!, {r0-r3,r7,lr}
	bx	r12
	
	END_ENTRY _objc_msgSend_stret_uncached

	
/********************************************************************
*
* id _objc_msgForward(id self, SEL _cmd,...);
*
* _objc_msgForward and _objc_msgForward_stret are the externally-callable
*   functions returned by things like method_getImplementation().
* _objc_msgForward_impcache is the function pointer actually stored in
*   method caches.
*
********************************************************************/

	MI_EXTERN(__objc_forward_handler)
	MI_EXTERN(__objc_forward_stret_handler)
	
	STATIC_ENTRY   _objc_msgForward_impcache
	// Method cache version

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band Z is 0 (EQ) for normal, 1 (NE) for stret and/or super
	// Out-of-band r9 is 1 for stret, cls for super, cls|1 for super_stret
	// Note _objc_msgSend_uncached_impcache uses the same parameters

	MESSENGER_START
	nop
	MESSENGER_END_SLOW

	it	ne
	tstne	r9, #1
	beq	__objc_msgForward
	b	__objc_msgForward_stret
	
	END_ENTRY _objc_msgForward_impcache
	

	ENTRY   _objc_msgForward
	// Non-stret version

	MI_GET_EXTERN(r12, __objc_forward_handler)
	ldr	r12, [r12]
	bx	r12

	END_ENTRY _objc_msgForward


	ENTRY   _objc_msgForward_stret
	// Struct-return version

	MI_GET_EXTERN(r12, __objc_forward_stret_handler)
	ldr	r12, [r12]
	bx	r12

	END_ENTRY _objc_msgForward_stret


	ENTRY objc_msgSend_debug
	b	_objc_msgSend
	END_ENTRY objc_msgSend_debug

	ENTRY objc_msgSendSuper2_debug
	b	_objc_msgSendSuper2
	END_ENTRY objc_msgSendSuper2_debug

	ENTRY objc_msgSend_stret_debug
	b	_objc_msgSend_stret
	END_ENTRY objc_msgSend_stret_debug

	ENTRY objc_msgSendSuper2_stret_debug
	b	_objc_msgSendSuper2_stret
	END_ENTRY objc_msgSendSuper2_stret_debug


	ENTRY method_invoke
	// r1 is method triplet instead of SEL
	ldr	r12, [r1, #METHOD_IMP]
	ldr	r1, [r1, #METHOD_NAME]
	bx	r12
	END_ENTRY method_invoke


	ENTRY method_invoke_stret
	// r2 is method triplet instead of SEL
	ldr	r12, [r2, #METHOD_IMP]
	ldr	r2, [r2, #METHOD_NAME]
	bx	r12
	END_ENTRY method_invoke_stret


	STATIC_ENTRY _objc_ignored_method

	// self is already in a0
	bx	lr

	END_ENTRY _objc_ignored_method
	

.section __DATA,__objc_msg_break
.long 0
.long 0
	
#endif
