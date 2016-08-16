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

#include <TargetConditionals.h>
#if __x86_64__  &&  !TARGET_IPHONE_SIMULATOR

/********************************************************************
 ********************************************************************
 **
 **  objc-msg-x86_64.s - x86-64 code to support objc messaging.
 **
 ********************************************************************
 ********************************************************************/

/********************************************************************
* Data used by the ObjC runtime.
*
********************************************************************/

.data

// _objc_entryPoints and _objc_exitPoints are used by objc
// to get the critical regions for which method caches 
// cannot be garbage collected.

.align 4
.private_extern	_objc_entryPoints
_objc_entryPoints:
	.quad	_cache_getImp
	.quad	_objc_msgSend
	.quad	_objc_msgSend_fpret
	.quad	_objc_msgSend_fp2ret
	.quad	_objc_msgSend_stret
	.quad	_objc_msgSendSuper
	.quad	_objc_msgSendSuper_stret
	.quad	_objc_msgSendSuper2
	.quad	_objc_msgSendSuper2_stret
	.quad	0

.private_extern	_objc_exitPoints
_objc_exitPoints:
	.quad	LExit_cache_getImp
	.quad	LExit_objc_msgSend
	.quad	LExit_objc_msgSend_fpret
	.quad	LExit_objc_msgSend_fp2ret
	.quad	LExit_objc_msgSend_stret
	.quad	LExit_objc_msgSendSuper
	.quad	LExit_objc_msgSendSuper_stret
	.quad	LExit_objc_msgSendSuper2
	.quad	LExit_objc_msgSendSuper2_stret
	.quad	0


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
	.quad 4b
	.quad ENTER
	.text
.endmacro
.macro MESSENGER_END_FAST
4:
	.section __DATA,__objc_msg_break
	.quad 4b
	.quad FAST_EXIT
	.text
.endmacro
.macro MESSENGER_END_SLOW
4:
	.section __DATA,__objc_msg_break
	.quad 4b
	.quad SLOW_EXIT
	.text
.endmacro
.macro MESSENGER_END_NIL
4:
	.section __DATA,__objc_msg_break
	.quad 4b
	.quad NIL_EXIT
	.text
.endmacro


/********************************************************************
 * Recommended multi-byte NOP instructions
 * (Intel 64 and IA-32 Architectures Software Developer's Manual Volume 2B)
 ********************************************************************/
#define nop1 .byte 0x90
#define nop2 .byte 0x66,0x90
#define nop3 .byte 0x0F,0x1F,0x00
#define nop4 .byte 0x0F,0x1F,0x40,0x00
#define nop5 .byte 0x0F,0x1F,0x44,0x00,0x00
#define nop6 .byte 0x66,0x0F,0x1F,0x44,0x00,0x00
#define nop7 .byte 0x0F,0x1F,0x80,0x00,0x00,0x00,0x00
#define nop8 .byte 0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00
#define nop9 .byte 0x66,0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00

	
/********************************************************************
 * Harmless branch prefix hint for instruction alignment
 ********************************************************************/
	
#define PN .byte 0x2e


/********************************************************************
 * Names for parameter registers.
 ********************************************************************/

#define a1  rdi
#define a1d edi
#define a1b dil
#define a2  rsi
#define a2d esi
#define a2b sil
#define a3  rdx
#define a3d edx
#define a4  rcx
#define a4d ecx
#define a5  r8
#define a5d r8d
#define a6  r9
#define a6d r9d


/********************************************************************
 * Names for relative labels
 * DO NOT USE THESE LABELS ELSEWHERE
 * Reserved labels: 6: 7: 8: 9:
 ********************************************************************/
#define LCacheMiss 	6
#define LCacheMiss_f 	6f
#define LCacheMiss_b 	6b
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
#define FP2RET 2
#define GETIMP 3
#define STRET 4
#define SUPER 5
#define SUPER_STRET 6
#define SUPER2 7
#define SUPER2_STRET 8
	

