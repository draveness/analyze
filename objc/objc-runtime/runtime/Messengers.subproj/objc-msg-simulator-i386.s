/*
 * Copyright (c) 1999-2009 Apple Inc.  All Rights Reserved.
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

#include <TargetConditionals.h>
#if defined(__i386__)  &&  TARGET_IPHONE_SIMULATOR

#include "objc-config.h"

.data

// _objc_entryPoints and _objc_exitPoints are used by objc
// to get the critical regions for which method caches 
// cannot be garbage collected.

.align 2
.private_extern _objc_entryPoints
_objc_entryPoints:
	.long	_cache_getImp
	.long	_objc_msgSend
	.long	_objc_msgSend_fpret
	.long	_objc_msgSend_stret
	.long	_objc_msgSendSuper
	.long	_objc_msgSendSuper2
	.long	_objc_msgSendSuper_stret
	.long	_objc_msgSendSuper2_stret
	.long	0

.private_extern _objc_exitPoints
_objc_exitPoints:
	.long	LGetImpExit
	.long	LMsgSendExit
	.long	LMsgSendFpretExit
	.long	LMsgSendStretExit
	.long	LMsgSendSuperExit
	.long	LMsgSendSuper2Exit
	.long	LMsgSendSuperStretExit
	.long	LMsgSendSuper2StretExit
	.long	0


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
 * Reserved labels: 5: 6: 7: 8: 9:
 ********************************************************************/
#define LCacheMiss 	5
#define LCacheMiss_f 	5f
#define LCacheMiss_b 	5b
#define LNilTestDone 	6
#define LNilTestDone_f 	6f
#define LNilTestDone_b 	6b
#define LNilTestSlow 	7
#define LNilTestSlow_f 	7f
#define LNilTestSlow_b 	7b
#define LGetIsaDone 	8
#define LGetIsaDone_f 	8f
#define LGetIsaDone_b 	8b
#define LGetIsaSlow 	9
#define LGetIsaSlow_f 	9f
#define LGetIsaSlow_b 	9b

/********************************************************************
 * Macro parameters
 ********************************************************************/

#define NORMAL 0
#define FPRET 1
#define GETIMP 3
#define STRET 4
#define SUPER 5
#define SUPER_STRET 6


/********************************************************************
 *
 * Structure definitions.
 *
 ********************************************************************/

// Offsets from %esp
#define self            4
#define super           4
#define selector        8
#define marg_size       12
#define marg_list       16
#define first_arg       12

#define struct_addr     4

#define self_stret      8
#define super_stret     8
#define selector_stret  12
#define marg_size_stret 16
#define marg_list_stret 20

// objc_super parameter to sendSuper
#define receiver        0
#define class           4

// Selected field offsets in class structure
#define isa             0
#define superclass	4

// Method descriptor
#define method_name     0
#define method_imp      8


//////////////////////////////////////////////////////////////////////
//
// ENTRY		functionName
//
// Assembly directives to begin an exported function.
//
// Takes: functionName - name of the exported function
//////////////////////////////////////////////////////////////////////

.macro ENTRY
	.text
	.globl	$0
	.align	2, 0x90
$0:
	.cfi_startproc
.endmacro

.macro STATIC_ENTRY
	.text
	.private_extern	$0
	.align	4, 0x90
$0:
	.cfi_startproc
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

.macro END_ENTRY
	.cfi_endproc
.endmacro


/////////////////////////////////////////////////////////////////////
//
// CacheLookup	return-type
//
// Locate the implementation for a selector in a class method cache.
//
// Takes: 
//	  $0 = NORMAL, FPRET, STRET, SUPER, SUPER_STRET, GETIMP
//	  ecx = selector to search for
//	  edx = class to search
//
// On exit: ecx clobbered
//	    (found) calls or returns IMP in eax, eq/ne set for forwarding
//	    (not found) jumps to LCacheMiss, class still in edx
//
/////////////////////////////////////////////////////////////////////

.macro CacheHit

	// CacheHit must always be preceded by a not-taken `jne` instruction
	// in case the imp is _objc_msgForward_impcache.

.if $0 == GETIMP
	movl	4(%eax), %eax		// return imp
	call	4f
