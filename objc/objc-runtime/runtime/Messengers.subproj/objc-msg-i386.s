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
#if defined(__i386__)  &&  !TARGET_IPHONE_SIMULATOR

/********************************************************************
 ********************************************************************
 **
 **  objc-msg-i386.s - i386 code to support objc messaging.
 **
 ********************************************************************
 ********************************************************************/

// for kIgnore
#include "objc-config.h"


/********************************************************************
* Data used by the ObjC runtime.
*
********************************************************************/

.data

// _objc_entryPoints and _objc_exitPoints are used by objc
// to get the critical regions for which method caches 
// cannot be garbage collected.

.align 2
.private_extern _objc_entryPoints
_objc_entryPoints:
	.long	__cache_getImp
	.long	__cache_getMethod
	.long	_objc_msgSend
	.long	_objc_msgSend_fpret
	.long	_objc_msgSend_stret
	.long	_objc_msgSendSuper
	.long	_objc_msgSendSuper_stret
	.long	0

.private_extern _objc_exitPoints
_objc_exitPoints:
	.long	LGetImpExit
	.long	LGetMethodExit
	.long	LMsgSendExit
	.long	LMsgSendFpretExit
	.long	LMsgSendStretExit
	.long	LMsgSendSuperExit
	.long	LMsgSendSuperStretExit
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
 *
 * Common offsets.
 *
 ********************************************************************/

	self            = 4
	super           = 4
	selector        = 8
	marg_size       = 12
	marg_list       = 16
	first_arg       = 12

	struct_addr     = 4

	self_stret      = 8
	super_stret     = 8
	selector_stret  = 12
	marg_size_stret = 16
	marg_list_stret = 20


/********************************************************************
 *
 * Structure definitions.
 *
 ********************************************************************/

// objc_super parameter to sendSuper
	receiver        = 0
	class           = 4

// Selected field offsets in class structure
	isa             = 0
	cache           = 32

// Method descriptor
	method_name     = 0
	method_imp      = 8

// Cache header
	mask            = 0
	occupied        = 4
	buckets         = 8		// variable length array

#if defined(OBJC_INSTRUMENTED)
// Cache instrumentation data, follows buckets
	hitCount        = 0
	hitProbes       = hitCount + 4
	maxHitProbes    = hitProbes + 4
	missCount       = maxHitProbes + 4
	missProbes      = missCount + 4
	maxMissProbes   = missProbes + 4
	flushCount      = maxMissProbes + 4
	flushedEntries  = flushCount + 4

// Buckets in CacheHitHistogram and CacheMissHistogram
	CACHE_HISTOGRAM_SIZE = 512
#endif


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
	.align	4, 0x90
$0:
.endmacro

.macro STATIC_ENTRY
	.text
	.private_extern	$0
	.align	4, 0x90
$0:
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
.endmacro

//////////////////////////////////////////////////////////////////////
//
// CALL_MCOUNTER
//
// Calls mcount() profiling routine. Must be called immediately on
// function entry, before any prologue executes.
//
//////////////////////////////////////////////////////////////////////

.macro CALL_MCOUNTER
#ifdef PROFILE
	// Current stack contents: ret
	pushl	%ebp
	movl	%esp,%ebp
	subl	$$8,%esp
	// Current stack contents: ret, ebp, pad, pad
	call	mcount
	movl	%ebp,%esp
	popl	%ebp
#endif
.endmacro


/////////////////////////////////////////////////////////////////////
//
//
// CacheLookup	WORD_RETURN | STRUCT_RETURN, MSG_SEND | MSG_SENDSUPER | CACHE_GET, cacheMissLabel
//
// Locate the implementation for a selector in a class method cache.
//
// Takes: WORD_RETURN	(first parameter is at sp+4)
//        STRUCT_RETURN	(struct address is at sp+4, first parameter at sp+8)
//        MSG_SEND	(first parameter is receiver)
//        MSG_SENDSUPER	(first parameter is address of objc_super structure)
//        CACHE_GET	(first parameter is class; return method triplet)
//        selector in %ecx
//        class to search in %edx
//
//	  cacheMissLabel = label to branch to iff method is not cached
//
// On exit: (found) MSG_SEND and MSG_SENDSUPER: return imp in eax
//          (found) CACHE_GET: return method triplet in eax
//          (not found) jumps to cacheMissLabel
//	
/////////////////////////////////////////////////////////////////////