/********************************************************************
 *
 * Structure definitions.
 *
 ********************************************************************/

// objc_super parameter to sendSuper
#define receiver 	0
#define class 		8

// Selected field offsets in class structure
// #define isa		0    USE GetIsa INSTEAD

// Method descriptor
#define method_name 	0
#define method_imp 	16

// typedef struct {
//	uint128_t floatingPointArgs[8];	// xmm0..xmm7
//	long linkageArea[4];		// r10, rax, ebp, ret
//	long registerArgs[6];		// a1..a6
//	long stackArgs[0];		// variable-size
// } *marg_list;
#define FP_AREA 0
#define LINK_AREA (FP_AREA+8*16)
#define REG_AREA (LINK_AREA+4*8)
#define STACK_AREA (REG_AREA+6*8)


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
	.align	6, 0x90
$0:
	.cfi_startproc
.endmacro

.macro STATIC_ENTRY
	.text
	.private_extern	$0
	.align	2, 0x90
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
LExit$0:
.endmacro


/////////////////////////////////////////////////////////////////////
//
// SaveRegisters
//
// Pushes a stack frame and saves all registers that might contain
// parameter values.
//
// On entry:
//		stack = ret
//
// On exit: 
//		%rsp is 16-byte aligned
//	
/////////////////////////////////////////////////////////////////////

.macro SaveRegisters

	push	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset rbp, -16
	
	mov	%rsp, %rbp
	.cfi_def_cfa_register rbp
	
	sub	$$0x80+8, %rsp		// +8 for alignment

	movdqa	%xmm0, -0x80(%rbp)
	push	%rax			// might be xmm parameter count
	movdqa	%xmm1, -0x70(%rbp)
	push	%a1
	movdqa	%xmm2, -0x60(%rbp)
	push	%a2
	movdqa	%xmm3, -0x50(%rbp)
	push	%a3
	movdqa	%xmm4, -0x40(%rbp)
	push	%a4
	movdqa	%xmm5, -0x30(%rbp)
	push	%a5
	movdqa	%xmm6, -0x20(%rbp)
	push	%a6
	movdqa	%xmm7, -0x10(%rbp)
	
.endmacro

/////////////////////////////////////////////////////////////////////
//
// RestoreRegisters
//
// Pops a stack frame pushed by SaveRegisters
//
// On entry:
//		%rbp unchanged since SaveRegisters
//
// On exit: 
//		stack = ret
//	
/////////////////////////////////////////////////////////////////////

.macro RestoreRegisters

	movdqa	-0x80(%rbp), %xmm0
	pop	%a6
	movdqa	-0x70(%rbp), %xmm1
	pop	%a5
	movdqa	-0x60(%rbp), %xmm2
	pop	%a4
	movdqa	-0x50(%rbp), %xmm3
	pop	%a3
	movdqa	-0x40(%rbp), %xmm4
	pop	%a2
	movdqa	-0x30(%rbp), %xmm5
	pop	%a1
	movdqa	-0x20(%rbp), %xmm6
	pop	%rax
	movdqa	-0x10(%rbp), %xmm7
	
	leave
	.cfi_def_cfa rsp, 8
	.cfi_same_value rbp

.endmacro


/////////////////////////////////////////////////////////////////////
//
// CacheLookup	return-type, caller
//
// Locate the implementation for a class in a selector's method cache.
//
// Takes: 
//	  $0 = NORMAL, FPRET, FP2RET, STRET, SUPER, SUPER_STRET, SUPER2, SUPER2_STRET, GETIMP
//	  a2 or a3 (STRET) = selector a.k.a. cache
//	  r11 = class to search
//
// On exit: r10 clobbered
//	    (found) calls or returns IMP, eq/ne/r11 set for forwarding
//	    (not found) jumps to LCacheMiss, class still in r11
//
/////////////////////////////////////////////////////////////////////