4:	pop	%edx
	leal	__objc_msgSend_uncached_impcache-4b(%edx), %edx
	cmpl	%edx, %eax
	jne	4f
	xor	%eax, %eax		// don't return msgSend_uncached
4:	ret
.elseif $0 == NORMAL  ||  $0 == FPRET
	// eq already set for forwarding by `jne`
	MESSENGER_END_FAST
	jmp	*4(%eax)		// call imp
.elseif $0 == STRET
	test	%eax, %eax		// set ne for stret forwarding
	MESSENGER_END_FAST
	jmp	*4(%eax)		// call imp
.elseif $0 == SUPER	
	// replace "super" arg with "receiver"
	movl	super(%esp), %ecx	// get super structure
	movl	receiver(%ecx), %ecx	// get messaged object
	movl	%ecx, super(%esp)	// make it the first argument
	cmp	%eax, %eax		// set eq for non-stret forwarding
	MESSENGER_END_FAST
	jmp	*4(%eax)		// call imp
.elseif $0 == SUPER_STRET
	// replace "super" arg with "receiver"
	movl	super_stret(%esp), %ecx	// get super structure
	movl	receiver(%ecx), %ecx	// get messaged object
	movl	%ecx, super_stret(%esp)	// make it the first argument
	test	%eax, %eax		// set ne for stret forwarding
	MESSENGER_END_FAST
	jmp	*4(%eax)		// call imp
.else
.abort oops
.endif

.endmacro


.macro	CacheLookup

	movzwl	12(%edx), %eax		// eax = mask
	andl	%ecx, %eax		// eax = SEL & mask
	shll	$$3, %eax		// eax = offset = (SEL & mask) * 8
	addl	8(%edx), %eax		// eax = bucket = cache->buckets+offset
	cmpl	(%eax), %ecx		// if (bucket->sel != SEL)
	jne	1f			//     scan more
	// The `jne` above sets flags for CacheHit
	CacheHit $0			// call or return imp

1:
	// loop
	cmpl	$$1, (%eax)
	jbe	3f			// if (bucket->sel <= 1) wrap or miss
	
	addl	$$8, %eax		// bucket++
2:
	cmpl	(%eax), %ecx		// if (bucket->sel != sel)
	jne	1b			//     scan more
	// The `jne` above sets flags for CacheHit
	CacheHit $0			// call or return imp

3:	
	// wrap or miss
	jb	LCacheMiss_f		// if (bucket->sel < 1) cache miss
	// wrap
	movl	4(%eax), %eax		// bucket->imp is really first bucket
	jmp	2f

	// Clone scanning loop to miss instead of hang when cache is corrupt.
	// The slow path may detect any corruption and halt later.

1:
	// loop
	cmpq	$$1, (%eax)
	jbe	3f			// if (bucket->sel <= 1) wrap or miss
	
	addl	$$8, %eax		// bucket++
2:
	cmpl	(%eax), %ecx		// if (bucket->sel != sel)
	jne	1b			//     scan more
	// The `jne` above sets flags for CacheHit
	CacheHit $0			// call or return imp

3:	
	// double wrap or miss
	jmp	LCacheMiss_f
	
.endmacro


/////////////////////////////////////////////////////////////////////
//
// MethodTableLookup
//
// Takes:
//	  $0 = NORMAL, FPRET, STRET, SUPER, SUPER_STRET
//	  eax = receiver
// 	  ecx = selector
// 	  edx = class to search
//
// On exit: calls IMP, eq/ne set for forwarding
//
/////////////////////////////////////////////////////////////////////

.macro MethodTableLookup
	MESSENGER_END_SLOW
	pushl	%ebp
	.cfi_def_cfa_offset 8
	.cfi_offset ebp, -8
	
	movl	%esp, %ebp
	.cfi_def_cfa_register ebp

	subl	$$(8+5*16), %esp

	movdqa  %xmm3, 4*16(%esp)
	movdqa  %xmm2, 3*16(%esp)
	movdqa  %xmm1, 2*16(%esp)
	movdqa  %xmm0, 1*16(%esp)
	
	movl	%edx, 8(%esp)		// class
	movl	%ecx, 4(%esp)		// selector
	movl	%eax, 0(%esp)		// receiver
	call	__class_lookupMethodAndLoadCache3

	// imp in eax

	movdqa  4*16(%esp), %xmm3
	movdqa  3*16(%esp), %xmm2
	movdqa  2*16(%esp), %xmm1
	movdqa  1*16(%esp), %xmm0

	leave
	.cfi_def_cfa esp, 4
	.cfi_same_value ebp

