/*
 * Copyright (c) 2007 Apple Inc.  All Rights Reserved.
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
* objc-os.m
* OS portability layer.
**********************************************************************/

#include "objc-private.h"
#include "objc-loadmethod.h"

#if TARGET_OS_WIN32

#include "objc-runtime-old.h"
#include "objcrt.h"

int monitor_init(monitor_t *c) 
{
    // fixme error checking
    HANDLE mutex = CreateMutex(NULL, TRUE, NULL);
    while (!c->mutex) {
        // fixme memory barrier here?
        if (0 == InterlockedCompareExchangePointer(&c->mutex, mutex, 0)) {
            // we win - finish construction
            c->waiters = CreateSemaphore(NULL, 0, 0x7fffffff, NULL);
            c->waitersDone = CreateEvent(NULL, FALSE, FALSE, NULL);
            InitializeCriticalSection(&c->waitCountLock);
            c->waitCount = 0;
            c->didBroadcast = 0;
            ReleaseMutex(c->mutex);    
            return 0;
        }
    }

    // someone else allocated the mutex and constructed the monitor
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 0;
}

void mutex_init(mutex_t *m)
{
    while (!m->lock) {
        CRITICAL_SECTION *newlock = malloc(sizeof(CRITICAL_SECTION));
        InitializeCriticalSection(newlock);
        // fixme memory barrier here?
        if (0 == InterlockedCompareExchangePointer(&m->lock, newlock, 0)) {
            return;
        }
        // someone else installed their lock first
        DeleteCriticalSection(newlock);
        free(newlock);
    }
}


void recursive_mutex_init(recursive_mutex_t *m)
{
    // fixme error checking
    HANDLE newmutex = CreateMutex(NULL, FALSE, NULL);
    while (!m->mutex) {
        // fixme memory barrier here?
        if (0 == InterlockedCompareExchangePointer(&m->mutex, newmutex, 0)) {
            // we win
            return;
        }
    }
    
    // someone else installed their lock first
    CloseHandle(newmutex);
}