// Values to specify to method lookup macros whether the return type of
// the method is word or structure.
WORD_RETURN   = 0
STRUCT_RETURN = 1

// Values to specify to method lookup macros whether the first argument
// is an object/class reference or a 'objc_super' structure.
MSG_SEND      = 0	// first argument is receiver, search the isa
MSG_SENDSUPER = 1	// first argument is objc_super, search the class
CACHE_GET     = 2	// first argument is class, search that class

.macro	CacheLookup

// load variables and save caller registers.

	pushl	%edi			// save scratch register
	movl	cache(%edx), %edi	// cache = class->cache
	pushl	%esi			// save scratch register

#if defined(OBJC_INSTRUMENTED)
	pushl	%ebx			// save non-volatile register
	pushl	%eax			// save cache pointer
	xorl	%ebx, %ebx		// probeCount = 0
#endif
	movl	mask(%edi), %esi		// mask = cache->mask
	movl	%ecx, %edx		// index = selector
	shrl	$$2, %edx		// index = selector >> 2

// search the receiver's cache
// ecx = selector
// edi = cache
// esi = mask
// edx = index
// eax = method (soon)
LMsgSendProbeCache_$0_$1_$2:
#if defined(OBJC_INSTRUMENTED)
	addl	$$1, %ebx			// probeCount += 1
#endif
	andl	%esi, %edx		// index &= mask
	movl	buckets(%edi, %edx, 4), %eax	// meth = cache->buckets[index]

	testl	%eax, %eax		// check for end of bucket
	je	LMsgSendCacheMiss_$0_$1_$2	// go to cache miss code
	cmpl	method_name(%eax), %ecx	// check for method name match
	je	LMsgSendCacheHit_$0_$1_$2	// go handle cache hit
	addl	$$1, %edx			// bump index ...
	jmp	LMsgSendProbeCache_$0_$1_$2 // ... and loop

// not found in cache: restore state and go to callers handler
LMsgSendCacheMiss_$0_$1_$2:
#if defined(OBJC_INSTRUMENTED)
	popl	%edx			// retrieve cache pointer
	movl	mask(%edx), %esi		// mask = cache->mask
	testl	%esi, %esi		// a mask of zero is only for the...
	je	LMsgSendMissInstrumentDone_$0_$1_$2	// ... emptyCache, do not record anything

	// locate and update the CacheInstrumentation structure
	addl	$$1, %esi			// entryCount = mask + 1
	shll	$$2, %esi		// tableSize = entryCount * sizeof(entry)
	addl	$buckets, %esi		// offset = buckets + tableSize
	addl	%edx, %esi		// cacheData = &cache->buckets[mask+1]

	movl	missCount(%esi), %edi	// 
	addl	$$1, %edi			// 
	movl	%edi, missCount(%esi)	// cacheData->missCount += 1
	movl	missProbes(%esi), %edi	// 
	addl	%ebx, %edi		// 
	movl	%edi, missProbes(%esi)	// cacheData->missProbes += probeCount
	movl	maxMissProbes(%esi), %edi// if (cacheData->maxMissProbes < probeCount)
	cmpl	%ebx, %edi		// 
	jge	LMsgSendMaxMissProbeOK_$0_$1_$2	// 
	movl	%ebx, maxMissProbes(%esi)// cacheData->maxMissProbes = probeCount
LMsgSendMaxMissProbeOK_$0_$1_$2:

	// update cache miss probe histogram
	cmpl	$CACHE_HISTOGRAM_SIZE, %ebx	// pin probeCount to max index
	jl	LMsgSendMissHistoIndexSet_$0_$1_$2
	movl	$(CACHE_HISTOGRAM_SIZE-1), %ebx
LMsgSendMissHistoIndexSet_$0_$1_$2:
	LEA_STATIC_DATA	%esi, _CacheMissHistogram, EXTERNAL_SYMBOL
	shll	$$2, %ebx		// convert probeCount to histogram index
	addl	%ebx, %esi		// calculate &CacheMissHistogram[probeCount<<2]
	movl	0(%esi), %edi		// get current tally
	addl	$$1, %edi			// 
	movl	%edi, 0(%esi)		// tally += 1
