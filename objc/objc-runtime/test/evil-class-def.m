#if __OBJC2__

#include <mach/shared_region.h>

#if __LP64__
#   define PTR " .quad " 
#   define PTRSIZE "8"
#   define LOGPTRSIZE "3"
#else
#   define PTR " .long " 
#   define PTRSIZE "4"
#   define LOGPTRSIZE "2"
#endif

#define str(x) #x
#define str2(x) str(x)

__BEGIN_DECLS
// not id to avoid ARC operations because the class doesn't implement RR methods
void* nop(void* self) { return self; }
__END_DECLS

asm(
    ".globl _OBJC_CLASS_$_Super    \n"
    ".section __DATA,__objc_data  \n"
    ".align 3                     \n"
    "_OBJC_CLASS_$_Super:          \n"
    PTR "_OBJC_METACLASS_$_Super   \n"
    PTR "0                        \n"
    PTR "__objc_empty_cache \n"
    PTR "0 \n"
    PTR "L_ro \n"
    // pad to OBJC_MAX_CLASS_SIZE
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "_OBJC_METACLASS_$_Super:          \n"
    PTR "_OBJC_METACLASS_$_Super   \n"
    PTR "_OBJC_CLASS_$_Super        \n"
    PTR "__objc_empty_cache \n"
    PTR "0 \n"
    PTR "L_meta_ro \n"
    // pad to OBJC_MAX_CLASS_SIZE
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "L_ro: \n"
    ".long 2 \n"
    ".long 0 \n"
    ".long "PTRSIZE" \n"
#if __LP64__
    ".long 0 \n"
#endif
    PTR "0 \n"
    PTR "L_super_name \n"
#if EVIL_SUPER
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
    PTR "0 \n"
    PTR "L_super_ivars \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "L_meta_ro: \n"
    ".long 3 \n"
    ".long 40 \n"
    ".long 40 \n"
#if __LP64__
    ".long 0 \n"
#endif
    PTR "0 \n"
    PTR "L_super_name \n"
#if EVIL_SUPER_META
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"

    ".globl _OBJC_CLASS_$_Sub    \n"
    ".section __DATA,__objc_data  \n"
    ".align 3                     \n"
    "_OBJC_CLASS_$_Sub:          \n"
    PTR "_OBJC_METACLASS_$_Sub   \n"
    PTR "_OBJC_CLASS_$_Super       \n"
    PTR "__objc_empty_cache \n"
    PTR "0 \n"
    PTR "L_sub_ro \n"
    // pad to OBJC_MAX_CLASS_SIZE
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "_OBJC_METACLASS_$_Sub:          \n"
    PTR "_OBJC_METACLASS_$_Super   \n"
    PTR "_OBJC_METACLASS_$_Super        \n"
    PTR "__objc_empty_cache \n"
    PTR "0 \n"
    PTR "L_sub_meta_ro \n"
    // pad to OBJC_MAX_CLASS_SIZE
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "L_sub_ro: \n"
    ".long 2 \n"
    ".long 0 \n"
    ".long "PTRSIZE" \n"
#if __LP64__
    ".long 0 \n"
#endif
    PTR "0 \n"
    PTR "L_sub_name \n"
#if EVIL_SUB
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
    PTR "0 \n"
    PTR "L_sub_ivars \n"
    PTR "0 \n"
    PTR "0 \n"
    ""
    "L_sub_meta_ro: \n"
    ".long 3 \n"
    ".long 40 \n"
    ".long 40 \n"
#if __LP64__
    ".long 0 \n"
#endif
    PTR "0 \n"
    PTR "L_sub_name \n"
#if EVIL_SUB_META
    PTR "L_evil_methods \n"
#else
    PTR "L_good_methods \n"
#endif
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"
    PTR "0 \n"

    "L_evil_methods: \n"
    ".long 3*"PTRSIZE" \n"
    ".long 1 \n"
    PTR "L_load \n"
    PTR "L_load \n"
    PTR str2(SHARED_REGION_BASE+SHARED_REGION_SIZE-PAGE_MAX_SIZE) " \n"

    "L_good_methods: \n"
    ".long 3*"PTRSIZE" \n"
    ".long 2 \n"
    PTR "L_load \n"
    PTR "L_load \n"
    PTR "_nop \n"
    PTR "L_self \n"
    PTR "L_self \n"
    PTR "_nop \n"

    "L_super_ivars: \n"
    ".long 4*"PTRSIZE" \n"
    ".long 1 \n"
    PTR "L_super_ivar_offset \n"
    PTR "L_super_ivar_name \n"
    PTR "L_super_ivar_type \n"
    ".long "LOGPTRSIZE" \n"
    ".long "PTRSIZE" \n"

    "L_sub_ivars: \n"
    ".long 4*"PTRSIZE" \n"
    ".long 1 \n"
    PTR "L_sub_ivar_offset \n"
    PTR "L_sub_ivar_name \n"
    PTR "L_sub_ivar_type \n"
    ".long "LOGPTRSIZE" \n"
    ".long "PTRSIZE" \n"

    "L_super_ivar_offset: \n"
    ".long 0 \n"
    "L_sub_ivar_offset: \n"
    ".long "PTRSIZE" \n"

    ".cstring \n"
    "L_super_name:       .ascii \"Super\\0\" \n"
    "L_sub_name:         .ascii \"Sub\\0\" \n"
    "L_load:             .ascii \"load\\0\" \n"
    "L_self:             .ascii \"self\\0\" \n"
    "L_super_ivar_name:  .ascii \"super_ivar\\0\" \n"
    "L_super_ivar_type:  .ascii \"c\\0\" \n"
    "L_sub_ivar_name:    .ascii \"sub_ivar\\0\" \n"
    "L_sub_ivar_type:    .ascii \"@\\0\" \n"


    ".section __DATA,__objc_classlist \n"
#if !OMIT_SUPER
    PTR "_OBJC_CLASS_$_Super \n"
#endif
#if !OMIT_SUB
    PTR "_OBJC_CLASS_$_Sub \n"
#endif

    ".section __DATA,__objc_nlclslist \n"
#if !OMIT_NL_SUPER
    PTR "_OBJC_CLASS_$_Super \n"
#endif
#if !OMIT_NL_SUB
    PTR "_OBJC_CLASS_$_Sub \n"
#endif

    ".text \n"
);

// __OBJC2__
#endif

void fn(void) { }
