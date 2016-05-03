/*
 * Copyright (c) 2010 Apple Inc.  All Rights Reserved.
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
 * objc-block-trampolines.m
 * Author:	b.bum
 *
 **********************************************************************/

/***********************************************************************
 * Imports.
 **********************************************************************/
#include "objc-private.h"
#include "runtime.h"

#include <Block.h>
#include <Block_private.h>
#include <mach/mach.h>

// symbols defined in assembly files
// Don't use the symbols directly; they're thumb-biased on some ARM archs.
#define TRAMP(tramp)                                \
    static inline __unused uintptr_t tramp(void) {  \
        extern void *_##tramp;                      \
        return ((uintptr_t)&_##tramp) & ~1UL;       \
    }
// Scalar return
TRAMP(a1a2_tramphead);   // trampoline header code
TRAMP(a1a2_firsttramp);  // first trampoline
TRAMP(a1a2_trampend);    // after the last trampoline

#if SUPPORT_STRET
// Struct return
TRAMP(a2a3_tramphead);
TRAMP(a2a3_firsttramp);
TRAMP(a2a3_trampend);
#endif

// argument mode identifier
typedef enum {
    ReturnValueInRegisterArgumentMode,
#if SUPPORT_STRET
    ReturnValueOnStackArgumentMode,
#endif
    
    ArgumentModeCount
} ArgumentMode;


// We must take care with our data layout on architectures that support 
// multiple page sizes.
// 
// The trampoline template in __TEXT is sized and aligned with PAGE_MAX_SIZE.
// On some platforms this requires additional linker flags.
// 
// When we allocate a page pair, we use PAGE_MAX_SIZE size. 
// This allows trampoline code to find its data by subtracting PAGE_MAX_SIZE.
// 
// When we allocate a page pair, we use the process's page alignment. 
// This simplifies allocation because we don't need to force greater than 
// default alignment when running with small pages, but it also means 
// the trampoline code MUST NOT look for its data by masking with PAGE_MAX_MASK.

struct TrampolineBlockPagePair 
{
    TrampolineBlockPagePair *nextPagePair; // linked list of all pages
    TrampolineBlockPagePair *nextAvailablePage; // linked list of pages with available slots
    
    uintptr_t nextAvailable; // index of next available slot, endIndex() if no more available
    
    // Payload data: block pointers and free list.
    // Bytes parallel with trampoline header code are the fields above or unused
    // uint8_t blocks[ PAGE_MAX_SIZE - sizeof(TrampolineBlockPagePair) ] 
    
    // Code: trampoline header followed by trampolines.
    // uint8_t trampolines[PAGE_MAX_SIZE];
    
    // Per-trampoline block data format:
    // initial value is 0 while page data is filled sequentially 
    // when filled, value is reference to Block_copy()d block
    // when empty, value is index of next available slot OR 0 if never used yet
    
    union Payload {
        id block;
        uintptr_t nextAvailable;  // free list
    };
    
    static uintptr_t headerSize() {
        return (uintptr_t) (a1a2_firsttramp() - a1a2_tramphead());
    }
    
    static uintptr_t slotSize() {
        return 8;
    }

    static uintptr_t startIndex() {
        // headerSize is assumed to be slot-aligned
        return headerSize() / slotSize();
    }

    static uintptr_t endIndex() {
        return (uintptr_t)PAGE_MAX_SIZE / slotSize();
    }

    static bool validIndex(uintptr_t index) {
        return (index >= startIndex() && index < endIndex());
    }

    Payload *payload(uintptr_t index) {
        assert(validIndex(index));
        return (Payload *)((char *)this + index*slotSize());
    }

    IMP trampoline(uintptr_t index) {
        assert(validIndex(index));
        char *imp = (char *)this + index*slotSize() + PAGE_MAX_SIZE;
#if __arm__
        imp++;  // trampoline is Thumb instructions
#endif
        return (IMP)imp;
    }

    uintptr_t indexForTrampoline(IMP tramp) {
        uintptr_t tramp0 = (uintptr_t)this + PAGE_MAX_SIZE;
        uintptr_t start = tramp0 + headerSize();
        uintptr_t end = tramp0 + PAGE_MAX_SIZE;
        uintptr_t address = (uintptr_t)tramp;
        if (address >= start  &&  address < end) {
            return (uintptr_t)(address - tramp0) / slotSize();
        }
        return 0;
    }

    static void check() {
        assert(TrampolineBlockPagePair::slotSize() == 8);
        assert(TrampolineBlockPagePair::headerSize() >= sizeof(TrampolineBlockPagePair));
        assert(TrampolineBlockPagePair::headerSize() % TrampolineBlockPagePair::slotSize() == 0);
        
        // _objc_inform("%p %p %p", a1a2_tramphead(), a1a2_firsttramp(), 
        // a1a2_trampend());
        assert(a1a2_tramphead() % PAGE_SIZE == 0);  // not PAGE_MAX_SIZE
        assert(a1a2_tramphead() + PAGE_MAX_SIZE == a1a2_trampend());
#if SUPPORT_STRET
        // _objc_inform("%p %p %p", a2a3_tramphead(), a2a3_firsttramp(), 
        // a2a3_trampend());
        assert(a2a3_tramphead() % PAGE_SIZE == 0);  // not PAGE_MAX_SIZE
        assert(a2a3_tramphead() + PAGE_MAX_SIZE == a2a3_trampend());
#endif
        
#if __arm__
        // make sure trampolines are Thumb
        extern void *_a1a2_firsttramp;
        extern void *_a2a3_firsttramp;
        assert(((uintptr_t)&_a1a2_firsttramp) % 2 == 1);
        assert(((uintptr_t)&_a2a3_firsttramp) % 2 == 1);
#endif
    }

};

// two sets of trampoline pages; one for stack returns and one for register returns
static TrampolineBlockPagePair *headPagePairs[ArgumentModeCount];

#pragma mark Utility Functions

static inline void _lock() {
#if __OBJC2__
    runtimeLock.write();
#else
    classLock.lock();
#endif
}

static inline void _unlock() {
#if __OBJC2__
    runtimeLock.unlockWrite();
#else
    classLock.unlock();
#endif
}

static inline void _assert_locked() {
#if __OBJC2__
    runtimeLock.assertWriting();
#else
    classLock.assertLocked();
#endif
}

#pragma mark Trampoline Management Functions
static TrampolineBlockPagePair *_allocateTrampolinesAndData(ArgumentMode aMode) 
{
    _assert_locked();

    vm_address_t dataAddress;
    
    TrampolineBlockPagePair::check();

    TrampolineBlockPagePair *headPagePair = headPagePairs[aMode];
    
    if (headPagePair) {
        assert(headPagePair->nextAvailablePage == nil);
    }
    
    kern_return_t result;
    for (int i = 0; i < 5; i++) {
         result = vm_allocate(mach_task_self(), &dataAddress, 
                              PAGE_MAX_SIZE * 2,
                              TRUE | VM_MAKE_TAG(VM_MEMORY_FOUNDATION));
        if (result != KERN_SUCCESS) {
            mach_error("vm_allocate failed", result);
            return nil;
        }

        vm_address_t codeAddress = dataAddress + PAGE_MAX_SIZE;
        result = vm_deallocate(mach_task_self(), codeAddress, PAGE_MAX_SIZE);
        if (result != KERN_SUCCESS) {
            mach_error("vm_deallocate failed", result);
            return nil;
        }
        
        uintptr_t codePage;
        switch(aMode) {
            case ReturnValueInRegisterArgumentMode:
                codePage = a1a2_tramphead();
                break;
#if SUPPORT_STRET
            case ReturnValueOnStackArgumentMode:
                codePage = a2a3_tramphead();
                break;
#endif
            default:
                _objc_fatal("unknown return mode %d", (int)aMode);
                break;
        }
        vm_prot_t currentProtection, maxProtection;
        result = vm_remap(mach_task_self(), &codeAddress, PAGE_MAX_SIZE, 
                          0, FALSE, mach_task_self(), codePage, TRUE, 
                          &currentProtection, &maxProtection, VM_INHERIT_SHARE);
        if (result != KERN_SUCCESS) {
            result = vm_deallocate(mach_task_self(), 
                                   dataAddress, PAGE_MAX_SIZE);
            if (result != KERN_SUCCESS) {
                mach_error("vm_deallocate for retry failed.", result);
                return nil;
            } 
        } else {
            break;
        }
    }
    
    if (result != KERN_SUCCESS) {
        return nil; 
    }
    
    TrampolineBlockPagePair *pagePair = (TrampolineBlockPagePair *) dataAddress;
    pagePair->nextAvailable = pagePair->startIndex();
    pagePair->nextPagePair = nil;
    pagePair->nextAvailablePage = nil;
    
    if (headPagePair) {
        TrampolineBlockPagePair *lastPagePair = headPagePair;
        while(lastPagePair->nextPagePair)
            lastPagePair = lastPagePair->nextPagePair;
        
        lastPagePair->nextPagePair = pagePair;
        headPagePairs[aMode]->nextAvailablePage = pagePair;
    } else {
        headPagePairs[aMode] = pagePair;
    }
    
    return pagePair;
}

static TrampolineBlockPagePair *
_getOrAllocatePagePairWithNextAvailable(ArgumentMode aMode) 
{
    _assert_locked();
    
    TrampolineBlockPagePair *headPagePair = headPagePairs[aMode];

    if (!headPagePair)
        return _allocateTrampolinesAndData(aMode);
    
    // make sure head page is filled first
    if (headPagePair->nextAvailable != headPagePair->endIndex())
        return headPagePair;
    
    if (headPagePair->nextAvailablePage) // check if there is a page w/a hole
        return headPagePair->nextAvailablePage;
    
    return _allocateTrampolinesAndData(aMode); // tack on a new one
}

static TrampolineBlockPagePair *
_pageAndIndexContainingIMP(IMP anImp, uintptr_t *outIndex, 
                           TrampolineBlockPagePair **outHeadPagePair) 
{
    _assert_locked();

    for (int arg = 0; arg < ArgumentModeCount; arg++) {
        for (TrampolineBlockPagePair *pagePair = headPagePairs[arg]; 
             pagePair;
             pagePair = pagePair->nextPagePair)
        {
            uintptr_t index = pagePair->indexForTrampoline(anImp);
            if (index) {
                if (outIndex) *outIndex = index;
                if (outHeadPagePair) *outHeadPagePair = headPagePairs[arg];
                return pagePair;
            }
        }
    }
    
    return nil;
}


static ArgumentMode 
_argumentModeForBlock(id block) 
{
    ArgumentMode aMode = ReturnValueInRegisterArgumentMode;

#if SUPPORT_STRET
    if (_Block_has_signature(block) && _Block_use_stret(block))
        aMode = ReturnValueOnStackArgumentMode;
#else
    assert(! (_Block_has_signature(block) && _Block_use_stret(block)));
#endif
    
    return aMode;
}


// `block` must already have been copied 
IMP 
_imp_implementationWithBlockNoCopy(id block)
{
    _assert_locked();

    ArgumentMode aMode = _argumentModeForBlock(block);

    TrampolineBlockPagePair *pagePair = 
        _getOrAllocatePagePairWithNextAvailable(aMode);
    if (!headPagePairs[aMode])
        headPagePairs[aMode] = pagePair;

    uintptr_t index = pagePair->nextAvailable;
    assert(index >= pagePair->startIndex()  &&  index < pagePair->endIndex());
    TrampolineBlockPagePair::Payload *payload = pagePair->payload(index);
    
    uintptr_t nextAvailableIndex = payload->nextAvailable;
    if (nextAvailableIndex == 0) {
        // First time through (unused slots are zero). Fill sequentially.
        // If the page is now full this will now be endIndex(), handled below.
        nextAvailableIndex = index + 1;
    }
    pagePair->nextAvailable = nextAvailableIndex;
    if (nextAvailableIndex == pagePair->endIndex()) {
        // PagePair is now full (free list or wilderness exhausted)
        // Remove from available page linked list
        TrampolineBlockPagePair *iterator = headPagePairs[aMode];
        while(iterator && (iterator->nextAvailablePage != pagePair)) {
            iterator = iterator->nextAvailablePage;
        }
        if (iterator) {
            iterator->nextAvailablePage = pagePair->nextAvailablePage;
            pagePair->nextAvailablePage = nil;
        }
    }
    
    payload->block = block;
    return pagePair->trampoline(index);
}


#pragma mark Public API
IMP imp_implementationWithBlock(id block) 
{
    block = Block_copy(block);
    _lock();
    IMP returnIMP = _imp_implementationWithBlockNoCopy(block);
    _unlock();
    return returnIMP;
}


id imp_getBlock(IMP anImp) {
    uintptr_t index;
    TrampolineBlockPagePair *pagePair;
    
    if (!anImp) return nil;
    
    _lock();
    
    pagePair = _pageAndIndexContainingIMP(anImp, &index, nil);
    
    if (!pagePair) {
        _unlock();
        return nil;
    }

    TrampolineBlockPagePair::Payload *payload = pagePair->payload(index);
    
    if (payload->nextAvailable <= TrampolineBlockPagePair::endIndex()) {
        // unallocated
        _unlock();
        return nil;
    }
    
    _unlock();
    
    return payload->block;
}

BOOL imp_removeBlock(IMP anImp) {
    TrampolineBlockPagePair *pagePair;
    TrampolineBlockPagePair *headPagePair;
    uintptr_t index;
    
    if (!anImp) return NO;
    
    _lock();
    pagePair = _pageAndIndexContainingIMP(anImp, &index, &headPagePair);
    
    if (!pagePair) {
        _unlock();
        return NO;
    }

    TrampolineBlockPagePair::Payload *payload = pagePair->payload(index);
    id block = payload->block;
    // block is released below
    
    payload->nextAvailable = pagePair->nextAvailable;
    pagePair->nextAvailable = index;
    
    // make sure this page is on available linked list
    TrampolineBlockPagePair *pagePairIterator = headPagePair;
    
    // see if page is the next available page for any existing pages
    while (pagePairIterator->nextAvailablePage && 
           pagePairIterator->nextAvailablePage != pagePair)
    {
        pagePairIterator = pagePairIterator->nextAvailablePage;
    }
    
    if (! pagePairIterator->nextAvailablePage) {
        // if iteration stopped because nextAvail was nil
        // add to end of list.
        pagePairIterator->nextAvailablePage = pagePair;
        pagePair->nextAvailablePage = nil;
    }
    
    _unlock();
    Block_release(block);
    return YES;
}