LMsgSendMissInstrumentDone_$0_$1_$2:
	popl	%ebx			// restore non-volatile register
#endif

.if $0 == WORD_RETURN			// Regular word return
.if $1 == MSG_SEND			// MSG_SEND
	popl	%esi			//  restore callers register
	popl	%edi			//  restore callers register
	movl	self(%esp), %edx	//  get messaged object
	movl	isa(%edx), %eax		//  get objects class
.elseif $1 == MSG_SENDSUPER		// MSG_SENDSUPER
	// replace "super" arg with "receiver"
	movl	super+8(%esp), %edi	//  get super structure
	movl	receiver(%edi), %edx	//  get messaged object
	movl	%edx, super+8(%esp)	//  make it the first argument
	movl	class(%edi), %eax	//  get messaged class
	popl	%esi			//  restore callers register
	popl	%edi			//  restore callers register
.else					// CACHE_GET
	popl	%esi			//  restore callers register
	popl	%edi			//  restore callers register
.endif
.else					// Struct return
.if $1 == MSG_SEND			// MSG_SEND (stret)
	popl	%esi			//  restore callers register
	popl	%edi			//  restore callers register
	movl	self_stret(%esp), %edx	//  get messaged object
	movl	isa(%edx), %eax		//  get objects class
.elseif $1 == MSG_SENDSUPER		// MSG_SENDSUPER (stret)
	// replace "super" arg with "receiver"
	movl	super_stret+8(%esp), %edi//  get super structure
	movl	receiver(%edi), %edx	//  get messaged object
	movl	%edx, super_stret+8(%esp)//  make it the first argument
	movl	class(%edi), %eax	//  get messaged class
	popl	%esi			//  restore callers register
	popl	%edi			//  restore callers register
.else					// CACHE_GET
	!! This should not happen.
.endif
.endif

					// edx = receiver
					// ecx = selector
					// eax = class
	jmp	$2			// go to callers handler

// eax points to matching cache entry
	.align	4, 0x90
LMsgSendCacheHit_$0_$1_$2:
#if defined(OBJC_INSTRUMENTED)
	popl	%edx			// retrieve cache pointer
	movl	mask(%edx), %esi		// mask = cache->mask
	testl	%esi, %esi		// a mask of zero is only for the...
	je	LMsgSendHitInstrumentDone_$0_$1_$2	// ... emptyCache, do not record anything

	// locate and update the CacheInstrumentation structure
	addl	$$1, %esi			// entryCount = mask + 1
	shll	$$2, %esi		// tableSize = entryCount * sizeof(entry)
	addl	$buckets, %esi		// offset = buckets + tableSize
	addl	%edx, %esi		// cacheData = &cache->buckets[mask+1]

	movl	hitCount(%esi), %edi
	addl	$$1, %edi
	movl	%edi, hitCount(%esi)	// cacheData->hitCount += 1
	movl	hitProbes(%esi), %edi
	addl	%ebx, %edi
	movl	%edi, hitProbes(%esi)	// cacheData->hitProbes += probeCount
	movl	maxHitProbes(%esi), %edi// if (cacheData->maxHitProbes < probeCount)
	cmpl	%ebx, %edi
	jge	LMsgSendMaxHitProbeOK_$0_$1_$2
	movl	%ebx, maxHitProbes(%esi)// cacheData->maxHitProbes = probeCount
LMsgSendMaxHitProbeOK_$0_$1_$2:

	// update cache hit probe histogram
	cmpl	$CACHE_HISTOGRAM_SIZE, %ebx	// pin probeCount to max index
	jl	LMsgSendHitHistoIndexSet_$0_$1_$2
	movl	$(CACHE_HISTOGRAM_SIZE-1), %ebx
LMsgSendHitHistoIndexSet_$0_$1_$2:
	LEA_STATIC_DATA	%esi, _CacheHitHistogram, EXTERNAL_SYMBOL
	shll	$$2, %ebx		// convert probeCount to histogram index
	addl	%ebx, %esi		// calculate &CacheHitHistogram[probeCount<<2]
	movl	0(%esi), %edi		// get current tally
	addl	$$1, %edi			// 
	movl	%edi, 0(%esi)		// tally += 1