.macro CacheHit

	// CacheHit must always be preceded by a not-taken `jne` instruction
	// in order to set the correct flags for _objc_msgForward_impcache.

	// r10 = found bucket
	
.if $0 == GETIMP
	movq	8(%r10), %rax		// return imp
	leaq	__objc_msgSend_uncached_impcache(%rip), %r11
	cmpq	%rax, %r11
	jne 4f
	xorl	%eax, %eax		// don't return msgSend_uncached
4:	ret
.elseif $0 == NORMAL  ||  $0 == FPRET  ||  $0 == FP2RET
	// eq already set for forwarding by `jne`
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
	
.elseif $0 == SUPER
	movq	receiver(%a1), %a1	// load real receiver
	cmp	%r10, %r10		// set eq for non-stret forwarding
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
	
.elseif $0 == SUPER2
	movq	receiver(%a1), %a1	// load real receiver
	cmp	%r10, %r10		// set eq for non-stret forwarding
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
	
.elseif $0 == STRET
	test	%r10, %r10		// set ne for stret forwarding
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
	
.elseif $0 == SUPER_STRET
	movq	receiver(%a2), %a2	// load real receiver
	test	%r10, %r10		// set ne for stret forwarding
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
	
.elseif $0 == SUPER2_STRET
	movq	receiver(%a2), %a2	// load real receiver
	test	%r10, %r10		// set ne for stret forwarding
	MESSENGER_END_FAST
	jmp	*8(%r10)		// call imp
.else
.abort oops
.endif
	
.endmacro


.macro	CacheLookup
.if $0 != STRET  &&  $0 != SUPER_STRET  &&  $0 != SUPER2_STRET
	movq	%a2, %r10		// r10 = _cmd
.else
	movq	%a3, %r10		// r10 = _cmd
.endif
	andl	24(%r11), %r10d		// r10 = _cmd & class->cache.mask
	shlq	$$4, %r10		// r10 = offset = (_cmd & mask)<<4
	addq	16(%r11), %r10		// r10 = class->cache.buckets + offset

.if $0 != STRET  &&  $0 != SUPER_STRET  &&  $0 != SUPER2_STRET
	cmpq	(%r10), %a2		// if (bucket->sel != _cmd)
.else
	cmpq	(%r10), %a3		// if (bucket->sel != _cmd)
.endif
	jne 	1f			//     scan more
	// CacheHit must always be preceded by a not-taken `jne` instruction
	CacheHit $0			// call or return imp

1:
	// loop
	cmpq	$$1, (%r10)
	jbe	3f			// if (bucket->sel <= 1) wrap or miss

	addq	$$16, %r10		// bucket++
2:	
.if $0 != STRET  &&  $0 != SUPER_STRET  &&  $0 != SUPER2_STRET
	cmpq	(%r10), %a2		// if (bucket->sel != _cmd)
.else
	cmpq	(%r10), %a3		// if (bucket->sel != _cmd)
.endif
	jne 	1b			//     scan more
	// CacheHit must always be preceded by a not-taken `jne` instruction
	CacheHit $0			// call or return imp

3:
	// wrap or miss
	jb	LCacheMiss_f		// if (bucket->sel < 1) cache miss
	// wrap
	movq	8(%r10), %r10		// bucket->imp is really first bucket
	jmp 	2f

	// Clone scanning loop to miss instead of hang when cache is corrupt.
	// The slow path may detect any corruption and halt later.

1:
	// loop
	cmpq	$$1, (%r10)
	jbe	3f			// if (bucket->sel <= 1) wrap or miss

	addq	$$16, %r10		// bucket++
2:	
.if $0 != STRET  &&  $0 != SUPER_STRET  &&  $0 != SUPER2_STRET
	cmpq	(%r10), %a2		// if (bucket->sel != _cmd)
.else
	cmpq	(%r10), %a3		// if (bucket->sel != _cmd)
