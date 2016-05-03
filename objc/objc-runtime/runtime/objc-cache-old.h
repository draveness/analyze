/*
 * Copyright (c) 2012 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_CACHE_OLD_H
#define _OBJC_CACHE_OLD_H

#include "objc-private.h"

__BEGIN_DECLS

extern IMP _cache_getImp(Class cls, SEL sel);
extern Method _cache_getMethod(Class cls, SEL sel, IMP objc_msgForward_internal_imp);

extern void flush_cache(Class cls);
extern bool _cache_fill(Class cls, Method meth, SEL sel);
extern void _cache_addForwardEntry(Class cls, SEL sel);
extern IMP  _cache_addIgnoredEntry(Class cls, SEL sel);
extern void _cache_free(Cache cache);
extern void _cache_collect(bool collectALot);

__END_DECLS

#endif