LMsgSendHitInstrumentDone_$0_$1_$2:
	popl	%ebx			// restore non-volatile register
#endif

// load implementation address, restore state, and we're done
.if $1 == CACHE_GET
	// method triplet is already in eax
.else
	movl	method_imp(%eax), %eax	// imp = method->method_imp
.endif

.if $0 == WORD_RETURN			// Regular word return
.if $1 == MSG_SENDSUPER			// MSG_SENDSUPER
	// replace "super" arg with "self"
	movl	super+8(%esp), %edi
	movl	receiver(%edi), %esi
	movl	%esi, super+8(%esp)
.endif
.else					// Struct return
.if $1 == MSG_SENDSUPER			// MSG_SENDSUPER (stret)
	// replace "super" arg with "self"
	movl	super_stret+8(%esp), %edi
	movl	receiver(%edi), %esi
	movl	%esi, super_stret+8(%esp)
.endif
.endif

	// restore caller registers
	popl	%esi
	popl	%edi
.endmacro


/////////////////////////////////////////////////////////////////////
//
// MethodTableLookup WORD_RETURN | STRUCT_RETURN, MSG_SEND | MSG_SENDSUPER
//
// Takes: WORD_RETURN	(first parameter is at sp+4)
//	  STRUCT_RETURN	(struct address is at sp+4, first parameter at sp+8)
// 	  MSG_SEND	(first parameter is receiver)
//	  MSG_SENDSUPER	(first parameter is address of objc_super structure)
//
//	  edx = receiver
// 	  ecx = selector
// 	  eax = class
//        (all set by CacheLookup's miss case)
// 
// Stack must be at 0xXXXXXXXc on entrance.
//
// On exit:  esp unchanged
//           imp in eax
//
/////////////////////////////////////////////////////////////////////

.macro MethodTableLookup
	MESSENGER_END_SLOW

	// stack has return address and nothing else
	subl	$$(12+5*16), %esp

	movdqa  %xmm3, 4*16(%esp)
	movdqa  %xmm2, 3*16(%esp)
	movdqa  %xmm1, 2*16(%esp)
	movdqa  %xmm0, 1*16(%esp)
	
	movl	%eax, 8(%esp)		// class
	movl	%ecx, 4(%esp)		// selector
	movl	%edx, 0(%esp)		// receiver
	call	__class_lookupMethodAndLoadCache3

	movdqa  4*16(%esp), %xmm3
	movdqa  3*16(%esp), %xmm2
	movdqa  2*16(%esp), %xmm1
	movdqa  1*16(%esp), %xmm0

	addl    $$(12+5*16), %esp	// pop parameters
.endmacro


/********************************************************************
 * Method _cache_getMethod(Class cls, SEL sel, IMP msgForward_internal_imp)
 *
 * If found, returns method triplet pointer.
 * If not found, returns NULL.
 *
 * NOTE: _cache_getMethod never returns any cache entry whose implementation
 * is _objc_msgForward_impcache. It returns 1 instead. This prevents thread-
 * safety and memory management bugs in _class_lookupMethodAndLoadCache. 
 * See _class_lookupMethodAndLoadCache for details.
 *
 * _objc_msgForward_impcache is passed as a parameter because it's more 
 * efficient to do the (PIC) lookup once in the caller than repeatedly here.
 ********************************************************************/
        
	STATIC_ENTRY __cache_getMethod

// load the class and selector
	movl	selector(%esp), %ecx
	movl	self(%esp), %edx

// do lookup
	CacheLookup WORD_RETURN, CACHE_GET, LGetMethodMiss

// cache hit, method triplet in %eax
	movl    first_arg(%esp), %ecx   // check for _objc_msgForward_impcache
	cmpl    method_imp(%eax), %ecx  // if (imp==_objc_msgForward_impcache)
	je      1f                      //     return (Method)1
	ret                             // else return method triplet address
1:	movl	$1, %eax
	ret

LGetMethodMiss:
// cache miss, return nil
	xorl    %eax, %eax      // zero %eax
	ret

LGetMethodExit:
	END_ENTRY __cache_getMethod