.if $0 == SUPER
	// replace "super" arg with "receiver"
	movl	super(%esp), %ecx	//  get super structure
	movl	receiver(%ecx), %ecx	//  get messaged object
	movl	%ecx, super(%esp)	//  make it the first argument
.elseif $0 == SUPER_STRET
	// replace "super" arg with "receiver"
	movl	super_stret(%esp), %ecx	//  get super structure
	movl	receiver(%ecx), %ecx	//  get messaged object
	movl	%ecx, super_stret(%esp)	//  make it the first argument
.endif

.if $0 == STRET  ||  $0 == SUPER_STRET
	// set ne (stret) for forwarding; eax != 0
	test	%eax, %eax
	jmp	*%eax		// call imp
.else
	// set eq (non-stret) for forwarding
	cmp	%eax, %eax
	jmp	*%eax		// call imp
.endif

.endmacro


/////////////////////////////////////////////////////////////////////
//
// NilTest return-type
//
// Takes:	$0 = NORMAL or FPRET or STRET
//		eax = receiver
//
// On exit: 	Loads non-nil receiver in eax and self(esp) or self_stret(esp),
//		or returns zero.
//
// NilTestSupport return-type
//
// Takes:	$0 = NORMAL or FPRET or STRET
//		eax = receiver
//
// On exit: 	Loads non-nil receiver in eax and self(esp) or self_stret(esp),
//		or returns zero.
//
/////////////////////////////////////////////////////////////////////

.macro NilTest
	testl	%eax, %eax
	jz	LNilTestSlow_f
LNilTestDone:
.endmacro

.macro NilTestSupport
	.align 3
LNilTestSlow:

.if $0 == FPRET
	fldz
	MESSENGER_END_NIL
	ret
.elseif $0 == STRET
	MESSENGER_END_NIL
	ret $$4
.elseif $0 == NORMAL
	// eax is already zero
	xorl	%edx, %edx
	xorps	%xmm0, %xmm0
	xorps	%xmm1, %xmm1
	MESSENGER_END_NIL
	ret
.endif
.endmacro


/********************************************************************
 * IMP _cache_getImp(Class cls, SEL sel)
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

	STATIC_ENTRY _cache_getImp

// load the class and selector
	movl    selector(%esp), %ecx
	movl	self(%esp), %edx

	CacheLookup GETIMP		// returns IMP on success

LCacheMiss:
// cache miss, return nil
	xorl    %eax, %eax
	ret

LGetImpExit:
	END_ENTRY _cache_getImp


/********************************************************************
 *
 * id objc_msgSend(id self, SEL	_cmd,...);
 *
 ********************************************************************/

	ENTRY	_objc_msgSend
	MESSENGER_START
	
	movl    selector(%esp), %ecx
	movl	self(%esp), %eax

	NilTest NORMAL

	movl	isa(%eax), %edx		// class = self->isa
	CacheLookup NORMAL		// calls IMP on success

	NilTestSupport NORMAL

LCacheMiss:
	// isa still in edx
	movl    selector(%esp), %ecx
	movl	self(%esp), %eax
	MethodTableLookup NORMAL	// calls IMP

LMsgSendExit:
	END_ENTRY	_objc_msgSend


/********************************************************************
 *
 * id objc_msgSendSuper(struct objc_super *super, SEL _cmd,...);
 *
 * struct objc_super {
 *		id	receiver;
 *		Class	class;
 * };
 ********************************************************************/

	ENTRY	_objc_msgSendSuper
	MESSENGER_START

	movl    selector(%esp), %ecx
	movl	super(%esp), %eax	// struct objc_super
	movl	class(%eax), %edx	// struct objc_super->class
	CacheLookup SUPER		// calls IMP on success

LCacheMiss:	
	// class still in edx
	movl    selector(%esp), %ecx
	movl	super(%esp), %eax
	movl	receiver(%eax), %eax
	MethodTableLookup SUPER		// calls IMP
	