.endif
	jne 	1b			//     scan more
	// CacheHit must always be preceded by a not-taken `jne` instruction
	CacheHit $0			// call or return imp

3:
	// double wrap or miss
	jmp	LCacheMiss_f

.endmacro


/////////////////////////////////////////////////////////////////////
//
// MethodTableLookup classRegister, selectorRegister
//
// Takes:	$0 = class to search (a1 or a2 or r10 ONLY)
//		$1 = selector to search for (a2 or a3 ONLY)
// 		r11 = class to search
//
// On exit: imp in %r11
//
/////////////////////////////////////////////////////////////////////
.macro MethodTableLookup

	MESSENGER_END_SLOW
	
	SaveRegisters

	// _class_lookupMethodAndLoadCache3(receiver, selector, class)

	movq	$0, %a1
	movq	$1, %a2
	movq	%r11, %a3
	call	__class_lookupMethodAndLoadCache3

	// IMP is now in %rax
	movq	%rax, %r11

	RestoreRegisters

.endmacro

/////////////////////////////////////////////////////////////////////
//
// GetIsaFast return-type
// GetIsaSupport return-type
//
// Sets r11 = obj->isa. Consults the tagged isa table if necessary.
//
// Takes:	$0 = NORMAL or FPRET or FP2RET or STRET
//		a1 or a2 (STRET) = receiver
//
// On exit: 	r11 = receiver->isa
//		r10 is clobbered
//
/////////////////////////////////////////////////////////////////////

.macro GetIsaFast
.if $0 != STRET
	testb	$$1, %a1b
	PN
	jnz	LGetIsaSlow_f
	movq	$$0x00007ffffffffff8, %r11
	andq	(%a1), %r11
.else
	testb	$$1, %a2b
	PN
	jnz	LGetIsaSlow_f
	movq	$$0x00007ffffffffff8, %r11
	andq	(%a2), %r11
.endif
LGetIsaDone:	
.endmacro

.macro GetIsaSupport2
LGetIsaSlow:
	leaq	_objc_debug_taggedpointer_classes(%rip), %r11
.if $0 != STRET
	movl	%a1d, %r10d
.else
	movl	%a2d, %r10d
.endif
	andl	$$0xF, %r10d
	movq	(%r11, %r10, 8), %r11	// read isa from table
.endmacro
	
.macro GetIsaSupport
	GetIsaSupport2 $0
	jmp	LGetIsaDone_b
.endmacro

.macro GetIsa
	GetIsaFast $0
	jmp	LGetIsaDone_f
	GetIsaSupport2 $0
LGetIsaDone:
.endmacro

	
/////////////////////////////////////////////////////////////////////
//
// NilTest return-type
//
// Takes:	$0 = NORMAL or FPRET or FP2RET or STRET
//		%a1 or %a2 (STRET) = receiver
//
// On exit: 	Loads non-nil receiver in %a1 or %a2 (STRET), or returns zero.
//
// NilTestSupport return-type
//
// Takes:	$0 = NORMAL or FPRET or FP2RET or STRET
//		%a1 or %a2 (STRET) = receiver
//
// On exit: 	Loads non-nil receiver in %a1 or %a2 (STRET), or returns zero.
//
/////////////////////////////////////////////////////////////////////

.macro NilTest
.if $0 == SUPER  ||  $0 == SUPER_STRET
	error super dispatch does not test for nil
.endif

.if $0 != STRET
	testq	%a1, %a1
.else
	testq	%a2, %a2
.endif
	PN
	jz	LNilTestSlow_f
.endmacro

.macro NilTestSupport
	.align 3
LNilTestSlow:
.if $0 == FPRET
	fldz
.elseif $0 == FP2RET
	fldz
	fldz
.endif
.if $0 == STRET
	movq	%rdi, %rax
.else
	xorl	%eax, %eax
	xorl	%edx, %edx
	xorps	%xmm0, %xmm0
	xorps	%xmm1, %xmm1