/********************************************************************
 * IMP _cache_getImp(Class cls, SEL sel)
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

	STATIC_ENTRY __cache_getImp

// load the class and selector
	movl    selector(%esp), %ecx
	movl	self(%esp), %edx

// do lookup
	CacheLookup WORD_RETURN, CACHE_GET, LGetImpMiss

// cache hit, method triplet in %eax
	movl    method_imp(%eax), %eax  // return method imp
	ret

LGetImpMiss:
// cache miss, return nil
	xorl    %eax, %eax      // zero %eax
	ret

LGetImpExit:
	END_ENTRY __cache_getImp


/********************************************************************
 *
 * id objc_msgSend(id self, SEL	_cmd,...);
 *
 ********************************************************************/

	ENTRY	_objc_msgSend
	MESSENGER_START
	CALL_MCOUNTER

// load receiver and selector
	movl    selector(%esp), %ecx
	movl	self(%esp), %eax

// check whether selector is ignored
	cmpl    $ kIgnore, %ecx
	je      LMsgSendDone		// return self from %eax

// check whether receiver is nil 
	testl	%eax, %eax
	je	LMsgSendNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendReceiverOk:
	movl	isa(%eax), %edx		// class = self->isa
	CacheLookup WORD_RETURN, MSG_SEND, LMsgSendCacheMiss
	xor	%edx, %edx		// set nonstret for msgForward_internal
	MESSENGER_END_FAST
	jmp	*%eax

// cache miss: go search the method lists
LMsgSendCacheMiss:
	MethodTableLookup WORD_RETURN, MSG_SEND
	xor	%edx, %edx		// set nonstret for msgForward_internal
	jmp	*%eax			// goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendNilSelf:
	// %eax is already zero
	movl	$0,%edx
	xorps	%xmm0, %xmm0
LMsgSendDone:
	MESSENGER_END_NIL
	ret

// guaranteed non-nil entry point (disabled for now)
// .globl _objc_msgSendNonNil
// _objc_msgSendNonNil:
// 	movl	self(%esp), %eax
// 	jmp     LMsgSendReceiverOk

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
	CALL_MCOUNTER

// load selector and class to search
	movl	super(%esp), %eax	// struct objc_super
	movl    selector(%esp), %ecx
	movl	class(%eax), %edx	// struct objc_super->class

// check whether selector is ignored
	cmpl    $ kIgnore, %ecx
	je      LMsgSendSuperIgnored	// return self from %eax

// search the cache (class in %edx)
	CacheLookup WORD_RETURN, MSG_SENDSUPER, LMsgSendSuperCacheMiss
	xor	%edx, %edx		// set nonstret for msgForward_internal
	MESSENGER_END_FAST
	jmp	*%eax			// goto *imp

// cache miss: go search the method lists
LMsgSendSuperCacheMiss:
	MethodTableLookup WORD_RETURN, MSG_SENDSUPER
	xor	%edx, %edx		// set nonstret for msgForward_internal
	jmp	*%eax			// goto *imp

// ignored selector: return self
LMsgSendSuperIgnored:
	movl	super(%esp), %eax
	movl    receiver(%eax), %eax
	MESSENGER_END_NIL
	ret
	
LMsgSendSuperExit:
	END_ENTRY	_objc_msgSendSuper

/********************************************************************
 * id objc_msgSendv(id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * On entry:
 *		(sp+4)  is the message receiver,
 *		(sp+8)	is the selector,
 *		(sp+12) is the size of the marg_list, in bytes,
 *		(sp+16) is the address of the marg_list
 *
 ********************************************************************/

	ENTRY	_objc_msgSendv

#if defined(KERNEL)
	trap				// _objc_msgSendv is not for the kernel
#else
	pushl	%ebp
	movl	%esp, %ebp
	// stack is currently aligned assuming no extra arguments
	movl	(marg_list+4)(%ebp), %edx
	addl	$8, %edx			// skip self & selector
	movl	(marg_size+4)(%ebp), %ecx
	subl    $8, %ecx			// skip self & selector
	shrl	$2, %ecx
	je      LMsgSendvArgsOK

	// %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
	movl    %ecx, %eax			// 16-byte align stack
	andl    $3, %eax
	shll    $2, %eax
	subl    $16, %esp
	addl    %eax, %esp