LMsgSendSuperExit:
	END_ENTRY	_objc_msgSendSuper


	ENTRY	_objc_msgSendSuper2
	MESSENGER_START

	movl    selector(%esp), %ecx
	movl	super(%esp), %eax	// struct objc_super
	movl	class(%eax), %eax	// struct objc_super->class
	mov	superclass(%eax), %edx	// edx = objc_super->class->super_class
	CacheLookup SUPER		// calls IMP on success

LCacheMiss:
	// class still in edx
	movl    selector(%esp), %ecx
	movl	super(%esp), %eax
	movl	receiver(%eax), %eax
	MethodTableLookup SUPER		// calls IMP

LMsgSendSuper2Exit:
	END_ENTRY	_objc_msgSendSuper2


/********************************************************************
 *
 * double objc_msgSend_fpret(id self, SEL _cmd,...);
 *
 ********************************************************************/

	ENTRY	_objc_msgSend_fpret
	MESSENGER_START

	movl    selector(%esp), %ecx
	movl	self(%esp), %eax

	NilTest FPRET

	movl	isa(%eax), %edx		// class = self->isa
	CacheLookup FPRET		// calls IMP on success

	NilTestSupport FPRET
	
LCacheMiss:	
	// class still in edx
	movl    selector(%esp), %ecx
	movl	self(%esp), %eax
	MethodTableLookup FPRET		// calls IMP

LMsgSendFpretExit:
	END_ENTRY	_objc_msgSend_fpret
	

/********************************************************************
 *
 * void	objc_msgSend_stret(void *st_addr	, id self, SEL _cmd, ...);
 *
 *
 * objc_msgSend_stret is the struct-return form of msgSend.
 * The ABI calls for (sp+4) to be used as the address of the structure
 * being returned, with the parameters in the succeeding locations.
 *
 * On entry:	(sp+4)is the address where the structure is returned,
 *		(sp+8) is the message receiver,
 *		(sp+12) is the selector
 ********************************************************************/

	ENTRY	_objc_msgSend_stret
	MESSENGER_START

	movl	selector_stret(%esp), %ecx
	movl	self_stret(%esp), %eax

	NilTest STRET

	movl	isa(%eax), %edx		// class = self->isa
	CacheLookup STRET		// calls IMP on success

	NilTestSupport STRET
	
LCacheMiss:
	// class still in edx
	movl	selector_stret(%esp), %ecx
	movl	self_stret(%esp), %eax
	MethodTableLookup STRET		// calls IMP

LMsgSendStretExit:
	END_ENTRY	_objc_msgSend_stret

	
/********************************************************************
 *
 * void objc_msgSendSuper_stret(void *st_addr, struct objc_super *super, SEL _cmd, ...);
 *
 * struct objc_super {
 *		id	receiver;
 *		Class	class;
 * };
 *
 * objc_msgSendSuper_stret is the struct-return form of msgSendSuper.
 * The ABI calls for (sp+4) to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry:	(sp+4)is the address where the structure is returned,
 *		(sp+8) is the address of the objc_super structure,
 *		(sp+12) is the selector
 *
 ********************************************************************/

	ENTRY	_objc_msgSendSuper_stret
	MESSENGER_START

	movl	selector_stret(%esp), %ecx
	movl	super_stret(%esp), %eax	// struct objc_super
	movl	class(%eax), %edx	// struct objc_super->class
	CacheLookup SUPER_STRET		// calls IMP on success

LCacheMiss:
	// class still in edx
	movl	selector_stret(%esp), %ecx
	movl	super_stret(%esp), %eax
	movl	receiver(%eax), %eax
	MethodTableLookup SUPER_STRET	// calls IMP

LMsgSendSuperStretExit:
	END_ENTRY	_objc_msgSendSuper_stret


	ENTRY	_objc_msgSendSuper2_stret
	MESSENGER_START

	movl	selector_stret(%esp), %ecx
	movl	super_stret(%esp), %eax	// struct objc_super
	movl	class(%eax), %eax	// struct objc_super->class
	mov	superclass(%eax), %edx	// edx = objc_super->class->super_class
	CacheLookup SUPER_STRET		// calls IMP on success

// cache miss: go search the method lists
LCacheMiss:
	// class still in edx
	movl	selector_stret(%esp), %ecx
	movl	super_stret(%esp), %eax
	movl	receiver(%eax), %eax
	MethodTableLookup SUPER_STRET	// calls IMP

