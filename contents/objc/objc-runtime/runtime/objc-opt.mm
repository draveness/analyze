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

/*
  objc-opt.mm
  Management of optimizations in the dyld shared cache 
*/

#include "objc-private.h"


#if !SUPPORT_PREOPT
// Preoptimization not supported on this platform.

struct objc_selopt_t;

bool isPreoptimized(void) 
{
    return false;
}

bool header_info::isPreoptimized() const
{
    return false;
}

objc_selopt_t *preoptimizedSelectors(void) 
{
    return nil;
}

Protocol *getPreoptimizedProtocol(const char *name)
{
    return nil;
}

Class getPreoptimizedClass(const char *name)
{
    return nil;
}

Class* copyPreoptimizedClasses(const char *name, int *outCount)
{
    *outCount = 0;
    return nil;
}

header_info *preoptimizedHinfoForHeader(const headerType *mhdr)
{
    return nil;
}

void preopt_init(void)
{
    disableSharedCacheOptimizations();
    
    if (PrintPreopt) {
        _objc_inform("PREOPTIMIZATION: is DISABLED "
                     "(not supported on ths platform)");
    }
}


// !SUPPORT_PREOPT
#else
// SUPPORT_PREOPT

#include <objc-shared-cache.h>

using objc_opt::objc_stringhash_offset_t;
//using objc_opt::objc_protocolopt_t;
using objc_opt::objc_clsopt_t;
using objc_opt::objc_headeropt_t;
using objc_opt::objc_opt_t;

__BEGIN_DECLS

// preopt: the actual opt used at runtime (nil or &_objc_opt_data)
// _objc_opt_data: opt data possibly written by dyld
// opt is initialized to ~0 to detect incorrect use before preopt_init()

static const objc_opt_t *opt = (objc_opt_t *)~0;
static bool preoptimized;

extern const objc_opt_t _objc_opt_data;  // in __TEXT, __objc_opt_ro

bool isPreoptimized(void) 
{
    return preoptimized;
}


/***********************************************************************
* Return YES if this image's dyld shared cache optimizations are valid.
**********************************************************************/
bool header_info::isPreoptimized() const
{
    // preoptimization disabled for some reason
    if (!preoptimized) return NO;

    // image not from shared cache, or not fixed inside shared cache
    if (!_objcHeaderOptimizedByDyld(this)) return NO;

    return YES;
}


objc_selopt_t *preoptimizedSelectors(void) 
{
    return opt ? opt->selopt() : nil;
}


Protocol *getPreoptimizedProtocol(const char *name)
{
    return nil;
//    objc_protocolopt_t *protocols = opt ? opt->protocolopt() : nil;
//    if (!protocols) return nil;
//
//    return (Protocol *)protocols->getProtocol(name);
}


Class getPreoptimizedClass(const char *name)
{
    objc_clsopt_t *classes = opt ? opt->clsopt() : nil;
    if (!classes) return nil;

    void *cls;
    void *hi;
    uint32_t count = classes->getClassAndHeader(name, cls, hi);
    if (count == 1  &&  ((header_info *)hi)->isLoaded()) {
        // exactly one matching class, and its image is loaded
        return (Class)cls;
    } 
    else if (count > 1) {
        // more than one matching class - find one that is loaded
        void *clslist[count];
        void *hilist[count];
        classes->getClassesAndHeaders(name, clslist, hilist);
        for (uint32_t i = 0; i < count; i++) {
            if (((header_info *)hilist[i])->isLoaded()) {
                return (Class)clslist[i];
            }
        }
    }

    // no match that is loaded
    return nil;
}


Class* copyPreoptimizedClasses(const char *name, int *outCount)
{
    *outCount = 0;

    objc_clsopt_t *classes = opt ? opt->clsopt() : nil;
    if (!classes) return nil;

    void *cls;
    void *hi;
    uint32_t count = classes->getClassAndHeader(name, cls, hi);
    if (count == 0) return nil;

    Class *result = (Class *)calloc(count, sizeof(Class));
    if (count == 1  &&  ((header_info *)hi)->isLoaded()) {
        // exactly one matching class, and its image is loaded
        result[(*outCount)++] = (Class)cls;
        return result;
    } 
    else if (count > 1) {
        // more than one matching class - find those that are loaded
        void *clslist[count];
        void *hilist[count];
        classes->getClassesAndHeaders(name, clslist, hilist);
        for (uint32_t i = 0; i < count; i++) {
            if (((header_info *)hilist[i])->isLoaded()) {
                result[(*outCount)++] = (Class)clslist[i];
            }
        }

        if (*outCount == 0) {
            // found multiple classes with that name, but none are loaded
            free(result);
            result = nil;
        }
        return result;
    }

    // no match that is loaded
    return nil;
}

namespace objc_opt {
struct objc_headeropt_t {
    uint32_t count;
    uint32_t entsize;
    header_info headers[0];  // sorted by mhdr address

    header_info *get(const headerType *mhdr) 
    {
        assert(entsize == sizeof(header_info));

        int32_t start = 0;
        int32_t end = count;
        while (start <= end) {
            int32_t i = (start+end)/2;
            header_info *hi = headers+i;
            if (mhdr == hi->mhdr) return hi;
            else if (mhdr < hi->mhdr) end = i-1;
            else start = i+1;
        }

#if DEBUG
        for (uint32_t i = 0; i < count; i++) {
            header_info *hi = headers+i;
            if (mhdr == hi->mhdr) {
                _objc_fatal("failed to find header %p (%d/%d)", 
                            mhdr, i, count);
            }
        }
#endif

        return nil;
    }
};
};


header_info *preoptimizedHinfoForHeader(const headerType *mhdr)
{
    objc_headeropt_t *hinfos = opt ? opt->headeropt() : nil;
    if (hinfos) return hinfos->get(mhdr);
    else return nil;
}


void preopt_init(void)
{
    // `opt` not set at compile time in order to detect too-early usage
    const char *failure = nil;
    opt = &_objc_opt_data;

    if (DisablePreopt) {
        // OBJC_DISABLE_PREOPTIMIZATION is set
        // If opt->version != VERSION then you continue at your own risk.
        failure = "(by OBJC_DISABLE_PREOPTIMIZATION)";
    } 
    else if (opt->version != objc_opt::VERSION) {
        // This shouldn't happen. You probably forgot to edit objc-sel-table.s.
        // If dyld really did write the wrong optimization version, 
        // then we must halt because we don't know what bits dyld twiddled.
        _objc_fatal("bad objc preopt version (want %d, got %d)", 
                    objc_opt::VERSION, opt->version);
    }
    else if (!opt->selopt()  ||  !opt->headeropt()) {
        // One of the tables is missing. 
        failure = "(dyld shared cache is absent or out of date)";
    }
#if SUPPORT_IGNORED_SELECTOR_CONSTANT
    else if (UseGC) {
        // GC is on, which renames some selectors
        // Non-selector optimizations are still valid, but we don't have
        // any of those yet
        failure = "(GC is on)";
    }
#endif

    if (failure) {
        // All preoptimized selector references are invalid.
        preoptimized = NO;
        opt = nil;
        disableSharedCacheOptimizations();

        if (PrintPreopt) {
            _objc_inform("PREOPTIMIZATION: is DISABLED %s", failure);
        }
    }
    else {
        // Valid optimization data written by dyld shared cache
        preoptimized = YES;

        if (PrintPreopt) {
            _objc_inform("PREOPTIMIZATION: is ENABLED "
                         "(version %d)", opt->version);
        }
    }
}


__END_DECLS

// SUPPORT_PREOPT
#endif