LMsgSendvArgLoop:
	decl	%ecx
	movl	0(%edx, %ecx, 4), %eax
	pushl	%eax
	jg	LMsgSendvArgLoop

LMsgSendvArgsOK:
	movl	(selector+4)(%ebp), %ecx
	pushl	%ecx
	movl	(self+4)(%ebp),%ecx
	pushl	%ecx
	call	_objc_msgSend
	movl	%ebp,%esp
	popl	%ebp

	ret
#endif
	END_ENTRY	_objc_msgSendv

/********************************************************************
 *
 * double objc_msgSend_fpret(id self, SEL _cmd,...);
 *
 ********************************************************************/

	ENTRY	_objc_msgSend_fpret
	MESSENGER_START
	CALL_MCOUNTER

// load receiver and selector
	movl    selector(%esp), %ecx
	movl	self(%esp), %eax

// check whether selector is ignored
	cmpl    $ kIgnore, %ecx
	je      LMsgSendFpretDone	// return self from %eax

// check whether receiver is nil 
	testl	%eax, %eax
	je	LMsgSendFpretNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendFpretReceiverOk:
	movl	isa(%eax), %edx		// class = self->isa
	CacheLookup WORD_RETURN, MSG_SEND, LMsgSendFpretCacheMiss
	xor	%edx, %edx		// set nonstret for msgForward_internal
	MESSENGER_END_FAST
	jmp	*%eax			// goto *imp

// cache miss: go search the method lists
LMsgSendFpretCacheMiss:
	MethodTableLookup WORD_RETURN, MSG_SEND
	xor	%edx, %edx		// set nonstret for msgForward_internal
	jmp	*%eax			// goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendFpretNilSelf:
	// %eax is already zero
	fldz
LMsgSendFpretDone:
	MESSENGER_END_NIL
	ret

LMsgSendFpretExit:
	END_ENTRY	_objc_msgSend_fpret
	
/********************************************************************
 * double objc_msgSendv_fpret(id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * On entry:
 *		(sp+4)  is the message receiver,
 *		(sp+8)	is the selector,
 *		(sp+12) is the size of the marg_list, in bytes,
 *		(sp+16) is the address of the marg_list
 *
 ********************************************************************/

	ENTRY	_objc_msgSendv_fpret

#if defined(KERNEL)
	trap				// _objc_msgSendv is not for the kernel
#else
	pushl	%ebp
	movl	%esp, %ebp
	// stack is currently aligned assuming no extra arguments
	movl	(marg_list+4)(%ebp), %edx
	addl	$8, %edx			// skip self & selector
	movl	(marg_size+4)(%ebp), %ecx
	subl    $8, %ecx			// skip self & selector
	shrl	$2, %ecx
	je      LMsgSendvFpretArgsOK

	// %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
	movl    %ecx, %eax			// 16-byte align stack
	andl    $3, %eax
	shll    $2, %eax
	subl    $16, %esp
	addl    %eax, %esp

LMsgSendvFpretArgLoop:
	decl	%ecx
	movl	0(%edx, %ecx, 4), %eax
	pushl	%eax
	jg	LMsgSendvFpretArgLoop

LMsgSendvFpretArgsOK:
	movl	(selector+4)(%ebp), %ecx
	pushl	%ecx
	movl	(self+4)(%ebp),%ecx
	pushl	%ecx
	call	_objc_msgSend_fpret
	movl	%ebp,%esp
	popl	%ebp

	ret
#endif
	END_ENTRY	_objc_msgSendv_fpret

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
	CALL_MCOUNTER

// load receiver and selector
	movl	self_stret(%esp), %eax
	movl	(selector_stret)(%esp), %ecx

// check whether receiver is nil 
	testl	%eax, %eax
	je	LMsgSendStretNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendStretReceiverOk:
	movl	isa(%eax), %edx		//   class = self->isa
	CacheLookup STRUCT_RETURN, MSG_SEND, LMsgSendStretCacheMiss
	movl	$1, %edx		// set stret for objc_msgForward
	MESSENGER_END_FAST
	jmp	*%eax			// goto *imp

// cache miss: go search the method lists
LMsgSendStretCacheMiss:
	MethodTableLookup STRUCT_RETURN, MSG_SEND
	movl	$1, %edx		// set stret for objc_msgForward
	jmp	*%eax			// goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendStretNilSelf:
	MESSENGER_END_NIL
	ret	$4			// pop struct return address (#2995932)

