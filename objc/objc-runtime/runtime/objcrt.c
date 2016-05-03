#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <stdlib.h>
#include "objcrt.h"

// Boundary symbols for metadata sections

#pragma section(".objc_module_info$A",long,read,write)
#pragma data_seg(".objc_module_info$A")
static uintptr_t __objc_modStart = 0;
#pragma section(".objc_module_info$C",long,read,write)
#pragma data_seg(".objc_module_info$C")
static uintptr_t __objc_modEnd = 0;

#pragma section(".objc_protocol$A",long,read,write)
#pragma data_seg(".objc_protocol$A")
static uintptr_t __objc_protoStart = 0;
#pragma section(".objc_protocol$C",long,read,write)
#pragma data_seg(".objc_protocol$C")
static uintptr_t __objc_protoEnd = 0;

#pragma section(".objc_image_info$A",long,read,write)
#pragma data_seg(".objc_image_info$A")
static uintptr_t __objc_iiStart = 0;
#pragma section(".objc_image_info$C",long,read,write)
#pragma data_seg(".objc_image_info$C")
static uintptr_t __objc_iiEnd = 0;

#pragma section(".objc_message_refs$A",long,read,write)
#pragma data_seg(".objc_message_refs$A")
static uintptr_t __objc_selrefsStart = 0;
#pragma section(".objc_message_refs$C",long,read,write)
#pragma data_seg(".objc_message_refs$C")
static uintptr_t __objc_selrefsEnd = 0;

#pragma section(".objc_class_refs$A",long,read,write)
#pragma data_seg(".objc_class_refs$A")
static uintptr_t __objc_clsrefsStart = 0;
#pragma section(".objc_class_refs$C",long,read,write)
#pragma data_seg(".objc_class_refs$C")
static uintptr_t __objc_clsrefsEnd = 0;

#pragma data_seg()

// Merge all metadata into .data
// fixme order these by usage?
#pragma comment(linker, "/MERGE:.objc_module_info=.data")
#pragma comment(linker, "/MERGE:.objc_protocol=.data")
#pragma comment(linker, "/MERGE:.objc_image_info=.data")
#pragma comment(linker, "/MERGE:.objc_message_refs=.data")
#pragma comment(linker, "/MERGE:.objc_class_refs=.data")


// Image initializers

static void *__hinfo = NULL;  // cookie from runtime
extern IMAGE_DOS_HEADER __ImageBase;  // this image's header

static int __objc_init(void)
{
    objc_sections sections = {
        5, 
        &__objc_modStart, &__objc_modEnd, 
        &__objc_protoStart, &__objc_protoEnd, 
        &__objc_iiStart, &__objc_iiEnd, 
        &__objc_selrefsStart, &__objc_selrefsEnd, 
        &__objc_clsrefsStart, &__objc_clsrefsEnd, 
    };
    __hinfo = _objc_init_image((HMODULE)&__ImageBase, &sections);
    return 0;
}

static void __objc_unload(void)
{
    _objc_unload_image((HMODULE)&__ImageBase, __hinfo);
}

static int __objc_load(void)
{
    _objc_load_image((HMODULE)&__ImageBase, __hinfo);
    return 0;
}

// run _objc_init_image ASAP
#pragma section(".CRT$XIAA",long,read,write)
#pragma data_seg(".CRT$XIAA")
static void *__objc_init_fn = &__objc_init;

// run _objc_load_image (+load methods) after all other initializers; 
// otherwise constant NSStrings are not initialized yet
#pragma section(".CRT$XCUO",long,read,write)
#pragma data_seg(".CRT$XCUO")
static void *__objc_load_fn = &__objc_load;

// _objc_unload_image is called by atexit(), not by an image terminator

#pragma data_seg()
