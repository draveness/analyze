/*
 * Copyright (c) 2010-2012 Apple Inc. All rights reserved.
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


/***********************************************************************
* Inlineable parts of NSObject / objc_object implementation
**********************************************************************/

#ifndef _OBJC_OBJCOBJECT_H_
#define _OBJC_OBJCOBJECT_H_

#include "objc-private.h"


enum ReturnDisposition : bool {
    ReturnAtPlus0 = false, ReturnAtPlus1 = true
};

static ALWAYS_INLINE 
bool prepareOptimizedReturn(ReturnDisposition disposition);


#if SUPPORT_TAGGED_POINTERS

#define TAG_COUNT 8
#define TAG_SLOT_MASK 0xf

#if SUPPORT_MSB_TAGGED_POINTERS
#   define TAG_MASK (1ULL<<63)
#   define TAG_SLOT_SHIFT 60
#   define TAG_PAYLOAD_LSHIFT 4
#   define TAG_PAYLOAD_RSHIFT 4
#else
#   define TAG_MASK 1
#   define TAG_SLOT_SHIFT 0
#   define TAG_PAYLOAD_LSHIFT 0
#   define TAG_PAYLOAD_RSHIFT 4
#endif

extern "C" { extern Class objc_debug_taggedpointer_classes[TAG_COUNT*2]; }
#define objc_tag_classes objc_debug_taggedpointer_classes

#endif


inline bool
objc_object::isClass()
{
    if (isTaggedPointer()) return false;
    return ISA()->isMetaClass();
}

#if SUPPORT_NONPOINTER_ISA

#   if !SUPPORT_TAGGED_POINTERS
#       error sorry
#   endif


inline Class 
objc_object::ISA() 
{
    assert(!isTaggedPointer()); 
    return (Class)(isa.bits & ISA_MASK);
}


inline bool 
objc_object::hasIndexedIsa()
{
    return isa.indexed;
}

inline Class 
objc_object::getIsa() 
{
    if (isTaggedPointer()) {
        uintptr_t slot = ((uintptr_t)this >> TAG_SLOT_SHIFT) & TAG_SLOT_MASK;
        return objc_tag_classes[slot];
    }
    return ISA();
}


inline void 
objc_object::initIsa(Class cls)
{
    initIsa(cls, false, false);
}

inline void 
objc_object::initClassIsa(Class cls)
{
    if (DisableIndexedIsa) {
        initIsa(cls, false, false);
    } else {
        initIsa(cls, true, false);
    }
}

inline void
objc_object::initProtocolIsa(Class cls)
{
    return initClassIsa(cls);
}

inline void 
objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)
{
    assert(!UseGC);
    assert(!cls->requiresRawIsa());
    assert(hasCxxDtor == cls->hasCxxDtor());

    initIsa(cls, true, hasCxxDtor);
}

inline void 
objc_object::initIsa(Class cls, bool indexed, bool hasCxxDtor) 
{ 
    assert(!isTaggedPointer()); 
    
    if (!indexed) {
        isa.cls = cls;
    } else {
        assert(!DisableIndexedIsa);
        isa.bits = ISA_MAGIC_VALUE;
        // isa.magic is part of ISA_MAGIC_VALUE
        // isa.indexed is part of ISA_MAGIC_VALUE
        isa.has_cxx_dtor = hasCxxDtor;
        isa.shiftcls = (uintptr_t)cls >> 3;
    }
}


