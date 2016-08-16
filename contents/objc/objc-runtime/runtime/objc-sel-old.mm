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

/*
 *	Utilities for registering and looking up selectors.  The sole
 *	purpose of the selector tables is a registry whereby there is
 *	exactly one address (selector) associated with a given string
 *	(method name).
 */

#if !__OBJC2__

#include "objc-private.h"
#include "objc-sel-set.h"

#if SUPPORT_PREOPT
#include <objc-shared-cache.h>
static const objc_selopt_t *builtins = NULL;
#endif

__BEGIN_DECLS

static size_t SelrefCount = 0;

static const char *_objc_empty_selector = "";
static struct __objc_sel_set *_objc_selectors = NULL;


static SEL _objc_search_builtins(const char *key) 
{
#if defined(DUMP_SELECTORS)
    if (NULL != key) printf("\t\"%s\",\n", key);
#endif

    if (!key) return (SEL)0;
#if SUPPORT_IGNORED_SELECTOR_CONSTANT
    if ((uintptr_t)key == kIgnore) return (SEL)kIgnore;
    if (ignoreSelectorNamed(key)) return (SEL)kIgnore;
#endif
    if ('\0' == *key) return (SEL)_objc_empty_selector;

#if SUPPORT_PREOPT
    if (builtins) return (SEL)builtins->get(key);
#endif

    return (SEL)0;
}


const char *sel_getName(SEL sel) {
#if SUPPORT_IGNORED_SELECTOR_CONSTANT
    if ((uintptr_t)sel == kIgnore) return "<ignored selector>";
#endif
    return sel ? (const char *)sel : "<null selector>";
}


BOOL sel_isMapped(SEL name) 
{
    SEL sel;
    
    if (!name) return NO;
#if SUPPORT_IGNORED_SELECTOR_CONSTANT
    if ((uintptr_t)name == kIgnore) return YES;
#endif

    sel = _objc_search_builtins((const char *)name);
    if (sel) return YES;

    rwlock_reader_t lock(selLock);
    if (_objc_selectors) {
        sel = __objc_sel_set_get(_objc_selectors, name);
    }
    return bool(sel);
}

static SEL __sel_registerName(const char *name, int lock, int copy) 
{
    SEL result = 0;

    if (lock) selLock.assertUnlocked();
    else selLock.assertWriting();

    if (!name) return (SEL)0;
    result = _objc_search_builtins(name);
    if (result) return result;
    
    if (lock) selLock.read();
    if (_objc_selectors) {
        result = __objc_sel_set_get(_objc_selectors, (SEL)name);
    }
    if (lock) selLock.unlockRead();
    if (result) return result;

    // No match. Insert.

    if (lock) selLock.write();

    if (!_objc_selectors) {
        _objc_selectors = __objc_sel_set_create(SelrefCount);
    }
    if (lock) {
        // Rescan in case it was added while we dropped the lock
        result = __objc_sel_set_get(_objc_selectors, (SEL)name);
    }
    if (!result) {
        result = (SEL)(copy ? strdup(name) : name);
        __objc_sel_set_add(_objc_selectors, result);
#if defined(DUMP_UNKNOWN_SELECTORS)
        printf("\t\"%s\",\n", name);
#endif
    }

    if (lock) selLock.unlockWrite();
    return result;
}


SEL sel_registerName(const char *name) {
    return __sel_registerName(name, 1, 1);     // YES lock, YES copy
}

SEL sel_registerNameNoLock(const char *name, bool copy) {
    return __sel_registerName(name, 0, copy);  // NO lock, maybe copy
}

void sel_lock(void)
{
    selLock.write();
}

void sel_unlock(void)
{
    selLock.unlockWrite();
}


// 2001/1/24
// the majority of uses of this function (which used to return NULL if not found)
// did not check for NULL, so, in fact, never return NULL
//
SEL sel_getUid(const char *name) {
    return __sel_registerName(name, 2, 1);  // YES lock, YES copy
}


BOOL sel_isEqual(SEL lhs, SEL rhs)
{
    return bool(lhs == rhs);
}


/***********************************************************************
* sel_init
* Initialize selector tables and register selectors used internally.
**********************************************************************/
void sel_init(bool wantsGC, size_t selrefCount)
{
    // save this value for later
    SelrefCount = selrefCount;

#if SUPPORT_PREOPT
    builtins = preoptimizedSelectors();
#endif

    // Register selectors used by libobjc

    if (wantsGC) {
        // Registering retain/release/autorelease requires GC decision first.
        // sel_init doesn't actually need the wantsGC parameter, it just 
        // helps enforce the initialization order.
    }

#define s(x) SEL_##x = sel_registerNameNoLock(#x, NO)
#define t(x,y) SEL_##y = sel_registerNameNoLock(#x, NO)

    sel_lock();

    s(load);
    s(initialize);
    t(resolveInstanceMethod:, resolveInstanceMethod);
    t(resolveClassMethod:, resolveClassMethod);
    t(.cxx_construct, cxx_construct);
    t(.cxx_destruct, cxx_destruct);
    s(retain);
    s(release);
    s(autorelease);
    s(retainCount);
    s(alloc);
    t(allocWithZone:, allocWithZone);
    s(dealloc);
    s(copy);
    s(new);
    s(finalize);
    t(forwardInvocation:, forwardInvocation);
    t(_tryRetain, tryRetain);
    t(_isDeallocating, isDeallocating);
    s(retainWeakReference);
    s(allowsWeakReference);

    extern SEL FwdSel;
    FwdSel = sel_registerNameNoLock("forward::", NO);

    sel_unlock();

#undef s
#undef t
}

__END_DECLS

#endif
