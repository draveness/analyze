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
// Copyright 1988-1996 NeXT Software, Inc.

#if !__OBJC2__

#include "objc-private.h"
#include "objc-runtime-old.h"
#include "objc-file-old.h"

#if TARGET_OS_WIN32

/*
Module 
_getObjcModules(const header_info *hi, size_t *nmodules)
{
    if (nmodules) *nmodules = hi->moduleCount;
    return hi->modules;
}
*/
SEL *
_getObjcSelectorRefs(const header_info *hi, size_t *nmess)
{
    if (nmess) *nmess = hi->selrefCount;
    return hi->selrefs;
}

struct old_protocol **
_getObjcProtocols(const header_info *hi, size_t *nprotos)
{
    if (nprotos) *nprotos = hi->protocolCount;
    return hi->protocols;
}

Class*
_getObjcClassRefs(const header_info *hi, size_t *nclasses)
{
    if (nclasses) *nclasses = hi->clsrefCount;
    return (Class*)hi->clsrefs;
}

// __OBJC,__class_names section only emitted by CodeWarrior  rdar://4951638
const char *
_getObjcClassNames(const header_info *hi, size_t *size)
{
    if (size) *size = 0;
    return NULL;
}

#else

#define GETSECT(name, type, sectname)                                   \
    type *name(const header_info *hi, size_t *outCount)  \
    {                                                                   \
        unsigned long byteCount = 0;                                    \
        type *data = (type *)                                           \
            getsectiondata(hi->mhdr, SEG_OBJC, sectname, &byteCount);   \
        *outCount = byteCount / sizeof(type);                           \
        return data;                                                    \
    }

GETSECT(_getObjcModules,      struct objc_module, "__module_info");
GETSECT(_getObjcSelectorRefs, SEL,                "__message_refs");
GETSECT(_getObjcClassRefs,    Class, "__cls_refs");
GETSECT(_getObjcClassNames,   const char,         "__class_names");
// __OBJC,__class_names section only emitted by CodeWarrior  rdar://4951638


objc_image_info *
_getObjcImageInfo(const headerType *mhdr, size_t *outBytes)
{
    unsigned long byteCount = 0;
    objc_image_info *info = (objc_image_info *)
        getsectiondata(mhdr, SEG_OBJC, "__image_info", &byteCount);
    *outBytes = byteCount;
    return info;
}


struct old_protocol **
_getObjcProtocols(const header_info *hi, size_t *nprotos)
{
    unsigned long size = 0;
    struct old_protocol *protos = (struct old_protocol *)
        getsectiondata(hi->mhdr, SEG_OBJC, "__protocol", &size);
    *nprotos = size / sizeof(struct old_protocol);
    
    if (!hi->proto_refs  &&  *nprotos) {
        size_t i;
        header_info *whi = (header_info *)hi;
        whi->proto_refs = (struct old_protocol **)
            malloc(*nprotos * sizeof(*hi->proto_refs));
        for (i = 0; i < *nprotos; i++) {
            hi->proto_refs[i] = protos+i;
        }
    }
    
    return hi->proto_refs;
}


static const segmentType *
getsegbynamefromheader(const headerType *head, const char *segname)
{
    const segmentType *sgp;
    unsigned long i;
    
    sgp = (const segmentType *) (head + 1);
    for (i = 0; i < head->ncmds; i++){
        if (sgp->cmd == SEGMENT_CMD) {
            if (strncmp(sgp->segname, segname, sizeof(sgp->segname)) == 0) {
                return sgp;
            }
        }
        sgp = (const segmentType *)((char *)sgp + sgp->cmdsize);
    }
    return NULL;
}

bool
_hasObjcContents(const header_info *hi)
{
    // Look for an __OBJC,* section other than __OBJC,__image_info
    const segmentType *seg = getsegbynamefromheader(hi->mhdr, "__OBJC");
    const sectionType *sect;
    uint32_t i;
    for (i = 0; i < seg->nsects; i++) {
        sect = ((const sectionType *)(seg+1))+i;
        if (0 != strncmp(sect->sectname, "__image_info", 12)) {
            return YES;
        }
    }

    return NO;
}


#endif

#endif