inline Class 
objc_object::changeIsa(Class newCls)
{
    // This is almost always rue but there are 
    // enough edge cases that we can't assert it.
    // assert(newCls->isFuture()  || 
    //        newCls->isInitializing()  ||  newCls->isInitialized());

    assert(!isTaggedPointer()); 

    isa_t oldisa;
    isa_t newisa;

    bool sideTableLocked = false;
    bool transcribeToSideTable = false;

    do {
        transcribeToSideTable = false;
        oldisa = LoadExclusive(&isa.bits);
        if ((oldisa.bits == 0  ||  oldisa.indexed)  &&
            !newCls->isFuture()  &&  newCls->canAllocIndexed())
        {
            // 0 -> indexed
            // indexed -> indexed
            if (oldisa.bits == 0) newisa.bits = ISA_MAGIC_VALUE;
            else newisa = oldisa;
            // isa.magic is part of ISA_MAGIC_VALUE
            // isa.indexed is part of ISA_MAGIC_VALUE
            newisa.has_cxx_dtor = newCls->hasCxxDtor();
            newisa.shiftcls = (uintptr_t)newCls >> 3;
        }
        else if (oldisa.indexed) {
            // indexed -> not indexed
            // Need to copy retain count et al to side table.
            // Acquire side table lock before setting isa to 
            // prevent races such as concurrent -release.
            if (!sideTableLocked) sidetable_lock();
            sideTableLocked = true;
            transcribeToSideTable = true;
            newisa.cls = newCls;
        }
        else {
            // not indexed -> not indexed
            newisa.cls = newCls;
        }
    } while (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits));

    if (transcribeToSideTable) {
        // Copy oldisa's retain count et al to side table.
        // oldisa.weakly_referenced: nothing to do
        // oldisa.has_assoc: nothing to do
        // oldisa.has_cxx_dtor: nothing to do
        sidetable_moveExtraRC_nolock(oldisa.extra_rc, 
                                     oldisa.deallocating, 
                                     oldisa.weakly_referenced);
    }

    if (sideTableLocked) sidetable_unlock();

    Class oldCls;
    if (oldisa.indexed) oldCls = (Class)((uintptr_t)oldisa.shiftcls << 3);
    else oldCls = oldisa.cls;
    
    return oldCls;
}


inline bool 
objc_object::isTaggedPointer() 
{
    return ((uintptr_t)this & TAG_MASK);
}


inline bool
objc_object::hasAssociatedObjects()
{
    if (isTaggedPointer()) return true;
    if (isa.indexed) return isa.has_assoc;
    return true;
}


inline void
objc_object::setHasAssociatedObjects()
{
    if (isTaggedPointer()) return;

 retry:
    isa_t oldisa = LoadExclusive(&isa.bits);
    isa_t newisa = oldisa;
    if (!newisa.indexed) return;
    if (newisa.has_assoc) return;
    newisa.has_assoc = true;
    if (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits)) goto retry;
}


inline bool
objc_object::isWeaklyReferenced()
{
    assert(!isTaggedPointer());
    if (isa.indexed) return isa.weakly_referenced;
    else return sidetable_isWeaklyReferenced();
}


inline void
objc_object::setWeaklyReferenced_nolock()
{
 retry:
    isa_t oldisa = LoadExclusive(&isa.bits);
    isa_t newisa = oldisa;
    if (!newisa.indexed) return sidetable_setWeaklyReferenced_nolock();
    if (newisa.weakly_referenced) return;
    newisa.weakly_referenced = true;
    if (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits)) goto retry;
}


inline bool
objc_object::hasCxxDtor()
{
    assert(!isTaggedPointer());
    if (isa.indexed) return isa.has_cxx_dtor;
    else return isa.cls->hasCxxDtor();
}



inline bool 
objc_object::rootIsDeallocating()
{
    assert(!UseGC);

    if (isTaggedPointer()) return false;
    if (isa.indexed) return isa.deallocating;
    return sidetable_isDeallocating();
}


inline void 
objc_object::clearDeallocating()
{
    if (!isa.indexed) {
        // Slow path for raw pointer isa.
        sidetable_clearDeallocating();
    }
    else if (isa.weakly_referenced  ||  isa.has_sidetable_rc) {
        // Slow path for non-pointer isa with weak refs and/or side table data.
        clearDeallocating_slow();
    }

    assert(!sidetable_present());
}


inline void
objc_object::rootDealloc()
{
    assert(!UseGC);
    if (isTaggedPointer()) return;

    if (isa.indexed  &&  
        !isa.weakly_referenced  &&  
        !isa.has_assoc  &&  
        !isa.has_cxx_dtor  &&  
        !isa.has_sidetable_rc)
    {
        assert(!sidetable_present());
        free(this);
    } 
    else {
        object_dispose((id)this);
    }
}


// Equivalent to calling [this retain], with shortcuts if there is no override
inline id 
objc_object::retain()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());
    assert(!isTaggedPointer());

    if (! ISA()->hasCustomRR()) {
        return rootRetain();
    }

    return ((id(*)(objc_object *, SEL))objc_msgSend)(this, SEL_retain);
}


