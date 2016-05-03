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

#ifndef _OBJC_FILE_OLD_H
#define _OBJC_FILE_OLD_H

#if !__OBJC2__

#include "objc-os.h"

struct objc_module;
struct old_protocol;
struct old_class;

__BEGIN_DECLS

extern struct objc_module *_getObjcModules(const header_info *hi, size_t *nmodules);
extern SEL *_getObjcSelectorRefs(const header_info *hi, size_t *nmess);
extern struct old_protocol **_getObjcProtocols(const header_info *hi, size_t *nprotos);
extern Class *_getObjcClassRefs(const header_info *hi, size_t *nclasses);
extern const char *_getObjcClassNames(const header_info *hi, size_t *size);

__END_DECLS

#endif

#endif
