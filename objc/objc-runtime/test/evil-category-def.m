
#if __OBJC2__

#include <mach/shared_region.h>

#if __LP64__
#   define PTR " .quad " 
#else
#   define PTR " .long " 
#endif

#define str(x) #x
#define str2(x) str(x)

__BEGIN_DECLS
void nop(void) { }
__END_DECLS

asm(
    ".section __DATA,__objc_data \n"
    ".align 3 \n"
    "L_category: \n"
    PTR "L_cat_name \n"
    PTR "_OBJC_CLASS_$_NSObject \n"
#if EVIL_INSTANCE_METHOD
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
#if EVIL_CLASS_METHOD
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
    PTR "0 \n"
    PTR "0 \n"

    "L_evil_methods: \n"
    ".long 24 \n"
    ".long 1 \n"
    PTR "L_load \n"
    PTR "L_load \n"
    PTR str2(SHARED_REGION_BASE+SHARED_REGION_SIZE-PAGE_MAX_SIZE) " \n"

    "L_good_methods: \n"
    ".long 24 \n"
    ".long 1 \n"
    PTR "L_load \n"
    PTR "L_load \n"
    PTR "_nop \n"

    ".cstring \n"
    "L_cat_name:   .ascii \"Evil\\0\" \n"
    "L_load:       .ascii \"load\\0\" \n"

    ".section __DATA,__objc_catlist \n"
#if !OMIT_CAT
    PTR "L_category \n"
#endif

    ".section __DATA,__objc_nlcatlist \n"
#if !OMIT_NL_CAT
    PTR "L_category \n"
#endif

    ".text \n"
    );

// __OBJC2__
#endif

void fn(void) { }