// Base retain implementation, ignoring overrides.
// This does not check isa.fast_rr; if there is an RR override then 
// it was already called and it chose to call [super retain].
//
// tryRetain=true is the -_tryRetain path.
// handleOverflow=false is the frameless fast path.
// handleOverflow=true is the framed slow path including overflow to side table
// The code is structured this way to prevent duplication.

ALWAYS_INLINE id 
objc_object::rootRetain()
{
    return rootRetain(false, false);
}

ALWAYS_INLINE bool 
objc_object::rootTryRetain()
{
    return rootRetain(true, false) ? true : false;
}

ALWAYS_INLINE id 
objc_object::rootRetain(bool tryRetain, bool handleOverflow)
{
    assert(!UseGC);
    if (isTaggedPointer()) return (id)this;

    bool sideTableLocked = false;
    bool transcribeToSideTable = false;

    isa_t oldisa;
    isa_t newisa;

    do {
        transcribeToSideTable = false;
        oldisa = LoadExclusive(&isa.bits);
        newisa = oldisa;
        if (!newisa.indexed) goto unindexed;
        // don't check newisa.fast_rr; we already called any RR overrides
        if (tryRetain && newisa.deallocating) goto tryfail;
        uintptr_t carry;
        newisa.bits = addc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc++

        if (carry) {
            // newisa.extra_rc++ overflowed
            if (!handleOverflow) return rootRetain_overflow(tryRetain);
            // Leave half of the retain counts inline and 
            // prepare to copy the other half to the side table.
            if (!tryRetain && !sideTableLocked) sidetable_lock();
            sideTableLocked = true;
            transcribeToSideTable = true;
            newisa.extra_rc = RC_HALF;
            newisa.has_sidetable_rc = true;
        }
    } while (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits));

    if (transcribeToSideTable) {
        // Copy the other half of the retain counts to the side table.
        sidetable_addExtraRC_nolock(RC_HALF);
    }

    if (!tryRetain && sideTableLocked) sidetable_unlock();
    return (id)this;

 tryfail:
    if (!tryRetain && sideTableLocked) sidetable_unlock();
    return nil;

 unindexed:
    if (!tryRetain && sideTableLocked) sidetable_unlock();
    if (tryRetain) return sidetable_tryRetain() ? (id)this : nil;
    else return sidetable_retain();
}


// Equivalent to calling [this release], with shortcuts if there is no override
inline void
objc_object::release()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());
    assert(!isTaggedPointer());

    if (! ISA()->hasCustomRR()) {
        rootRelease();
        return;
    }

    ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_release);
}


// Base release implementation, ignoring overrides.
// Does not call -dealloc.
// Returns true if the object should now be deallocated.
// This does not check isa.fast_rr; if there is an RR override then 
// it was already called and it chose to call [super release].
// 
// handleUnderflow=false is the frameless fast path.
// handleUnderflow=true is the framed slow path including side table borrow
// The code is structured this way to prevent duplication.

ALWAYS_INLINE bool 
objc_object::rootRelease()
{
    return rootRelease(true, false);
}

ALWAYS_INLINE bool 
objc_object::rootReleaseShouldDealloc()
{
    return rootRelease(false, false);
}