.endif
	MESSENGER_END_NIL
	ret
.endmacro


/********************************************************************
 * IMP cache_getImp(Class cls, SEL sel)
 *
 * On entry:	a1 = class whose cache is to be searched
 *		a2 = selector to search for
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

	STATIC_ENTRY _cache_getImp

// do lookup
	movq	%a1, %r11		// move class to r11 for CacheLookup
	CacheLookup GETIMP		// returns IMP on success

LCacheMiss:
// cache miss, return nil
	xorl	%eax, %eax
	ret

LGetImpExit:
	END_ENTRY 	_cache_getImp


/********************************************************************
 *
 * id objc_msgSend(id self, SEL	_cmd,...);
 *
 ********************************************************************/
	
	.data
	.align 3
	.globl _objc_debug_taggedpointer_classes
_objc_debug_taggedpointer_classes:
	.fill 16, 8, 0

	ENTRY	_objc_msgSend
	MESSENGER_START

	NilTest	NORMAL

	GetIsaFast NORMAL		// r11 = self->isa
	CacheLookup NORMAL		// calls IMP on success

	NilTestSupport	NORMAL

	GetIsaSupport	NORMAL

// cache miss: go search the method lists
LCacheMiss:
	// isa still in r11
	MethodTableLookup %a1, %a2	// r11 = IMP
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSend

	
	ENTRY _objc_msgSend_fixup
	int3
	END_ENTRY _objc_msgSend_fixup

	
	STATIC_ENTRY _objc_msgSend_fixedup
	// Load _cmd from the message_ref
	movq	8(%a2), %a2
	jmp	_objc_msgSend
	END_ENTRY _objc_msgSend_fixedup

	
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
	
// search the cache (objc_super in %a1)
	movq	class(%a1), %r11	// class = objc_super->class
	CacheLookup SUPER		// calls IMP on success

// cache miss: go search the method lists
LCacheMiss:
	// class still in r11
	movq	receiver(%a1), %r10
	MethodTableLookup %r10, %a2	// r11 = IMP
	movq	receiver(%a1), %a1	// load real receiver
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp
	
	END_ENTRY	_objc_msgSendSuper


/********************************************************************
 * id objc_msgSendSuper2
 ********************************************************************/

	ENTRY _objc_msgSendSuper2
	MESSENGER_START
	
	// objc_super->class is superclass of class to search
	
// search the cache (objc_super in %a1)
	movq	class(%a1), %r11	// cls = objc_super->class
	movq	8(%r11), %r11		// cls = class->superclass
	CacheLookup SUPER2		// calls IMP on success

// cache miss: go search the method lists
LCacheMiss:
	// superclass still in r11
	movq	receiver(%a1), %r10
	MethodTableLookup %r10, %a2	// r11 = IMP
	movq	receiver(%a1), %a1	// load real receiver
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp
	
	END_ENTRY	_objc_msgSendSuper2

	
	ENTRY _objc_msgSendSuper2_fixup
	int3
	END_ENTRY _objc_msgSendSuper2_fixup

	
	STATIC_ENTRY _objc_msgSendSuper2_fixedup
	// Load _cmd from the message_ref
	movq	8(%a2), %a2
	jmp 	_objc_msgSendSuper2
	END_ENTRY _objc_msgSendSuper2_fixedup


/********************************************************************
 *
 * double objc_msgSend_fpret(id self, SEL _cmd,...);
 * Used for `long double` return only. `float` and `double` use objc_msgSend.
 *
 ********************************************************************/

	ENTRY	_objc_msgSend_fpret
	MESSENGER_START
	
	NilTest	FPRET

	GetIsaFast FPRET		// r11 = self->isa
	CacheLookup FPRET		// calls IMP on success

	NilTestSupport	FPRET

	GetIsaSupport	FPRET