LMsgSendSuper2StretExit:
	END_ENTRY	_objc_msgSendSuper2_stret


/********************************************************************
 *
 * _objc_msgSend_uncached_impcache
 * _objc_msgSend_uncached
 * _objc_msgSend_stret_uncached
 * 
 * Used to erase method cache entries in-place by 
 * bouncing them to the uncached lookup.
 *
 ********************************************************************/
	
	STATIC_ENTRY __objc_msgSend_uncached_impcache
	// Method cache version

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band condition register is NE for stret, EQ otherwise.
	// Out-of-band edx is the searched class

	MESSENGER_START
	nop
	MESSENGER_END_SLOW
	
	jne	__objc_msgSend_stret_uncached
	jmp	__objc_msgSend_uncached

	END_ENTRY __objc_msgSend_uncached_impcache


	STATIC_ENTRY __objc_msgSend_uncached

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band edx is the searched class

	// edx is already the class to search
	movl    selector(%esp), %ecx
	MethodTableLookup NORMAL	// calls IMP

	END_ENTRY __objc_msgSend_uncached

	
	STATIC_ENTRY __objc_msgSend_stret_uncached

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band edx is the searched class

	// edx is already the class to search
	movl    selector_stret(%esp), %ecx
	MethodTableLookup STRET		// calls IMP

	END_ENTRY __objc_msgSend_stret_uncached


	
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

	.non_lazy_symbol_pointer
L_forward_handler:
	.indirect_symbol __objc_forward_handler
	.long 0
L_forward_stret_handler:
	.indirect_symbol __objc_forward_stret_handler
	.long 0

	STATIC_ENTRY	__objc_msgForward_impcache
	// Method cache version
	
	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band condition register is NE for stret, EQ otherwise.

	MESSENGER_START
	nop
	MESSENGER_END_SLOW

	jne	__objc_msgForward_stret
	jmp	__objc_msgForward
	
	END_ENTRY	_objc_msgForward_impcache

	
	ENTRY	__objc_msgForward
	// Non-struct return version

	call	1f
1:	popl	%edx
	movl	L_forward_handler-1b(%edx), %edx
	jmp	*(%edx)

	END_ENTRY	__objc_msgForward


	ENTRY	__objc_msgForward_stret
	// Struct return version

	call	1f
1:	popl	%edx
	movl	L_forward_stret_handler-1b(%edx), %edx
	jmp	*(%edx)

	END_ENTRY	__objc_msgForward_stret


	ENTRY _objc_msgSend_debug
	jmp	_objc_msgSend
	END_ENTRY _objc_msgSend_debug

	ENTRY _objc_msgSendSuper2_debug
	jmp	_objc_msgSendSuper2
	END_ENTRY _objc_msgSendSuper2_debug

	ENTRY _objc_msgSend_stret_debug
	jmp	_objc_msgSend_stret
	END_ENTRY _objc_msgSend_stret_debug

	ENTRY _objc_msgSendSuper2_stret_debug
	jmp	_objc_msgSendSuper2_stret
	END_ENTRY _objc_msgSendSuper2_stret_debug

	ENTRY _objc_msgSend_fpret_debug
	jmp	_objc_msgSend_fpret
	END_ENTRY _objc_msgSend_fpret_debug


	ENTRY _objc_msgSend_noarg
	jmp	_objc_msgSend
	END_ENTRY _objc_msgSend_noarg
	

	ENTRY _method_invoke

	movl	selector(%esp), %ecx
	movl	method_name(%ecx), %edx
	movl	method_imp(%ecx), %eax
	movl	%edx, selector(%esp)
	jmp	*%eax
	
	END_ENTRY _method_invoke


	ENTRY _method_invoke_stret

	movl	selector_stret(%esp), %ecx
	movl	method_name(%ecx), %edx
	movl	method_imp(%ecx), %eax
	movl	%edx, selector_stret(%esp)
	jmp	*%eax
	
	END_ENTRY _method_invoke_stret

#if DEBUG
	STATIC_ENTRY __objc_ignored_method
	
	movl	self(%esp), %eax
	ret
	
	END_ENTRY __objc_ignored_method
#endif
	

.section __DATA,__objc_msg_break
.long 0
.long 0

#endif