ALWAYS_INLINE bool 
objc_object::rootRelease(bool performDealloc, bool handleUnderflow)
{
    assert(!UseGC);
    if (isTaggedPointer()) return false;

    bool sideTableLocked = false;

    isa_t oldisa;
    isa_t newisa;

 retry:
    do {
        oldisa = LoadExclusive(&isa.bits);
        newisa = oldisa;
        if (!newisa.indexed) goto unindexed;
        // don't check newisa.fast_rr; we already called any RR overrides
        uintptr_t carry;
        newisa.bits = subc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc--
        if (carry) goto underflow;
    } while (!StoreReleaseExclusive(&isa.bits, oldisa.bits, newisa.bits));

    if (sideTableLocked) sidetable_unlock();
    return false;

 underflow:
    // newisa.extra_rc-- underflowed: borrow from side table or deallocate

    // abandon newisa to undo the decrement
    newisa = oldisa;

    if (newisa.has_sidetable_rc) {
        if (!handleUnderflow) {
            return rootRelease_underflow(performDealloc);
        }

        // Transfer retain count from side table to inline storage.

        if (!sideTableLocked) {
            sidetable_lock();
            sideTableLocked = true;
            if (!isa.indexed) {
                // Lost a race vs the indexed -> not indexed transition
                // before we got the side table lock. Stop now to avoid 
                // breaking the safety checks in the sidetable ExtraRC code.
                goto unindexed;
            }
        }

        // Try to remove some retain counts from the side table.        
        size_t borrowed = sidetable_subExtraRC_nolock(RC_HALF);

        // To avoid races, has_sidetable_rc must remain set 
        // even if the side table count is now zero.

        if (borrowed > 0) {
            // Side table retain count decreased.
            // Try to add them to the inline count.
            newisa.extra_rc = borrowed - 1;  // redo the original decrement too
            bool stored = StoreExclusive(&isa.bits, oldisa.bits, newisa.bits);
            if (!stored) {
                // Inline update failed. 
                // Try it again right now. This prevents livelock on LL/SC 
                // architectures where the side table access itself may have 
                // dropped the reservation.
                isa_t oldisa2 = LoadExclusive(&isa.bits);
                isa_t newisa2 = oldisa2;
                if (newisa2.indexed) {
                    uintptr_t overflow;
                    newisa2.bits = 
                        addc(newisa2.bits, RC_ONE * (borrowed-1), 0, &overflow);
                    if (!overflow) {
                        stored = StoreReleaseExclusive(&isa.bits, oldisa2.bits, 
                                                       newisa2.bits);
                    }
                }
            }

            if (!stored) {
                // Inline update failed.
                // Put the retains back in the side table.
                sidetable_addExtraRC_nolock(borrowed);
                goto retry;
            }

            // Decrement successful after borrowing from side table.
            // This decrement cannot be the deallocating decrement - the side 
            // table lock and has_sidetable_rc bit ensure that if everyone 
            // else tried to -release while we worked, the last one would block.
            sidetable_unlock();
            return false;
        }
        else {
            // Side table is empty after all. Fall-through to the dealloc path.
        }
    }

    // Really deallocate.

    if (sideTableLocked) sidetable_unlock();

    if (newisa.deallocating) {
        return overrelease_error();
    }
    newisa.deallocating = true;
    if (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits)) goto retry;
    __sync_synchronize();
    if (performDealloc) {
        ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_dealloc);
    }
    return true;

 unindexed:
    if (sideTableLocked) sidetable_unlock();
    return sidetable_release(performDealloc);
}


// Equivalent to [this autorelease], with shortcuts if there is no override
inline id 
objc_object::autorelease()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());

    if (isTaggedPointer()) return (id)this;
    if (! ISA()->hasCustomRR()) return rootAutorelease();

    return ((id(*)(objc_object *, SEL))objc_msgSend)(this, SEL_autorelease);
}


// Base autorelease implementation, ignoring overrides.
inline id 
objc_object::rootAutorelease()
{
    assert(!UseGC);

    if (isTaggedPointer()) return (id)this;
    if (prepareOptimizedReturn(ReturnAtPlus1)) return (id)this;

    return rootAutorelease2();
}


inline uintptr_t 
objc_object::rootRetainCount()
{
    assert(!UseGC);
    if (isTaggedPointer()) return (uintptr_t)this;

    sidetable_lock();
    isa_t bits = LoadExclusive(&isa.bits);
    if (bits.indexed) {
        uintptr_t rc = 1 + bits.extra_rc;
        if (bits.has_sidetable_rc) {
            rc += sidetable_getExtraRC_nolock();
        }
        sidetable_unlock();
        return rc;
    }

    sidetable_unlock();
    return sidetable_retainCount();
}


// SUPPORT_NONPOINTER_ISA
#else
// not SUPPORT_NONPOINTER_ISA


inline Class 
objc_object::ISA() 
{
    assert(!isTaggedPointer()); 
    return isa.cls;
}


inline bool 
objc_object::hasIndexedIsa()
{
    return false;
}