// cache miss: go search the method lists
LCacheMiss:
	// isa still in r11
	MethodTableLookup %a1, %a2	// r11 = IMP
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSend_fpret

	
	ENTRY _objc_msgSend_fpret_fixup
	int3
	END_ENTRY _objc_msgSend_fpret_fixup

	
	STATIC_ENTRY _objc_msgSend_fpret_fixedup
	// Load _cmd from the message_ref
	movq	8(%a2), %a2
	jmp	_objc_msgSend_fpret
	END_ENTRY _objc_msgSend_fpret_fixedup


/********************************************************************
 *
 * double objc_msgSend_fp2ret(id self, SEL _cmd,...);
 * Used for `complex long double` return only.
 *
 ********************************************************************/

	ENTRY	_objc_msgSend_fp2ret
	MESSENGER_START
	
	NilTest	FP2RET

	GetIsaFast FP2RET		// r11 = self->isa
	CacheLookup FP2RET		// calls IMP on success

	NilTestSupport	FP2RET

	GetIsaSupport 	FP2RET
	
// cache miss: go search the method lists
LCacheMiss:
	// isa still in r11
	MethodTableLookup %a1, %a2	// r11 = IMP
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSend_fp2ret


	ENTRY _objc_msgSend_fp2ret_fixup
	int3
	END_ENTRY _objc_msgSend_fp2ret_fixup

	
	STATIC_ENTRY _objc_msgSend_fp2ret_fixedup
	// Load _cmd from the message_ref
	movq	8(%a2), %a2
	jmp	_objc_msgSend_fp2ret
	END_ENTRY _objc_msgSend_fp2ret_fixedup


/********************************************************************
 *
 * void	objc_msgSend_stret(void *st_addr, id self, SEL _cmd, ...);
 *
 * objc_msgSend_stret is the struct-return form of msgSend.
 * The ABI calls for %a1 to be used as the address of the structure
 * being returned, with the parameters in the succeeding locations.
 *
 * On entry:	%a1 is the address where the structure is returned,
 *		%a2 is the message receiver,
 *		%a3 is the selector
 ********************************************************************/

	ENTRY	_objc_msgSend_stret
	MESSENGER_START
	
	NilTest	STRET

	GetIsaFast STRET		// r11 = self->isa
	CacheLookup STRET		// calls IMP on success

	NilTestSupport	STRET

	GetIsaSupport	STRET

// cache miss: go search the method lists
LCacheMiss:
	// isa still in r11
	MethodTableLookup %a2, %a3	// r11 = IMP
	test	%r11, %r11		// set ne (stret) for forward; r11!=0
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSend_stret


	ENTRY _objc_msgSend_stret_fixup
	int3
	END_ENTRY _objc_msgSend_stret_fixup


	STATIC_ENTRY _objc_msgSend_stret_fixedup
	// Load _cmd from the message_ref
	movq	8(%a3), %a3
	jmp	_objc_msgSend_stret
	END_ENTRY _objc_msgSend_stret_fixedup


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
 * On entry:	%a1 is the address where the structure is returned,
 *		%a2 is the address of the objc_super structure,
 *		%a3 is the selector
 *
 ********************************************************************/

	ENTRY	_objc_msgSendSuper_stret
	MESSENGER_START
	
// search the cache (objc_super in %a2)
	movq	class(%a2), %r11	// class = objc_super->class
	CacheLookup SUPER_STRET		// calls IMP on success

// cache miss: go search the method lists
LCacheMiss:
	// class still in r11
	movq	receiver(%a2), %r10
	MethodTableLookup %r10, %a3	// r11 = IMP
	movq	receiver(%a2), %a2	// load real receiver
	test	%r11, %r11		// set ne (stret) for forward; r11!=0
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSendSuper_stret


/********************************************************************
 * id objc_msgSendSuper2_stret
 ********************************************************************/

	ENTRY	_objc_msgSendSuper2_stret
	MESSENGER_START
	
