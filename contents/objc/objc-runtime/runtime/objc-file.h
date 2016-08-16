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

#ifndef _OBJC_FILE_NEW_H
#define _OBJC_FILE_NEW_H

#if __OBJC2__

#include "objc-runtime-new.h"

// classref_t is not fixed up at launch; use remapClass() to convert

extern SEL *_getObjc2SelectorRefs(const header_info *hi, size_t *count);
extern message_ref_t *_getObjc2MessageRefs(const header_info *hi, size_t *count);
extern Class*_getObjc2ClassRefs(const header_info *hi, size_t *count);
extern Class*_getObjc2SuperRefs(const header_info *hi, size_t *count);
extern classref_t *_getObjc2ClassList(const header_info *hi, size_t *count);
extern classref_t *_getObjc2NonlazyClassList(const header_info *hi, size_t *count);
extern category_t **_getObjc2CategoryList(const header_info *hi, size_t *count);
extern category_t **_getObjc2NonlazyCategoryList(const header_info *hi, size_t *count);
extern protocol_t **_getObjc2ProtocolList(const header_info *hi, size_t *count);
extern protocol_t **_getObjc2ProtocolRefs(const header_info *hi, size_t *count);
using Initializer = void(*)(void);
extern Initializer* getLibobjcInitializers(const header_info *hi, size_t *count);

extern classref_t *_getObjc2NonlazyClassList(const headerType *mhdr, size_t *count);
extern category_t **_getObjc2NonlazyCategoryList(const headerType *mhdr, size_t *count);
extern Initializer* getLibobjcInitializers(const headerType *mhdr, size_t *count);

#endif

#endif