inline Class 
objc_object::getIsa() 
{
#if SUPPORT_TAGGED_POINTERS
    if (isTaggedPointer()) {
        uintptr_t slot = ((uintptr_t)this >> TAG_SLOT_SHIFT) & TAG_SLOT_MASK;
        return objc_tag_classes[slot];
    }
#endif
    return ISA();
}


inline void 
objc_object::initIsa(Class cls)
{
    assert(!isTaggedPointer()); 
    isa = (uintptr_t)cls; 
}


inline void 
objc_object::initClassIsa(Class cls)
{
    initIsa(cls);
}


inline void 
objc_object::initProtocolIsa(Class cls)
{
    initIsa(cls);
}


inline void 
objc_object::initInstanceIsa(Class cls, bool)
{
    initIsa(cls);
}


inline void 
objc_object::initIsa(Class cls, bool, bool)
{ 
    initIsa(cls);
}


inline Class 
objc_object::changeIsa(Class cls)
{
    // This is almost always rue but there are 
    // enough edge cases that we can't assert it.
    // assert(cls->isFuture()  ||  
    //        cls->isInitializing()  ||  cls->isInitialized());

    assert(!isTaggedPointer()); 
    
    isa_t oldisa, newisa;
    newisa.cls = cls;
    do {
        oldisa = LoadExclusive(&isa.bits);
    } while (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits));
    
    if (oldisa.cls  &&  oldisa.cls->instancesHaveAssociatedObjects()) {
        cls->setInstancesHaveAssociatedObjects();
    }
    
    return oldisa.cls;
}


inline bool 
objc_object::isTaggedPointer() 
{
#if SUPPORT_TAGGED_POINTERS
    return ((uintptr_t)this & TAG_MASK);
#else
    return false;
#endif
}


inline bool
objc_object::hasAssociatedObjects()
{
    assert(!UseGC);

    return getIsa()->instancesHaveAssociatedObjects();
}


inline void
objc_object::setHasAssociatedObjects()
{
    assert(!UseGC);

    getIsa()->setInstancesHaveAssociatedObjects();
}


inline bool
objc_object::isWeaklyReferenced()
{
    assert(!isTaggedPointer());
    assert(!UseGC);

    return sidetable_isWeaklyReferenced();
}


inline void 
objc_object::setWeaklyReferenced_nolock()
{
    assert(!isTaggedPointer());
    assert(!UseGC);

    sidetable_setWeaklyReferenced_nolock();
}


inline bool
objc_object::hasCxxDtor()
{
    assert(!isTaggedPointer());
    return isa.cls->hasCxxDtor();
}


inline bool 
objc_object::rootIsDeallocating()
{
    assert(!UseGC);

    if (isTaggedPointer()) return false;
    return sidetable_isDeallocating();
}


inline void 
objc_object::clearDeallocating()
{
    sidetable_clearDeallocating();
}


inline void
objc_object::rootDealloc()
{
    if (isTaggedPointer()) return;
    object_dispose((id)this);
}


// Equivalent to calling [this retain], with shortcuts if there is no override
inline id 
objc_object::retain()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());
    assert(!isTaggedPointer());

    if (! ISA()->hasCustomRR()) {
        return sidetable_retain();
    }

    return ((id(*)(objc_object *, SEL))objc_msgSend)(this, SEL_retain);
}


// Base retain implementation, ignoring overrides.
// This does not check isa.fast_rr; if there is an RR override then 
// it was already called and it chose to call [super retain].
inline id 
objc_object::rootRetain()
{
    assert(!UseGC);

    if (isTaggedPointer()) return (id)this;
    return sidetable_retain();
}


// Equivalent to calling [this release], with shortcuts if there is no override
inline void
objc_object::release()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());
    assert(!isTaggedPointer());

    if (! ISA()->hasCustomRR()) {
        sidetable_release();
        return;
    }

    ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_release);
}


// Base release implementation, ignoring overrides.
// Does not call -dealloc.
// Returns true if the object should now be deallocated.
// This does not check isa.fast_rr; if there is an RR override then 
// it was already called and it chose to call [super release].
inline bool 
objc_object::rootRelease()
{
    assert(!UseGC);

    if (isTaggedPointer()) return false;
    return sidetable_release(true);
}

inline bool 
objc_object::rootReleaseShouldDealloc()
{
    if (isTaggedPointer()) return false;
    return sidetable_release(false);
}