// guaranteed non-nil entry point (disabled for now)
// .globl _objc_msgSendNonNil_stret
// _objc_msgSendNonNil_stret:
// 	CALL_MCOUNTER
// 	movl	self_stret(%esp), %eax
// 	jmp     LMsgSendStretReceiverOk

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
	CALL_MCOUNTER

// load selector and class to search
	movl	super_stret(%esp), %eax	// struct objc_super
	movl	(selector_stret)(%esp), %ecx	//   get selector
	movl	class(%eax), %edx	// struct objc_super->class

// search the cache (class in %edx)
	CacheLookup STRUCT_RETURN, MSG_SENDSUPER, LMsgSendSuperStretCacheMiss
	movl	$1, %edx		// set stret for objc_msgForward
	MESSENGER_END_FAST
	jmp	*%eax			// goto *imp

// cache miss: go search the method lists
LMsgSendSuperStretCacheMiss:
	MethodTableLookup STRUCT_RETURN, MSG_SENDSUPER
	movl	$1, %edx		// set stret for objc_msgForward
	jmp	*%eax			// goto *imp

LMsgSendSuperStretExit:
	END_ENTRY	_objc_msgSendSuper_stret


/********************************************************************
 * void objc_msgSendv_stret(void *st_addr, id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * objc_msgSendv_stret is the struct-return form of msgSendv.
 * This function does not use the struct-return ABI; instead, the
 * structure return address is passed as a normal parameter.
 * 
 * On entry:	(sp+4)  is the address in which the returned struct is put,
 *		(sp+8)  is the message receiver,
 *		(sp+12) is the selector,
 *		(sp+16) is the size of the marg_list, in bytes,
 *		(sp+20) is the address of the marg_list
 *
 ********************************************************************/

	ENTRY	_objc_msgSendv_stret

#if defined(KERNEL)
	trap				// _objc_msgSendv_stret is not for the kernel
#else
	pushl	%ebp
	movl	%esp, %ebp
	subl    $12, %esp	// align stack assuming no extra arguments
	movl	(marg_list_stret+4)(%ebp), %edx
	addl	$8, %edx			// skip self & selector
	movl	(marg_size_stret+4)(%ebp), %ecx
	subl	$5, %ecx			// skip self & selector
	shrl	$2, %ecx
	jle	LMsgSendvStretArgsOK

	// %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
	movl    %ecx, %eax			// 16-byte align stack
	andl    $3, %eax
	shll    $2, %eax
	subl    $16, %esp
	addl    %eax, %esp

LMsgSendvStretArgLoop:
	decl	%ecx
	movl	0(%edx, %ecx, 4), %eax
	pushl	%eax
	jg	LMsgSendvStretArgLoop

LMsgSendvStretArgsOK:
	movl	(selector_stret+4)(%ebp), %ecx
	pushl	%ecx
	movl	(self_stret+4)(%ebp),%ecx
	pushl	%ecx
	movl	(struct_addr+4)(%ebp),%ecx
	pushl	%ecx
	call	_objc_msgSend_stret
	movl	%ebp,%esp
	popl	%ebp

	ret
#endif
	END_ENTRY	_objc_msgSendv_stret


/********************************************************************
 *
 * id _objc_msgForward(id self, SEL _cmd,...);
 *
 ********************************************************************/

// _FwdSel is @selector(forward::), set up in map_images().
// ALWAYS dereference _FwdSel to get to "forward::" !!
	.data
	.align 2
	.private_extern _FwdSel
_FwdSel: .long 0

	.cstring
	.align 2
LUnkSelStr: .ascii "Does not recognize selector %s (while forwarding %s)\0"

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
	// Out-of-band register %edx is nonzero for stret, zero otherwise

	MESSENGER_START
	nop
	MESSENGER_END_SLOW
	
	// Check return type (stret or not)
	testl	%edx, %edx
	jnz	__objc_msgForward_stret
	jmp	__objc_msgForward
	
	END_ENTRY	_objc_msgForward_impcache

	
	ENTRY	__objc_msgForward
	// Non-struct return version

	// Get PIC base into %edx
	call	L__objc_msgForward$pic_base