// search the cache (objc_super in %a2)
	movq	class(%a2), %r11	// class = objc_super->class
	movq	8(%r11), %r11		// class = class->superclass
	CacheLookup SUPER2_STRET	// calls IMP on success

// cache miss: go search the method lists
LCacheMiss:
	// superclass still in r11
	movq	receiver(%a2), %r10
	MethodTableLookup %r10, %a3	// r11 = IMP
	movq	receiver(%a2), %a2	// load real receiver
	test	%r11, %r11		// set ne (stret) for forward; r11!=0
	jmp	*%r11			// goto *imp

	END_ENTRY	_objc_msgSendSuper2_stret

	
	ENTRY _objc_msgSendSuper2_stret_fixup
	int3
	END_ENTRY _objc_msgSendSuper2_stret_fixup

	
	STATIC_ENTRY _objc_msgSendSuper2_stret_fixedup
	// Load _cmd from the message_ref
	movq	8(%a3), %a3
	jmp	_objc_msgSendSuper2_stret
	END_ENTRY _objc_msgSendSuper2_stret_fixedup


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
	// Out-of-band r11 is the searched class

	MESSENGER_START
	nop
	MESSENGER_END_SLOW
	
	jne	__objc_msgSend_stret_uncached
	jmp	__objc_msgSend_uncached

	END_ENTRY __objc_msgSend_uncached_impcache


	STATIC_ENTRY __objc_msgSend_uncached

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band r11 is the searched class

	// r11 is already the class to search
	MethodTableLookup %a1, %a2	// r11 = IMP
	cmp	%r11, %r11		// set eq (nonstret) for forwarding
	jmp	*%r11			// goto *imp

	END_ENTRY __objc_msgSend_uncached

	
	STATIC_ENTRY __objc_msgSend_stret_uncached
	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band r11 is the searched class

	// r11 is already the class to search
	MethodTableLookup %a2, %a3	// r11 = IMP
	test	%r11, %r11		// set ne (stret) for forward; r11!=0
	jmp	*%r11			// goto *imp

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

	STATIC_ENTRY	__objc_msgForward_impcache
	// Method cache version

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band condition register is NE for stret, EQ otherwise.

	MESSENGER_START
	nop
	MESSENGER_END_SLOW
	
	jne	__objc_msgForward_stret
	jmp	__objc_msgForward

	END_ENTRY	__objc_msgForward_impcache
	
	
	ENTRY	__objc_msgForward
	// Non-stret version

	movq	__objc_forward_handler(%rip), %r11
	jmp	*%r11

	END_ENTRY	__objc_msgForward


	ENTRY	__objc_msgForward_stret
	// Struct-return version

	movq	__objc_forward_stret_handler(%rip), %r11
	jmp	*%r11

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

	ENTRY _objc_msgSend_fp2ret_debug
	jmp	_objc_msgSend_fp2ret
	END_ENTRY _objc_msgSend_fp2ret_debug


	ENTRY _objc_msgSend_noarg
	jmp	_objc_msgSend
	END_ENTRY _objc_msgSend_noarg


	ENTRY _method_invoke

	movq	method_imp(%a2), %r11
	movq	method_name(%a2), %a2
	jmp	*%r11
	
	END_ENTRY _method_invoke


	ENTRY _method_invoke_stret

	movq	method_imp(%a3), %r11
	movq	method_name(%a3), %a3
	jmp	*%r11
	
	END_ENTRY _method_invoke_stret


	STATIC_ENTRY __objc_ignored_method

	movq	%a1, %rax
	ret
	
	END_ENTRY __objc_ignored_method
	

.section __DATA,__objc_msg_break
.quad 0
.quad 0


	// Workaround for Skype evil (rdar://19715989)

	.text
	.align 4
	.private_extern _map_images
	.private_extern _map_2_images
	.private_extern _hax
_hax:	
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
_map_images:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	jmp _map_2_images

#endif