// Equivalent to [this autorelease], with shortcuts if there is no override
inline id 
objc_object::autorelease()
{
    // UseGC is allowed here, but requires hasCustomRR.
    assert(!UseGC  ||  ISA()->hasCustomRR());

    if (isTaggedPointer()) return (id)this;
    if (! ISA()->hasCustomRR()) return rootAutorelease();

    return ((id(*)(objc_object *, SEL))objc_msgSend)(this, SEL_autorelease);
}


// Base autorelease implementation, ignoring overrides.
inline id 
objc_object::rootAutorelease()
{
    assert(!UseGC);

    if (isTaggedPointer()) return (id)this;
    if (prepareOptimizedReturn(ReturnAtPlus1)) return (id)this;

    return rootAutorelease2();
}


// Base tryRetain implementation, ignoring overrides.
// This does not check isa.fast_rr; if there is an RR override then 
// it was already called and it chose to call [super _tryRetain].
inline bool 
objc_object::rootTryRetain()
{
    assert(!UseGC);

    if (isTaggedPointer()) return true;
    return sidetable_tryRetain();
}


inline uintptr_t 
objc_object::rootRetainCount()
{
    assert(!UseGC);

    if (isTaggedPointer()) return (uintptr_t)this;
    return sidetable_retainCount();
}


// not SUPPORT_NONPOINTER_ISA
#endif


#if SUPPORT_RETURN_AUTORELEASE

/***********************************************************************
  Fast handling of return through Cocoa's +0 autoreleasing convention.
  The caller and callee cooperate to keep the returned object 
  out of the autorelease pool and eliminate redundant retain/release pairs.

  An optimized callee looks at the caller's instructions following the 
  return. If the caller's instructions are also optimized then the callee 
  skips all retain count operations: no autorelease, no retain/autorelease.
  Instead it saves the result's current retain count (+0 or +1) in 
  thread-local storage. If the caller does not look optimized then 
  the callee performs autorelease or retain/autorelease as usual.

  An optimized caller looks at the thread-local storage. If the result 
  is set then it performs any retain or release needed to change the 
  result from the retain count left by the callee to the retain count 
  desired by the caller. Otherwise the caller assumes the result is 
  currently at +0 from an unoptimized callee and performs any retain 
  needed for that case.

  There are two optimized callees:
    objc_autoreleaseReturnValue
      result is currently +1. The unoptimized path autoreleases it.
    objc_retainAutoreleaseReturnValue
      result is currently +0. The unoptimized path retains and autoreleases it.

  There are two optimized callers:
    objc_retainAutoreleasedReturnValue
      caller wants the value at +1. The unoptimized path retains it.
    objc_unsafeClaimAutoreleasedReturnValue
      caller wants the value at +0 unsafely. The unoptimized path does nothing.

  Example:

    Callee:
      // compute ret at +1
      return objc_autoreleaseReturnValue(ret);
    
    Caller:
      ret = callee();
      ret = objc_retainAutoreleasedReturnValue(ret);
      // use ret at +1 here

    Callee sees the optimized caller, sets TLS, and leaves the result at +1.
    Caller sees the TLS, clears it, and accepts the result at +1 as-is.

  The callee's recognition of the optimized caller is architecture-dependent.
  i386 and x86_64: Callee looks for `mov rax, rdi` followed by a call or 
    jump instruction to objc_retainAutoreleasedReturnValue or 
    objc_unsafeClaimAutoreleasedReturnValue. 
  armv7: Callee looks for a magic nop `mov r7, r7` (frame pointer register). 
  arm64: Callee looks for a magic nop `mov x29, x29` (frame pointer register). 

  Tagged pointer objects do participate in the optimized return scheme, 
  because it saves message sends. They are not entered in the autorelease 
  pool in the unoptimized case.
**********************************************************************/

# if __x86_64__