WINBOOL APIENTRY DllMain( HMODULE hModule,
                       DWORD  ul_reason_for_call,
                       LPVOID lpReserved
					 )
{
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        environ_init();
        tls_init();
        lock_init();
        sel_init(NO, 3500);  // old selector heuristic
        exception_init();
        break;

    case DLL_THREAD_ATTACH:
        break;

    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

OBJC_EXPORT void *_objc_init_image(HMODULE image, const objc_sections *sects)
{
    header_info *hi = malloc(sizeof(header_info));
    size_t count, i;

    hi->mhdr = (const headerType *)image;
    hi->info = sects->iiStart;
    hi->allClassesRealized = NO;
    hi->modules = sects->modStart ? (Module *)((void **)sects->modStart+1) : 0;
    hi->moduleCount = (Module *)sects->modEnd - hi->modules;
    hi->protocols = sects->protoStart ? (struct old_protocol **)((void **)sects->protoStart+1) : 0;
    hi->protocolCount = (struct old_protocol **)sects->protoEnd - hi->protocols;
    hi->imageinfo = NULL;
    hi->imageinfoBytes = 0;
    // hi->imageinfo = sects->iiStart ? (uint8_t *)((void **)sects->iiStart+1) : 0;;
//     hi->imageinfoBytes = (uint8_t *)sects->iiEnd - hi->imageinfo;
    hi->selrefs = sects->selrefsStart ? (SEL *)((void **)sects->selrefsStart+1) : 0;
    hi->selrefCount = (SEL *)sects->selrefsEnd - hi->selrefs;
    hi->clsrefs = sects->clsrefsStart ? (Class *)((void **)sects->clsrefsStart+1) : 0;
    hi->clsrefCount = (Class *)sects->clsrefsEnd - hi->clsrefs;

    count = 0;
    for (i = 0; i < hi->moduleCount; i++) {
        if (hi->modules[i]) count++;
    }
    hi->mod_count = 0;
    hi->mod_ptr = 0;
    if (count > 0) {
        hi->mod_ptr = malloc(count * sizeof(struct objc_module));
        for (i = 0; i < hi->moduleCount; i++) {
            if (hi->modules[i]) memcpy(&hi->mod_ptr[hi->mod_count++], hi->modules[i], sizeof(struct objc_module));
        }
    }
    
    hi->moduleName = malloc(MAX_PATH * sizeof(TCHAR));
    GetModuleFileName((HMODULE)(hi->mhdr), hi->moduleName, MAX_PATH * sizeof(TCHAR));

    appendHeader(hi);

    if (PrintImages) {
        _objc_inform("IMAGES: loading image for %s%s%s\n", 
            hi->fname, 
            headerIsBundle(hi) ? " (bundle)" : "", 
            _objcHeaderIsReplacement(hi) ? " (replacement)":"");
    }

    _read_images(&hi, 1);

    return hi;
}

OBJC_EXPORT void _objc_load_image(HMODULE image, header_info *hinfo)
{
    prepare_load_methods(hinfo);
    call_load_methods();
}

OBJC_EXPORT void _objc_unload_image(HMODULE image, header_info *hinfo)
{
    _objc_fatal("image unload not supported");
}


bool crashlog_header_name(header_info *hi)
{
    return true;
}


// TARGET_OS_WIN32
#elif TARGET_OS_MAC

#include "objc-file-old.h"
#include "objc-file.h"


/***********************************************************************
* bad_magic.
* Return YES if the header has invalid Mach-o magic.
**********************************************************************/
bool bad_magic(const headerType *mhdr)
{
    return (mhdr->magic != MH_MAGIC  &&  mhdr->magic != MH_MAGIC_64  &&  
            mhdr->magic != MH_CIGAM  &&  mhdr->magic != MH_CIGAM_64);
}


static header_info * addHeader(const headerType *mhdr)
{
    header_info *hi;

    if (bad_magic(mhdr)) return NULL;

#if __OBJC2__
    // Look for hinfo from the dyld shared cache.
    hi = preoptimizedHinfoForHeader(mhdr);
    if (hi) {
        // Found an hinfo in the dyld shared cache.

        // Weed out duplicates.
        if (hi->loaded) {
            return NULL;
        }

        // Initialize fields not set by the shared cache
        // hi->next is set by appendHeader
        hi->fname = dyld_image_path_containing_address(hi->mhdr);
        hi->loaded = true;
        hi->inSharedCache = true;

        if (PrintPreopt) {
            _objc_inform("PREOPTIMIZATION: honoring preoptimized header info at %p for %s", hi, hi->fname);
        }

# if DEBUG
        // Verify image_info
        size_t info_size = 0;
        const objc_image_info *image_info = _getObjcImageInfo(mhdr,&info_size);
        assert(image_info == hi->info);
# endif
    }
    else 
#endif
    {
        // Didn't find an hinfo in the dyld shared cache.

        // Weed out duplicates
        for (hi = FirstHeader; hi; hi = hi->next) {
            if (mhdr == hi->mhdr) return NULL;
        }

        // Locate the __OBJC segment
        size_t info_size = 0;
        unsigned long seg_size;
        const objc_image_info *image_info = _getObjcImageInfo(mhdr,&info_size);
        const uint8_t *objc_segment = getsegmentdata(mhdr,SEG_OBJC,&seg_size);
        if (!objc_segment  &&  !image_info) return NULL;

        // Allocate a header_info entry.
        hi = (header_info *)calloc(sizeof(header_info), 1);

        // Set up the new header_info entry.
        hi->mhdr = mhdr;
#if !__OBJC2__
        // mhdr must already be set
        hi->mod_count = 0;
        hi->mod_ptr = _getObjcModules(hi, &hi->mod_count);
#endif
        hi->info = image_info;
        hi->fname = dyld_image_path_containing_address(hi->mhdr);
        hi->loaded = true;
        hi->inSharedCache = false;
        hi->allClassesRealized = NO;
    }

    // dylibs are not allowed to unload
    // ...except those with image_info and nothing else (5359412)
    if (hi->mhdr->filetype == MH_DYLIB  &&  _hasObjcContents(hi)) {
        dlopen(hi->fname, RTLD_NOLOAD);
    }

    appendHeader(hi);
    
    return hi;
}


#if !SUPPORT_GC

const char *_gcForHInfo(const header_info *hinfo)
{
    return "";
}
const char *_gcForHInfo2(const header_info *hinfo)
{
    return "";
}

#else

/***********************************************************************
* _gcForHInfo.
**********************************************************************/
const char *_gcForHInfo(const header_info *hinfo)
{
    if (_objcHeaderRequiresGC(hinfo)) {
        return "requires GC";
    } else if (_objcHeaderSupportsGC(hinfo)) {
        return "supports GC";
    } else {
        return "does not support GC";
    }
}
const char *_gcForHInfo2(const header_info *hinfo)
{
    if (_objcHeaderRequiresGC(hinfo)) {
        return "(requires GC)";
    } else if (_objcHeaderSupportsGC(hinfo)) {
        return "(supports GC)";
    }
    return "";
}


/***********************************************************************
* linksToLibrary
* Returns true if the image links directly to a dylib whose install name 
* is exactly the given name.
**********************************************************************/
bool
linksToLibrary(const header_info *hi, const char *name)
{
    const struct dylib_command *cmd;
    unsigned long i;
    
    cmd = (const struct dylib_command *) (hi->mhdr + 1);
    for (i = 0; i < hi->mhdr->ncmds; i++) {
        if (cmd->cmd == LC_LOAD_DYLIB  ||  cmd->cmd == LC_LOAD_UPWARD_DYLIB  ||
            cmd->cmd == LC_LOAD_WEAK_DYLIB  ||  cmd->cmd == LC_REEXPORT_DYLIB)
        {
            const char *dylib = cmd->dylib.name.offset + (const char *)cmd;
            if (0 == strcmp(dylib, name)) return true;
        }
        cmd = (const struct dylib_command *)((char *)cmd + cmd->cmdsize);
    }

    return false;
}


/***********************************************************************
* check_gc
* Check whether the executable supports or requires GC, and make sure 
* all already-loaded libraries support the executable's GC mode.
* Returns TRUE if the executable wants GC on.
**********************************************************************/
static void check_wants_gc(bool *appWantsGC)
{
    const header_info *hi;

    // Environment variables can override the following.
    if (DisableGC) {
        _objc_inform_on_crash("GC: forcing GC OFF because OBJC_DISABLE_GC is set");
        *appWantsGC = NO;
    }
    else {
        // Find the executable and check its GC bits. 
        // If the executable cannot be found, default to NO.
        // (The executable will not be found if the executable contains 
        // no Objective-C code.)
        *appWantsGC = NO;
        for (hi = FirstHeader; hi != NULL; hi = hi->next) {
            if (hi->mhdr->filetype == MH_EXECUTE) {
                *appWantsGC = _objcHeaderSupportsGC(hi);

                if (PrintGC) {
                    _objc_inform("GC: executable '%s' %s",
                                 hi->fname, _gcForHInfo(hi));
                }

                if (*appWantsGC) {
                    // Exception: AppleScriptObjC apps run without GC in 10.9+
                    // 1. executable defines no classes
                    // 2. executable references NSBundle only
                    // 3. executable links to AppleScriptObjC.framework
                    size_t classcount = 0;
                    size_t refcount = 0;
#if __OBJC2__
                    _getObjc2ClassList(hi, &classcount);
                    _getObjc2ClassRefs(hi, &refcount);
#else
                    if (hi->mod_count == 0  ||  (hi->mod_count == 1 && !hi->mod_ptr[0].symtab)) classcount = 0;
                    else classcount = 1;
                    _getObjcClassRefs(hi, &refcount);
#endif
                    if (classcount == 0  &&  refcount == 1  &&  
                        linksToLibrary(hi, "/System/Library/Frameworks"
                                       "/AppleScriptObjC.framework/Versions/A"
                                       "/AppleScriptObjC"))
                    {
                        *appWantsGC = NO;
                        if (PrintGC) {
                            _objc_inform("GC: forcing GC OFF because this is "
                                         "a trivial AppleScriptObjC app");
                        }
                    }
                }
            }
        }
    }
}


/***********************************************************************
* verify_gc_readiness
* if we want gc, verify that every header describes files compiled
* and presumably ready for gc.
************************************************************************/
static void verify_gc_readiness(bool wantsGC,
                                header_info **hList, uint32_t hCount)
{
    bool busted = NO;
    uint32_t i;

    // Find the libraries and check their GC bits against the app's request
    for (i = 0; i < hCount; i++) {
        header_info *hi = hList[i];
        if (hi->mhdr->filetype == MH_EXECUTE) {
            continue;
        }
        else if (hi->mhdr == &_mh_dylib_header) {
            // libobjc itself works with anything even though it is not 
            // compiled with -fobjc-gc (fixme should it be?)
        } 
        else if (wantsGC  &&  ! _objcHeaderSupportsGC(hi)) {
            // App wants GC but library does not support it - bad
            _objc_inform_now_and_on_crash
                ("'%s' was not compiled with -fobjc-gc or -fobjc-gc-only, "
                 "but the application requires GC",
                 hi->fname);
            busted = YES;
        } 
        else if (!wantsGC  &&  _objcHeaderRequiresGC(hi)) {
            // App doesn't want GC but library requires it - bad
            _objc_inform_now_and_on_crash
                ("'%s' was compiled with -fobjc-gc-only, "
                 "but the application does not support GC",
                 hi->fname);
            busted = YES;            
        }
        
        if (PrintGC) {
            _objc_inform("GC: library '%s' %s", 
                         hi->fname, _gcForHInfo(hi));
        }
    }
    
    if (busted) {
        // GC state is not consistent. 
        // Kill the process unless one of the forcing flags is set.
        if (!DisableGC) {
            _objc_fatal("*** GC capability of application and some libraries did not match");
        }
    }
}


/***********************************************************************
* gc_enforcer
* Make sure that images about to be loaded by dyld are GC-acceptable.
* Images linked to the executable are always permitted; they are 
* enforced inside map_images() itself.
**********************************************************************/
static bool InitialDyldRegistration = NO;
static const char *gc_enforcer(enum dyld_image_states state, 
                               uint32_t infoCount, 
                               const struct dyld_image_info info[])
{
    uint32_t i;

    // Linked images get a free pass
    if (InitialDyldRegistration) return NULL;

    if (PrintImages) {
        _objc_inform("IMAGES: checking %d images for compatibility...", 
                     infoCount);
    }

    for (i = 0; i < infoCount; i++) {
        crashlog_header_name_string(info[i].imageFilePath);

        const headerType *mhdr = (const headerType *)info[i].imageLoadAddress;
        if (bad_magic(mhdr)) continue;

        objc_image_info *image_info;
        size_t size;

        if (mhdr == &_mh_dylib_header) {
            // libobjc itself - OK
            continue;
        }

#if !__OBJC2__
        unsigned long seg_size;
        // 32-bit: __OBJC seg but no image_info means no GC support
        if (!getsegmentdata(mhdr, "__OBJC", &seg_size)) {
            // not objc - assume OK
            continue;
        }
        image_info = _getObjcImageInfo(mhdr, &size);
        if (!image_info) {
            // No image_info - assume GC unsupported
            if (!UseGC) {
                // GC is OFF - ok
                continue;
            } else {
                // GC is ON - bad
                if (PrintImages  ||  PrintGC) {
                    _objc_inform("IMAGES: rejecting %d images because %s doesn't support GC (no image_info)", infoCount, info[i].imageFilePath);
                }
                goto reject;
            }
        }
#else
        // 64-bit: no image_info means no objc at all
        image_info = _getObjcImageInfo(mhdr, &size);
        if (!image_info) {
            // not objc - assume OK
            continue;
        }
#endif

        if (UseGC  &&  !_objcInfoSupportsGC(image_info)) {
            // GC is ON, but image does not support GC
            if (PrintImages  ||  PrintGC) {
                _objc_inform("IMAGES: rejecting %d images because %s doesn't support GC", infoCount, info[i].imageFilePath);
            }
            goto reject;
        }
        if (!UseGC  &&  _objcInfoRequiresGC(image_info)) {
            // GC is OFF, but image requires GC
            if (PrintImages  ||  PrintGC) {
                _objc_inform("IMAGES: rejecting %d images because %s requires GC", infoCount, info[i].imageFilePath);
            }
            goto reject;
        }
    }

    crashlog_header_name_string(NULL);
    return NULL;

 reject:
    crashlog_header_name_string(NULL);
    return "GC capability mismatch";
}

// SUPPORT_GC
#endif


/***********************************************************************
* map_images_nolock
* Process the given images which are being mapped in by dyld.
* All class registration and fixups are performed (or deferred pending
* discovery of missing superclasses etc), and +load methods are called.
*
* info[] is in bottom-up order i.e. libobjc will be earlier in the 
* array than any library that links to libobjc.
*
* Locking: loadMethodLock(old) or runtimeLock(new) acquired by map_images.
**********************************************************************/
#if __OBJC2__
#include "objc-file.h"
#else
#include "objc-file-old.h"
#endif

const char *
map_images_nolock(enum dyld_image_states state, uint32_t infoCount,
                  const struct dyld_image_info infoList[])
{
    static bool firstTime = YES;
    static bool wantsGC = NO;
    uint32_t i;
    header_info *hi;
    header_info *hList[infoCount];
    uint32_t hCount;
    size_t selrefCount = 0;

    // Perform first-time initialization if necessary.
    // This function is called before ordinary library initializers. 
    // fixme defer initialization until an objc-using image is found?
    if (firstTime) {
        preopt_init();
#if SUPPORT_GC
        InitialDyldRegistration = YES;
        dyld_register_image_state_change_handler(dyld_image_state_mapped, 0 /* batch */, &gc_enforcer);
        InitialDyldRegistration = NO;
#endif
    }

    if (PrintImages) {
        _objc_inform("IMAGES: processing %u newly-mapped images...\n", infoCount);
    }


    // Find all images with Objective-C metadata.
    hCount = 0;
    i = infoCount;
    while (i--) {
        const headerType *mhdr = (headerType *)infoList[i].imageLoadAddress;

        hi = addHeader(mhdr);
        if (!hi) {
            // no objc data in this entry
            continue;
        }

        if (mhdr->filetype == MH_EXECUTE) {
            // Size some data structures based on main executable's size
#if __OBJC2__
            size_t count;
            _getObjc2SelectorRefs(hi, &count);
            selrefCount += count;
            _getObjc2MessageRefs(hi, &count);
            selrefCount += count;
#else
            _getObjcSelectorRefs(hi, &selrefCount);
#endif
        }

        hList[hCount++] = hi;
        

        if (PrintImages) {
            _objc_inform("IMAGES: loading image for %s%s%s%s%s\n", 
                         hi->fname, 
                         mhdr->filetype == MH_BUNDLE ? " (bundle)" : "", 
                         _objcHeaderIsReplacement(hi) ? " (replacement)" : "",
                         _objcHeaderOptimizedByDyld(hi)?" (preoptimized)" : "",
                         _gcForHInfo2(hi));
        }
    }

    // Perform one-time runtime initialization that must be deferred until 
    // the executable itself is found. This needs to be done before 
    // further initialization.
    // (The executable may not be present in this infoList if the 
    // executable does not contain Objective-C code but Objective-C 
    // is dynamically loaded later. In that case, check_wants_gc() 
    // will do the right thing.)
#if SUPPORT_GC
    if (firstTime) {
        check_wants_gc(&wantsGC);

        verify_gc_readiness(wantsGC, hList, hCount);
        
        gc_init(wantsGC);  // needs executable for GC decision
    } else {
        verify_gc_readiness(wantsGC, hList, hCount);
    }

    if (wantsGC) {
        // tell the collector about the data segment ranges.
        for (i = 0; i < hCount; ++i) {
            uint8_t *seg;
            unsigned long seg_size;
            hi = hList[i];

            seg = getsegmentdata(hi->mhdr, "__DATA", &seg_size);
            if (seg) gc_register_datasegment((uintptr_t)seg, seg_size);

            seg = getsegmentdata(hi->mhdr, "__DATA_CONST", &seg_size);
            if (seg) gc_register_datasegment((uintptr_t)seg, seg_size);

            seg = getsegmentdata(hi->mhdr, "__DATA_DIRTY", &seg_size);
            if (seg) gc_register_datasegment((uintptr_t)seg, seg_size);

            seg = getsegmentdata(hi->mhdr, "__OBJC", &seg_size);
            if (seg) gc_register_datasegment((uintptr_t)seg, seg_size);
            // __OBJC contains no GC data, but pointers to it are 
            // used as associated reference values (rdar://6953570)
        }
    }
#endif

    if (firstTime) {
        sel_init(wantsGC, selrefCount);
        arr_init();
    }

    _read_images(hList, hCount);

    firstTime = NO;

    return NULL;
}


/***********************************************************************
* load_images_nolock
* Prepares +load in the given images which are being mapped in by dyld.
* Returns YES if there are now +load methods to be called by call_load_methods.
*
* Locking: loadMethodLock(both) and runtimeLock(new) acquired by load_images
**********************************************************************/
bool 
load_images_nolock(enum dyld_image_states state,uint32_t infoCount,
                   const struct dyld_image_info infoList[])
{
    bool found = NO;
    uint32_t i;

    i = infoCount;
    while (i--) {
        const headerType *mhdr = (headerType*)infoList[i].imageLoadAddress;
        if (!hasLoadMethods(mhdr)) continue;

        prepare_load_methods(mhdr);
        found = YES;
    }

    return found;
}


/***********************************************************************
* unmap_image_nolock
* Process the given image which is about to be unmapped by dyld.
* mh is mach_header instead of headerType because that's what 
*   dyld_priv.h says even for 64-bit.
* 
* Locking: loadMethodLock(both) and runtimeLock(new) acquired by unmap_image.
**********************************************************************/
void 
unmap_image_nolock(const struct mach_header *mh)
{
    if (PrintImages) {
        _objc_inform("IMAGES: processing 1 newly-unmapped image...\n");
    }

    header_info *hi;
    
    // Find the runtime's header_info struct for the image
    for (hi = FirstHeader; hi != NULL; hi = hi->next) {
        if (hi->mhdr == (const headerType *)mh) {
            break;
        }
    }

    if (!hi) return;

    if (PrintImages) { 
        _objc_inform("IMAGES: unloading image for %s%s%s%s\n", 
                     hi->fname, 
                     hi->mhdr->filetype == MH_BUNDLE ? " (bundle)" : "", 
                     _objcHeaderIsReplacement(hi) ? " (replacement)" : "", 
                     _gcForHInfo2(hi));
    }

#if SUPPORT_GC
    if (UseGC) {
        uint8_t *seg;
        unsigned long seg_size;

        seg = getsegmentdata(hi->mhdr, "__DATA", &seg_size);
        if (seg) gc_unregister_datasegment((uintptr_t)seg, seg_size);

        seg = getsegmentdata(hi->mhdr, "__DATA_CONST", &seg_size);
        if (seg) gc_unregister_datasegment((uintptr_t)seg, seg_size);

        seg = getsegmentdata(hi->mhdr, "__DATA_DIRTY", &seg_size);
        if (seg) gc_unregister_datasegment((uintptr_t)seg, seg_size);

        seg = getsegmentdata(hi->mhdr, "__OBJC", &seg_size);
        if (seg) gc_unregister_datasegment((uintptr_t)seg, seg_size);
    }
#endif

    _unload_image(hi);

    // Remove header_info from header list
    removeHeader(hi);
    free(hi);
}


/***********************************************************************
* static_init
* Run C++ static constructor functions.
* libc calls _objc_init() before dyld would call our static constructors, 
* so we have to do it ourselves.
**********************************************************************/
static void static_init()
{
#if __OBJC2__
    size_t count;
    Initializer *inits = getLibobjcInitializers(&_mh_dylib_header, &count);
    for (size_t i = 0; i < count; i++) {
        inits[i]();
    }
#endif
}


/***********************************************************************
* _objc_init
* Bootstrap initialization. Registers our image notifier with dyld.
* Old ABI: called by dyld as a library initializer
* New ABI: called by libSystem BEFORE library initialization time
**********************************************************************/

#if !__OBJC2__
static __attribute__((constructor))
#endif
void _objc_init(void)
{
    static bool initialized = false;
    if (initialized) return;
    initialized = true;

    // fixme defer initialization until an objc-using image is found?
    environ_init();
    tls_init();
    static_init();
    lock_init();
    exception_init();
    
    // Register for unmap first, in case some +load unmaps something
    _dyld_register_func_for_remove_image(&unmap_image);
    dyld_register_image_state_change_handler(dyld_image_state_bound,
                                             1/*batch*/, &map_2_images);
    dyld_register_image_state_change_handler(dyld_image_state_dependents_initialized, 0/*not batch*/, &load_images);
}


/***********************************************************************
* _headerForAddress.
* addr can be a class or a category
**********************************************************************/
static const header_info *_headerForAddress(void *addr)
{
#if __OBJC2__
    const char *segnames[] = { "__DATA", "__DATA_CONST", "__DATA_DIRTY" };
#else
    const char *segnames[] = { "__OBJC" };
#endif
    header_info *hi;

    for (hi = FirstHeader; hi != NULL; hi = hi->next) {
        for (size_t i = 0; i < sizeof(segnames)/sizeof(segnames[0]); i++) {
            unsigned long seg_size;            
            uint8_t *seg = getsegmentdata(hi->mhdr, segnames[i], &seg_size);
            if (!seg) continue;
            
            // Is the class in this header?
            if ((uint8_t *)addr >= seg  &&  (uint8_t *)addr < seg + seg_size) {
                return hi;
            }
        }
    }

    // Not found
    return 0;
}


/***********************************************************************
* _headerForClass
* Return the image header containing this class, or NULL.
* Returns NULL on runtime-constructed classes, and the NSCF classes.
**********************************************************************/
const header_info *_headerForClass(Class cls)
{
    return _headerForAddress(cls);
}


/**********************************************************************
* secure_open
* Securely open a file from a world-writable directory (like /tmp)
* If the file does not exist, it will be atomically created with mode 0600
* If the file exists, it must be, and remain after opening: 
*   1. a regular file (in particular, not a symlink)
*   2. owned by euid
*   3. permissions 0600
*   4. link count == 1
* Returns a file descriptor or -1. Errno may or may not be set on error.
**********************************************************************/
int secure_open(const char *filename, int flags, uid_t euid)
{
    struct stat fs, ls;
    int fd = -1;
    bool truncate = NO;
    bool create = NO;

    if (flags & O_TRUNC) {
        // Don't truncate the file until after it is open and verified.
        truncate = YES;
        flags &= ~O_TRUNC;
    }
    if (flags & O_CREAT) {
        // Don't create except when we're ready for it
        create = YES;
        flags &= ~O_CREAT;
        flags &= ~O_EXCL;
    }

    if (lstat(filename, &ls) < 0) {
        if (errno == ENOENT  &&  create) {
            // No such file - create it
            fd = open(filename, flags | O_CREAT | O_EXCL, 0600);
            if (fd >= 0) {
                // File was created successfully.
                // New file does not need to be truncated.
                return fd;
            } else {
                // File creation failed.
                return -1;
            }
        } else {
            // lstat failed, or user doesn't want to create the file
            return -1;
        }
    } else {
        // lstat succeeded - verify attributes and open
        if (S_ISREG(ls.st_mode)  &&  // regular file?
            ls.st_nlink == 1  &&     // link count == 1?
            ls.st_uid == euid  &&    // owned by euid?
            (ls.st_mode & ALLPERMS) == (S_IRUSR | S_IWUSR))  // mode 0600?
        {
            // Attributes look ok - open it and check attributes again
            fd = open(filename, flags, 0000);
            if (fd >= 0) {
                // File is open - double-check attributes
                if (0 == fstat(fd, &fs)  &&  
                    fs.st_nlink == ls.st_nlink  &&  // link count == 1?
                    fs.st_uid == ls.st_uid  &&      // owned by euid?
                    fs.st_mode == ls.st_mode  &&    // regular file, 0600?
                    fs.st_ino == ls.st_ino  &&      // same inode as before?
                    fs.st_dev == ls.st_dev)         // same device as before?
                {
                    // File is open and OK
                    if (truncate) ftruncate(fd, 0);
                    return fd;
                } else {
                    // Opened file looks funny - close it
                    close(fd);
                    return -1;
                }
            } else {
                // File didn't open
                return -1;
            }
        } else {
            // Unopened file looks funny - don't open it
            return -1;
        }
    }
}


bool crashlog_header_name(header_info *hi)
{
    return crashlog_header_name_string(hi ? hi->fname : NULL);
}

bool crashlog_header_name_string(const char *name)
{
    CRSetCrashLogMessage2(name);
    return true;
}


#if TARGET_OS_IPHONE

const char *__crashreporter_info__ = NULL;

const char *CRSetCrashLogMessage(const char *msg)
{
    __crashreporter_info__ = msg;
    return msg;
}
const char *CRGetCrashLogMessage(void)
{
    return __crashreporter_info__;
}

const char *CRSetCrashLogMessage2(const char *msg)
{
    // sorry
    return msg;
}

#endif

// TARGET_OS_MAC
#else


#error unknown OS


#endif