L__objc_msgForward$pic_base:
	popl	%edx
	
	// Call user handler, if any
	movl	L_forward_handler-L__objc_msgForward$pic_base(%edx),%ecx
	movl	(%ecx), %ecx
	testl	%ecx, %ecx		// if not NULL
	je	1f			//   skip to default handler
	jmp	*%ecx			// call __objc_forward_handler
1:	
	// No user handler
	// Push stack frame
	pushl   %ebp
	movl    %esp, %ebp
	
	// Die if forwarding "forward::"
	movl    (selector+4)(%ebp), %eax
	movl	_FwdSel-L__objc_msgForward$pic_base(%edx),%ecx
	cmpl	%ecx, %eax
	je	LMsgForwardError

	// Call [receiver forward:sel :margs]
	subl    $8, %esp		// 16-byte align the stack
	leal    (self+4)(%ebp), %ecx
	pushl	%ecx			// &margs
	pushl	%eax			// sel
	movl	_FwdSel-L__objc_msgForward$pic_base(%edx),%ecx
	pushl	%ecx			// forward::
	pushl   (self+4)(%ebp)		// receiver
	
	call	_objc_msgSend
	
	movl    %ebp, %esp
	popl    %ebp
	ret

LMsgForwardError:
	// Call __objc_error(receiver, "unknown selector %s %s", "forward::", forwardedSel)
	subl    $8, %esp		// 16-byte align the stack
	pushl	(selector+4+4)(%ebp)	// the forwarded selector
	movl	_FwdSel-L__objc_msgForward$pic_base(%edx),%eax
	pushl 	%eax
	leal	LUnkSelStr-L__objc_msgForward$pic_base(%edx),%eax
	pushl 	%eax
	pushl   (self+4)(%ebp)
	call	___objc_error	// never returns

	END_ENTRY	__objc_msgForward


	ENTRY	__objc_msgForward_stret
	// Struct return version

	// Get PIC base into %edx
	call	L__objc_msgForwardStret$pic_base
L__objc_msgForwardStret$pic_base:
	popl	%edx

	// Call user handler, if any
	movl	L_forward_stret_handler-L__objc_msgForwardStret$pic_base(%edx), %ecx
	movl	(%ecx), %ecx
	testl	%ecx, %ecx		// if not NULL
	je	1f			//   skip to default handler
	jmp	*%ecx			// call __objc_forward_stret_handler
1:	
	// No user handler
	// Push stack frame
	pushl	%ebp
	movl	%esp, %ebp

	// Die if forwarding "forward::"
	movl	(selector_stret+4)(%ebp), %eax
	movl	_FwdSel-L__objc_msgForwardStret$pic_base(%edx), %ecx
	cmpl	%ecx, %eax
	je	LMsgForwardStretError

	// Call [receiver forward:sel :margs]
	subl    $8, %esp		// 16-byte align the stack
	leal    (self_stret+4)(%ebp), %ecx
	pushl	%ecx			// &margs
	pushl	%eax			// sel
	movl	_FwdSel-L__objc_msgForwardStret$pic_base(%edx),%ecx
	pushl	%ecx			// forward::
	pushl   (self_stret+4)(%ebp)	// receiver
	
	call	_objc_msgSend
	
	movl    %ebp, %esp
	popl    %ebp
	ret	$4			// pop struct return address (#2995932)

LMsgForwardStretError:
	// Call __objc_error(receiver, "unknown selector %s %s", "forward::", forwardedSelector)
	subl    $8, %esp		// 16-byte align the stack
	pushl	(selector_stret+4+4)(%ebp)	// the forwarded selector
	leal	_FwdSel-L__objc_msgForwardStret$pic_base(%edx),%eax
	pushl 	%eax
	leal	LUnkSelStr-L__objc_msgForwardStret$pic_base(%edx),%eax
	pushl 	%eax
	pushl   (self_stret+4)(%ebp)
	call	___objc_error	// never returns

	END_ENTRY	__objc_msgForward_stret


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

	
	STATIC_ENTRY __objc_ignored_method
	
	movl	self(%esp), %eax
	ret
	
	END_ENTRY __objc_ignored_method
	

.section __DATA,__objc_msg_break
.long 0
.long 0
	
#endif