static ALWAYS_INLINE bool 
callerAcceptsOptimizedReturn(const void * const ra0)
{
    const uint8_t *ra1 = (const uint8_t *)ra0;
    const uint16_t *ra2;
    const uint32_t *ra4 = (const uint32_t *)ra1;
    const void **sym;

#define PREFER_GOTPCREL 0
#if PREFER_GOTPCREL
    // 48 89 c7    movq  %rax,%rdi
    // ff 15       callq *symbol@GOTPCREL(%rip)
    if (*ra4 != 0xffc78948) {
        return false;
    }
    if (ra1[4] != 0x15) {
        return false;
    }
    ra1 += 3;
#else
    // 48 89 c7    movq  %rax,%rdi
    // e8          callq symbol
    if (*ra4 != 0xe8c78948) {
        return false;
    }
    ra1 += (long)*(const int32_t *)(ra1 + 4) + 8l;
    ra2 = (const uint16_t *)ra1;
    // ff 25       jmpq *symbol@DYLDMAGIC(%rip)
    if (*ra2 != 0x25ff) {
        return false;
    }
#endif
    ra1 += 6l + (long)*(const int32_t *)(ra1 + 2);
    sym = (const void **)ra1;
    if (*sym != objc_retainAutoreleasedReturnValue  &&  
        *sym != objc_unsafeClaimAutoreleasedReturnValue) 
    {
        return false;
    }

    return true;
}

// __x86_64__
# elif __arm__

static ALWAYS_INLINE bool 
callerAcceptsOptimizedReturn(const void *ra)
{
    // if the low bit is set, we're returning to thumb mode
    if ((uintptr_t)ra & 1) {
        // 3f 46          mov r7, r7
        // we mask off the low bit via subtraction
        if (*(uint16_t *)((uint8_t *)ra - 1) == 0x463f) {
            return true;
        }
    } else {
        // 07 70 a0 e1    mov r7, r7
        if (*(uint32_t *)ra == 0xe1a07007) {
            return true;
        }
    }
    return false;
}

// __arm__
# elif __arm64__

static ALWAYS_INLINE bool 
callerAcceptsOptimizedReturn(const void *ra)
{
    // fd 03 1d aa    mov fp, fp
    if (*(uint32_t *)ra == 0xaa1d03fd) {
        return true;
    }
    return false;
}

// __arm64__
# elif __i386__  &&  TARGET_IPHONE_SIMULATOR

static inline bool 
callerAcceptsOptimizedReturn(const void *ra)
{
    return false;
}

// __i386__  &&  TARGET_IPHONE_SIMULATOR
# else

#warning unknown architecture

static ALWAYS_INLINE bool 
callerAcceptsOptimizedReturn(const void *ra)
{
    return false;
}

// unknown architecture
# endif


static ALWAYS_INLINE ReturnDisposition 
getReturnDisposition()
{
    return (ReturnDisposition)(uintptr_t)tls_get_direct(RETURN_DISPOSITION_KEY);
}


static ALWAYS_INLINE void 
setReturnDisposition(ReturnDisposition disposition)
{
    tls_set_direct(RETURN_DISPOSITION_KEY, (void*)(uintptr_t)disposition);
}


// Try to prepare for optimized return with the given disposition (+0 or +1).
// Returns true if the optimized path is successful.
// Otherwise the return value must be retained and/or autoreleased as usual.
static ALWAYS_INLINE bool 
prepareOptimizedReturn(ReturnDisposition disposition)
{
    assert(getReturnDisposition() == ReturnAtPlus0);

    if (callerAcceptsOptimizedReturn(__builtin_return_address(0))) {
        if (disposition) setReturnDisposition(disposition);
        return true;
    }

    return false;
}


// Try to accept an optimized return.
// Returns the disposition of the returned object (+0 or +1).
// An un-optimized return is +0.
static ALWAYS_INLINE ReturnDisposition 
acceptOptimizedReturn()
{
    ReturnDisposition disposition = getReturnDisposition();
    setReturnDisposition(ReturnAtPlus0);  // reset to the unoptimized state
    return disposition;
}


// SUPPORT_RETURN_AUTORELEASE
#else
// not SUPPORT_RETURN_AUTORELEASE


static ALWAYS_INLINE bool
prepareOptimizedReturn(ReturnDisposition disposition __unused)
{
    return false;
}


static ALWAYS_INLINE ReturnDisposition 
acceptOptimizedReturn()
{
    return ReturnAtPlus0;
}


// not SUPPORT_RETURN_AUTORELEASE
#endif


// _OBJC_OBJECT_H_
#endif
