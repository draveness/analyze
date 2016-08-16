// unload3: contains imageinfo but no other objc metadata
// libobjc must not keep it open
// DO NOT USE __OBJC2__; this is a C file.

#include <TargetConditionals.h>

#if TARGET_OS_WIN32  ||  (TARGET_OS_MAC && TARGET_CPU_X86 && !TARGET_IPHONE_SIMULATOR)
// old ABI
int fake[2] __attribute__((section("__OBJC,__image_info")))
#else
// new ABI
int fake[2] __attribute__((section("__DATA,__objc_imageinfo")))
#endif
    = { 0, TARGET_IPHONE_SIMULATOR ? (1<<5) : 0 };

// silence "no debug symbols in executable" warning
void fn(void) { }
