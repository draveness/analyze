// TEST_CFLAGS -Wno-unused-parameter -Wundeclared-selector

#include "test.h"
#include "testroot.i"

#if __cplusplus  &&  !__clang__

int main()
{
    // llvm-g++ is confused by @selector(foo::) and will never be fixed
    succeed(__FILE__);
}

#else

#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/objc-internal.h>
#include <objc/objc-abi.h>
#include <simd/simd.h>

// rdar://21694990 simd.h should have a vector_equal(a, b) function
static bool vector_equal(vector_ulong2 lhs, vector_ulong2 rhs) {
    return vector_all(lhs == rhs);
}

#if __arm64__
    // no stret dispatchers
#   define SUPPORT_STRET 0
#   define objc_msgSend_stret objc_msgSend
#   define objc_msgSendSuper2_stret objc_msgSendSuper2
#   define objc_msgSend_stret_debug objc_msgSend_debug
#   define objc_msgSendSuper2_stret_debug objc_msgSendSuper2_debug
#   define method_invoke_stret method_invoke
#else
#   define SUPPORT_STRET 1
#endif
 
 
#if defined(__arm__) 
// rdar://8331406
#   define ALIGN_() 
#else
#   define ALIGN_() asm(".align 4");
#endif

@interface Super : TestRoot @end

@interface Sub : Super @end

static int state = 0;

static id SELF;

// for typeof() shorthand only
id (*idmsg0)(id, SEL) __attribute__((unused));
long long (*llmsg0)(id, SEL) __attribute__((unused));
// struct stret (*stretmsg0)(id, SEL) __attribute__((unused));
double (*fpmsg0)(id, SEL) __attribute__((unused));
long double (*lfpmsg0)(id, SEL) __attribute__((unused));
vector_ulong2 (*vecmsg0)(id, SEL) __attribute__((unused));

#define VEC1 ((vector_ulong2){1, 1})
#define VEC2 ((vector_ulong2){2, 2})
#define VEC3 ((vector_ulong2){3, 3})
#define VEC4 ((vector_ulong2){4, 4})
#define VEC5 ((vector_ulong2){5, 5})
#define VEC6 ((vector_ulong2){6, 6})
#define VEC7 ((vector_ulong2){7, 7})
#define VEC8 ((vector_ulong2){8, 8})

#define CHECK_ARGS(sel) \
do { \
    testassert(self == SELF); \
    testassert(_cmd == sel_registerName(#sel "::::::::::::::::::::::::::::::::::::"));\
    testassert(vector_all(v1 == 1)); \
    testassert(vector_all(v2 == 2)); \
    testassert(vector_all(v3 == 3)); \
    testassert(vector_all(v4 == 4)); \
    testassert(vector_all(v5 == 5)); \
    testassert(vector_all(v6 == 6)); \
    testassert(vector_all(v7 == 7)); \
    testassert(vector_all(v8 == 8)); \
    testassert(i1 == 1); \
    testassert(i2 == 2); \
    testassert(i3 == 3); \
    testassert(i4 == 4); \
    testassert(i5 == 5); \
    testassert(i6 == 6); \
    testassert(i7 == 7); \
    testassert(i8 == 8); \
    testassert(i9 == 9); \
    testassert(i10 == 10); \
    testassert(i11 == 11); \
    testassert(i12 == 12); \
    testassert(i13 == 13); \
    testassert(f1 == 1.0); \
    testassert(f2 == 2.0); \
    testassert(f3 == 3.0); \
    testassert(f4 == 4.0); \
    testassert(f5 == 5.0); \
    testassert(f6 == 6.0); \
    testassert(f7 == 7.0); \
    testassert(f8 == 8.0); \
    testassert(f9 == 9.0); \
    testassert(f10 == 10.0); \
    testassert(f11 == 11.0); \
    testassert(f12 == 12.0); \
    testassert(f13 == 13.0); \
    testassert(f14 == 14.0); \
    testassert(f15 == 15.0); \
} while (0) 

#define CHECK_ARGS_NOARG(sel) \
do { \
    testassert(self == SELF); \
    testassert(_cmd == sel_registerName(#sel "_noarg"));\
} while (0)

id NIL_RECEIVER;
id ID_RESULT;
long long LL_RESULT = __LONG_LONG_MAX__ - 2LL*__INT_MAX__;
double FP_RESULT = __DBL_MIN__ + __DBL_EPSILON__;
long double LFP_RESULT = __LDBL_MIN__ + __LDBL_EPSILON__;
vector_ulong2 VEC_RESULT = { 0x1234567890abcdefULL, 0xfedcba0987654321ULL };
// STRET_RESULT in test.h

static struct stret zero;

struct stret_i1 {
    uintptr_t i1;
};
struct stret_i2 {
    uintptr_t i1;
    uintptr_t i2;
};
struct stret_i3 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
};
struct stret_i4 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
};
struct stret_i5 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
    uintptr_t i4;
    uintptr_t i5;
};
struct stret_i6 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
    uintptr_t i4;
    uintptr_t i5;
    uintptr_t i6;
};
struct stret_i7 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
    uintptr_t i4;
    uintptr_t i5;
    uintptr_t i6;
    uintptr_t i7;
};
struct stret_i8 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
    uintptr_t i4;
    uintptr_t i5;
    uintptr_t i8;
    uintptr_t i9;
};
struct stret_i9 {
    uintptr_t i1;
    uintptr_t i2;
    uintptr_t i3;
    uintptr_t i4;
    uintptr_t i5;
    uintptr_t i6;
    uintptr_t i7;
    uintptr_t i8;
    uintptr_t i9;
};

struct stret_d1 {
    double d1;
};
struct stret_d2 {
    double d1;
    double d2;
};
struct stret_d3 {
    double d1;
    double d2;
    double d3;
};
struct stret_d4 {
    double d1;
    double d2;
    double d3;
};
struct stret_d5 {
    double d1;
    double d2;
    double d3;
    double d4;
    double d5;
};
struct stret_d6 {
    double d1;
    double d2;
    double d3;
    double d4;
    double d5;
    double d6;
};
struct stret_d7 {
    double d1;
    double d2;
    double d3;
    double d4;
    double d5;
    double d6;
    double d7;
};
struct stret_d8 {
    double d1;
    double d2;
    double d3;
    double d4;
    double d5;
    double d8;
    double d9;
};
struct stret_d9 {
    double d1;
    double d2;
    double d3;
    double d4;
    double d5;
    double d6;
    double d7;
    double d8;
    double d9;
};


@interface Super (Prototypes)

// Method prototypes to pacify -Wundeclared-selector.

-(id)idret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

-(long long)llret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

-(struct stret)stret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

-(double)fpret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

-(long double)lfpret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

-(vector_ulong2)vecret: 
    (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15;

@end


// Zero all volatile registers.
#if __cplusplus
extern "C" 
#endif
void stomp(void);

#if __x86_64__ 
asm("\n .text"
    "\n .globl _stomp"
    "\n _stomp:"
    "\n mov $0, %rax"
    "\n mov $0, %rcx"
    "\n mov $0, %rdx"
    "\n mov $0, %rsi"
    "\n mov $0, %rdi"
    "\n mov $0, %r8"
    "\n mov $0, %r9"
    "\n mov $0, %r10"
    "\n mov $0, %r11"
    "\n xorps %xmm0, %xmm0"
    "\n xorps %xmm1, %xmm1"
    "\n xorps %xmm2, %xmm2"
    "\n xorps %xmm3, %xmm3"
    "\n xorps %xmm4, %xmm4"
    "\n xorps %xmm5, %xmm5"
    "\n xorps %xmm6, %xmm6"
    "\n xorps %xmm7, %xmm7"
    "\n xorps %xmm8, %xmm8"
    "\n xorps %xmm9, %xmm9"
    "\n xorps %xmm10, %xmm10"
    "\n xorps %xmm11, %xmm11"
    "\n xorps %xmm12, %xmm12"
    "\n xorps %xmm13, %xmm13"
    "\n xorps %xmm14, %xmm14"
    "\n xorps %xmm15, %xmm15"
    "\n ret");

#elif __i386__
asm("\n .text"
    "\n .globl _stomp"
    "\n _stomp:"
    "\n mov $0, %eax"
    "\n mov $0, %ecx"
    "\n mov $0, %edx"
    "\n xorps %xmm0, %xmm0"
    "\n xorps %xmm1, %xmm1"
    "\n xorps %xmm2, %xmm2"
    "\n xorps %xmm3, %xmm3"
    "\n xorps %xmm4, %xmm4"
    "\n xorps %xmm5, %xmm5"
    "\n xorps %xmm6, %xmm6"
    "\n xorps %xmm7, %xmm7"
    "\n ret");

#elif __arm64__
asm("\n .text"
    "\n .globl _stomp"
    "\n _stomp:"
    "\n mov x0, #0"
    "\n mov x1, #0"
    "\n mov x2, #0"
    "\n mov x3, #0"
    "\n mov x4, #0"
    "\n mov x5, #0"
    "\n mov x6, #0"
    "\n mov x7, #0"
    "\n mov x8, #0"
    "\n mov x9, #0"
    "\n mov x10, #0"
    "\n mov x11, #0"
    "\n mov x12, #0"
    "\n mov x13, #0"
    "\n mov x14, #0"
    "\n mov x15, #0"
    "\n mov x16, #0"
    "\n mov x17, #0"
    "\n movi d0, #0"
    "\n movi d1, #0"
    "\n movi d2, #0"
    "\n movi d3, #0"
    "\n movi d4, #0"
    "\n movi d5, #0"
    "\n movi d6, #0"
    "\n movi d7, #0"
    "\n ret"
    );

#elif __arm__
asm("\n .text"
    "\n .globl _stomp"
    "\n .thumb_func _stomp"
    "\n _stomp:"
    "\n mov r0, #0"
    "\n mov r1, #0"
    "\n mov r2, #0"
    "\n mov r3, #0"
    "\n mov r9, #0"
    "\n mov r12, #0"
    "\n vmov.i32 q0, #0"
    "\n vmov.i32 q1, #0"
    "\n vmov.i32 q2, #0"
    "\n vmov.i32 q3, #0"
    "\n vmov.i32 q4, #0"
    "\n vmov.i32 q5, #0"
    "\n vmov.i32 q6, #0"
    "\n vmov.i32 q7, #0"
    "\n vmov.i32 q8, #0"
    "\n vmov.i32 q9, #0"
    "\n vmov.i32 q10, #0"
    "\n vmov.i32 q11, #0"
    "\n vmov.i32 q12, #0"
    "\n vmov.i32 q13, #0"
    "\n vmov.i32 q14, #0"
    "\n vmov.i32 q15, #0"
    "\n bx lr"
    );

#else
#   error unknown architecture
#endif


@implementation Super
-(struct stret)stret { return STRET_RESULT; }

// The IMPL_ methods are not called directly. Instead the non IMPL_ name is 
// called. The resolver function installs the real method. This allows 
// the resolver function to stomp on registers to help test register 
// preservation in the uncached path.

+(BOOL) resolveInstanceMethod:(SEL)sel
{
    const char *name = sel_getName(sel);
    if (! strstr(name, "::::::::")) return false;

    testprintf("resolving %s\n", name);

    stomp();
    char *realName;
    asprintf(&realName, "IMPL_%s", name);
    SEL realSel = sel_registerName(realName);
    free(realName);

    IMP imp = class_getMethodImplementation(self, realSel);
    if (imp == &_objc_msgForward) return false;
    return class_addMethod(self, sel, imp, "");
}

-(id)IMPL_idret: 
(vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(idret);
    state = 1;
    return ID_RESULT;
}

-(long long)IMPL_llret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(llret);
    state = 2;
    return LL_RESULT;
}

-(struct stret)IMPL_stret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(stret);
    state = 3;
    return STRET_RESULT;
}

-(double)IMPL_fpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(fpret);
    state = 4;
    return FP_RESULT;
}

-(long double)IMPL_lfpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(lfpret);
    state = 5;
    return LFP_RESULT;
}

-(vector_ulong2)IMPL_vecret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    CHECK_ARGS(vecret);
    state = 6;
    return VEC_RESULT;
}


-(id)idret_noarg
{
    CHECK_ARGS_NOARG(idret);
    state = 11;
    return ID_RESULT;
}

-(long long)llret_noarg
{
    CHECK_ARGS_NOARG(llret);
    state = 12;
    return LL_RESULT;
}

-(struct stret)stret_noarg
{
    CHECK_ARGS_NOARG(stret);
    state = 13;
    return STRET_RESULT;
}

-(double)fpret_noarg
{
    CHECK_ARGS_NOARG(fpret);
    state = 14;
    return FP_RESULT;
}

-(long double)lfpret_noarg
{
    CHECK_ARGS_NOARG(lfpret);
    state = 15;
    return LFP_RESULT;
}

-(vector_ulong2)vecret_noarg
{
    CHECK_ARGS_NOARG(vecret);
    state = 16;
    return VEC_RESULT;
}


-(void)voidret_nop
{
    return;
}

-(void)voidret_nop2
{
    return;
}

-(id)idret_nop
{
    return ID_RESULT;
}

-(long long)llret_nop
{
    return LL_RESULT;
}

-(struct stret)stret_nop
{
    return STRET_RESULT;
}

-(double)fpret_nop
{
    return FP_RESULT;
}

-(long double)lfpret_nop
{
    return LFP_RESULT;
}

-(vector_ulong2)vecret_nop
{
    return VEC_RESULT;
}

#define STRET_IMP(n)                            \
+(struct stret_##n)stret_##n##_zero             \
{                                               \
    struct stret_##n ret;                       \
    bzero(&ret, sizeof(ret));                   \
    return ret;                                 \
}                                               \
+(struct stret_##n)stret_##n##_nonzero          \
{                                               \
    struct stret_##n ret;                       \
    memset(&ret, 0xff, sizeof(ret));            \
    return ret;                                 \
}

STRET_IMP(i1)
STRET_IMP(i2)
STRET_IMP(i3)
STRET_IMP(i4)
STRET_IMP(i5)
STRET_IMP(i6)
STRET_IMP(i7)
STRET_IMP(i8)
STRET_IMP(i9)

STRET_IMP(d1)
STRET_IMP(d2)
STRET_IMP(d3)
STRET_IMP(d4)
STRET_IMP(d5)
STRET_IMP(d6)
STRET_IMP(d7)
STRET_IMP(d8)
STRET_IMP(d9)


+(id)idret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    fail("+idret called instead of -idret");
    CHECK_ARGS(idret);
}

+(long long)llret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    fail("+llret called instead of -llret");
    CHECK_ARGS(llret);
}

+(struct stret)stret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    fail("+stret called instead of -stret");
    CHECK_ARGS(stret);
}

+(double)fpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    fail("+fpret called instead of -fpret");
    CHECK_ARGS(fpret);
}

+(long double)lfpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    fail("+lfpret called instead of -lfpret");
    CHECK_ARGS(lfpret);
}

+(id)idret_noarg
{
    fail("+idret_noarg called instead of -idret_noarg");
    CHECK_ARGS_NOARG(idret);
}

+(long long)llret_noarg
{
    fail("+llret_noarg called instead of -llret_noarg");
    CHECK_ARGS_NOARG(llret);
}

+(struct stret)stret_noarg
{
    fail("+stret_noarg called instead of -stret_noarg");
    CHECK_ARGS_NOARG(stret);
}

+(double)fpret_noarg
{
    fail("+fpret_noarg called instead of -fpret_noarg");
    CHECK_ARGS_NOARG(fpret);
}

+(long double)lfpret_noarg
{
    fail("+lfpret_noarg called instead of -lfpret_noarg");
    CHECK_ARGS_NOARG(lfpret);
}

+(vector_ulong2)vecret_noarg
{
    fail("+vecret_noarg called instead of -vecret_noarg");
    CHECK_ARGS_NOARG(vecret);
}

@end


@implementation Sub

-(id)IMPL_idret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    id result;
    CHECK_ARGS(idret);
    state = 100;
    result = [super idret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 1);
    testassert(result == ID_RESULT);
    state = 101;
    return result;
}

-(long long)IMPL_llret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    long long result;
    CHECK_ARGS(llret);
    state = 100;
    result = [super llret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 2);
    testassert(result == LL_RESULT);
    state = 102;
    return result;
}

-(struct stret)IMPL_stret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    struct stret result;
    CHECK_ARGS(stret);
    state = 100;
    result = [super stret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 3);
    testassert(stret_equal(result, STRET_RESULT));
    state = 103;
    return result;
}

-(double)IMPL_fpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    double result;
    CHECK_ARGS(fpret);
    state = 100;
    result = [super fpret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 4);
    testassert(result == FP_RESULT);
    state = 104;
    return result;
}

-(long double)IMPL_lfpret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    long double result;
    CHECK_ARGS(lfpret);
    state = 100;
    result = [super lfpret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 5);
    testassert(result == LFP_RESULT);
    state = 105;
    return result;
}

-(vector_ulong2)IMPL_vecret: 
   (vector_ulong2)v1 :(vector_ulong2)v2 :(vector_ulong2)v3 :(vector_ulong2)v4 :(vector_ulong2)v5 :(vector_ulong2)v6 :(vector_ulong2)v7 :(vector_ulong2)v8  :(int)i1 :(int)i2 :(int)i3 :(int)i4 :(int)i5 :(int)i6 :(int)i7 :(int)i8 :(int)i9 :(int)i10 :(int)i11 :(int)i12 :(int)i13  :(double)f1 :(double)f2 :(double)f3 :(double)f4 :(double)f5 :(double)f6 :(double)f7 :(double)f8 :(double)f9 :(double)f10 :(double)f11 :(double)f12 :(double)f13 :(double)f14 :(double)f15
{
    vector_ulong2 result;
    CHECK_ARGS(vecret);
    state = 100;
    result = [super vecret:v1:v2:v3:v4:v5:v6:v7:v8:i1:i2:i3:i4:i5:i6:i7:i8:i9:i10:i11:i12:i13:f1:f2:f3:f4:f5:f6:f7:f8:f9:f10:f11:f12:f13:f14:f15];
    testassert(state == 6);
    testassert(vector_equal(result, VEC_RESULT));
    state = 106;
    return result;
}


-(id)idret_noarg
{
    id result;
    CHECK_ARGS_NOARG(idret);
    state = 100;
    result = [super idret_noarg];
    testassert(state == 11);
    testassert(result == ID_RESULT);
    state = 111;
    return result;
}

-(long long)llret_noarg
{
    long long result;
    CHECK_ARGS_NOARG(llret);
    state = 100;
    result = [super llret_noarg];
    testassert(state == 12);
    testassert(result == LL_RESULT);
    state = 112;
    return result;
}

-(struct stret)stret_noarg
{
    struct stret result;
    CHECK_ARGS_NOARG(stret);
    state = 100;
    result = [super stret_noarg];
    testassert(state == 13);
    testassert(stret_equal(result, STRET_RESULT));
    state = 113;
    return result;
}

-(double)fpret_noarg
{
    double result;
    CHECK_ARGS_NOARG(fpret);
    state = 100;
    result = [super fpret_noarg];
    testassert(state == 14);
    testassert(result == FP_RESULT);
    state = 114;
    return result;
}

-(long double)lfpret_noarg
{
    long double result;
    CHECK_ARGS_NOARG(lfpret);
    state = 100;
    result = [super lfpret_noarg];
    testassert(state == 15);
    testassert(result == LFP_RESULT);
    state = 115;
    return result;
}

-(vector_ulong2)vecret_noarg
{
    vector_ulong2 result;
    CHECK_ARGS_NOARG(vecret);
    state = 100;
    result = [super vecret_noarg];
    testassert(state == 16);
    testassert(vector_equal(result, VEC_RESULT));
    state = 116;
    return result;
}

@end


#if OBJC_HAVE_TAGGED_POINTERS

@interface TaggedSub : Sub @end

@implementation TaggedSub : Sub

+(void)initialize
{
    _objc_registerTaggedPointerClass(OBJC_TAG_7, self);
}

@end

#endif


// DWARF checking machinery

#if TARGET_OS_WIN32
// unimplemented on this platform
#elif !__OBJC2__
// 32-bit Mac doesn't use DWARF unwind
#elif TARGET_OS_IPHONE && __arm__
// 32-bit iOS device doesn't use DWARF unwind
#elif __has_feature(objc_arc)
// ARC's extra RR calls hit the traps at the wrong times
#else

#define TEST_DWARF 1

// Classes with no implementations and no cache contents from elsewhere.
@interface SuperDW : TestRoot @end
@implementation SuperDW @end

@interface Sub0DW : SuperDW @end
@implementation Sub0DW @end

@interface SubDW : Sub0DW @end
@implementation SubDW @end

#include <dlfcn.h>
#include <signal.h>
#include <sys/mman.h>
#include <libunwind.h>

#define UNW_STEP_SUCCESS 1
#define UNW_STEP_END     0

bool caught = false;
uintptr_t clobbered;

__BEGIN_DECLS
extern void callit(void *obj, void *sel, void *fn);
extern struct stret callit_stret(void *obj, void *sel, void *fn);
__END_DECLS

#if __x86_64__

#define OTOOL "/usr/bin/xcrun otool -arch x86_64 "

typedef uint8_t insn_t;
#define BREAK_INSN ((insn_t)0xcc)  // int3

uintptr_t r12 = 0;
uintptr_t r13 = 0;
uintptr_t r14 = 0;
uintptr_t r15 = 0;
uintptr_t rbx = 0;
uintptr_t rbp = 0;
uintptr_t rsp = 0;
uintptr_t rip = 0;

void handle_exception(x86_thread_state64_t *state)
{
    unw_cursor_t curs;
    unw_word_t reg;
    int err;
    int step;

    err = unw_init_local(&curs, (unw_context_t *)state);
    testassert(!err);

    step = unw_step(&curs);
    testassert(step == UNW_STEP_SUCCESS);

    err = unw_get_reg(&curs, UNW_X86_64_R12, &reg);
    testassert(!err);
    testassert(reg == r12);

    err = unw_get_reg(&curs, UNW_X86_64_R13, &reg);
    testassert(!err);
    testassert(reg == r13);

    err = unw_get_reg(&curs, UNW_X86_64_R14, &reg);
    testassert(!err);
    testassert(reg == r14);

    err = unw_get_reg(&curs, UNW_X86_64_R15, &reg);
    testassert(!err);
    testassert(reg == r15);

    err = unw_get_reg(&curs, UNW_X86_64_RBX, &reg);
    testassert(!err);
    testassert(reg == rbx);

    err = unw_get_reg(&curs, UNW_X86_64_RBP, &reg);
    testassert(!err);
    testassert(reg == rbp);

    err = unw_get_reg(&curs, UNW_X86_64_RSP, &reg);
    testassert(!err);
    testassert(reg == rsp);

    err = unw_get_reg(&curs, UNW_REG_IP, &reg);
    testassert(!err);
    testassert(reg == rip);


    // set thread state to unwound state
    state->__r12 = r12;
    state->__r13 = r13;
    state->__r14 = r14;
    state->__r15 = r15;
    state->__rbx = rbx;
    state->__rbp = rbp;
    state->__rsp = rsp;
    state->__rip = rip;

    caught = true;
}


void sigtrap(int sig, siginfo_t *info, void *cc)
{
    ucontext_t *uc = (ucontext_t *)cc;
    mcontext_t mc = (mcontext_t)uc->uc_mcontext;

    testprintf("    handled\n");

    testassert(sig == SIGTRAP);
    testassert((uintptr_t)info->si_addr-1 == clobbered);

    handle_exception(&mc->__ss);
    // handle_exception changed register state for continuation
}

__asm__(
"\n  .text"
"\n  .globl _callit"
"\n  _callit:"
// save sp and return address to variables
"\n      movq  (%rsp), %r10"
"\n      movq  %r10, _rip(%rip)"
"\n      movq  %rsp, _rsp(%rip)"
"\n      addq  $8,   _rsp(%rip)"   // rewind to pre-call value
// save other non-volatile registers to variables
"\n      movq  %rbx, _rbx(%rip)"
"\n      movq  %rbp, _rbp(%rip)"
"\n      movq  %r12, _r12(%rip)"
"\n      movq  %r13, _r13(%rip)"
"\n      movq  %r14, _r14(%rip)"
"\n      movq  %r15, _r15(%rip)"
"\n      jmpq  *%rdx"
        );

__asm__(
"\n  .text"
"\n  .globl _callit_stret"
"\n  _callit_stret:"
// save sp and return address to variables
"\n      movq  (%rsp), %r10"
"\n      movq  %r10, _rip(%rip)"
"\n      movq  %rsp, _rsp(%rip)"
"\n      addq  $8,   _rsp(%rip)"   // rewind to pre-call value
// save other non-volatile registers to variables
"\n      movq  %rbx, _rbx(%rip)"
"\n      movq  %rbp, _rbp(%rip)"
"\n      movq  %r12, _r12(%rip)"
"\n      movq  %r13, _r13(%rip)"
"\n      movq  %r14, _r14(%rip)"
"\n      movq  %r15, _r15(%rip)"
"\n      jmpq  *%rcx"
        );


// x86_64

#elif __i386__

#define OTOOL "/usr/bin/xcrun otool -arch i386 "

typedef uint8_t insn_t;
#define BREAK_INSN ((insn_t)0xcc)  // int3

uintptr_t eip = 0;
uintptr_t esp = 0;
uintptr_t ebx = 0;
uintptr_t ebp = 0;
uintptr_t edi = 0;
uintptr_t esi = 0;
uintptr_t espfix = 0;

void handle_exception(i386_thread_state_t *state)
{
    unw_cursor_t curs;
    unw_word_t reg;
    int err;
    int step;

    err = unw_init_local(&curs, (unw_context_t *)state);
    testassert(!err);

    step = unw_step(&curs);
    testassert(step == UNW_STEP_SUCCESS);

    err = unw_get_reg(&curs, UNW_REG_IP, &reg);
    testassert(!err);
    testassert(reg == eip);

    err = unw_get_reg(&curs, UNW_X86_ESP, &reg);
    testassert(!err);
    testassert(reg == esp);

    err = unw_get_reg(&curs, UNW_X86_EBX, &reg);
    testassert(!err);
    testassert(reg == ebx);

    err = unw_get_reg(&curs, UNW_X86_EBP, &reg);
    testassert(!err);
    testassert(reg == ebp);

    err = unw_get_reg(&curs, UNW_X86_EDI, &reg);
    testassert(!err);
    testassert(reg == edi);

    err = unw_get_reg(&curs, UNW_X86_ESI, &reg);
    testassert(!err);
    testassert(reg == esi);


    // set thread state to unwound state
    state->__eip = eip;
    state->__esp = esp + espfix;
    state->__ebx = ebx;
    state->__ebp = ebp;
    state->__edi = edi;
    state->__esi = esi;

    caught = true;
}


void sigtrap(int sig, siginfo_t *info, void *cc)
{
    ucontext_t *uc = (ucontext_t *)cc;
    mcontext_t mc = (mcontext_t)uc->uc_mcontext;

    testprintf("    handled\n");

    testassert(sig == SIGTRAP);
    testassert((uintptr_t)info->si_addr-1 == clobbered);

    handle_exception(&mc->__ss);
    // handle_exception changed register state for continuation
}

__asm__(
"\n  .text"
"\n  .globl _callit"
"\n  _callit:"
// save sp and return address to variables
"\n      call  1f"
"\n  1:  popl  %edx"
"\n      movl  (%esp), %eax"
"\n      movl  %eax, _eip-1b(%edx)"
"\n      movl  %esp, _esp-1b(%edx)"
"\n      addl  $4,   _esp-1b(%edx)"   // rewind to pre-call value
"\n      movl  $0,   _espfix-1b(%edx)"
// save other non-volatile registers to variables
"\n      movl  %ebx, _ebx-1b(%edx)"
"\n      movl  %ebp, _ebp-1b(%edx)"
"\n      movl  %edi, _edi-1b(%edx)"
"\n      movl  %esi, _esi-1b(%edx)"
"\n      jmpl  *12(%esp)"
        );

__asm__(
"\n  .text"
"\n  .globl _callit_stret"
"\n  _callit_stret:"
// save sp and return address to variables
"\n      call  1f"
"\n  1:  popl  %edx"
"\n      movl  (%esp), %eax"
"\n      movl  %eax, _eip-1b(%edx)"
"\n      movl  %esp, _esp-1b(%edx)"
"\n      addl  $4,   _esp-1b(%edx)"   // rewind to pre-call value
"\n      movl  $4,   _espfix-1b(%edx)"
// save other non-volatile registers to variables
"\n      movl  %ebx, _ebx-1b(%edx)"
"\n      movl  %ebp, _ebp-1b(%edx)"
"\n      movl  %edi, _edi-1b(%edx)"
"\n      movl  %esi, _esi-1b(%edx)"
"\n      jmpl  *16(%esp)"
        );


// i386
#elif __arm64__

#include <sys/ucontext.h>

// runs on iOS device, no xcrun command present
#define OTOOL "/usr/bin/otool -arch arm64 "

typedef uint32_t insn_t;
#define BREAK_INSN ((insn_t)0xd4200020)  // brk #1

uintptr_t x19 = 0;
uintptr_t x20 = 0;
uintptr_t x21 = 0;
uintptr_t x22 = 0;
uintptr_t x23 = 0;
uintptr_t x24 = 0;
uintptr_t x25 = 0;
uintptr_t x26 = 0;
uintptr_t x27 = 0;
uintptr_t x28 = 0;
uintptr_t fp = 0;
uintptr_t sp = 0;
uintptr_t pc = 0;

void handle_exception(arm_thread_state64_t *state)
{
    unw_cursor_t curs;
    unw_word_t reg;
    int err;
    int step;

    err = unw_init_local(&curs, (unw_context_t *)state);
    testassert(!err);

    step = unw_step(&curs);
    testassert(step == UNW_STEP_SUCCESS);

    err = unw_get_reg(&curs, UNW_ARM64_X19, &reg);
    testassert(!err);
    testassert(reg == x19);

    err = unw_get_reg(&curs, UNW_ARM64_X20, &reg);
    testassert(!err);
    testassert(reg == x20);

    err = unw_get_reg(&curs, UNW_ARM64_X21, &reg);
    testassert(!err);
    testassert(reg == x21);

    err = unw_get_reg(&curs, UNW_ARM64_X22, &reg);
    testassert(!err);
    testassert(reg == x22);

    err = unw_get_reg(&curs, UNW_ARM64_X23, &reg);
    testassert(!err);
    testassert(reg == x23);

    err = unw_get_reg(&curs, UNW_ARM64_X24, &reg);
    testassert(!err);
    testassert(reg == x24);

    err = unw_get_reg(&curs, UNW_ARM64_X25, &reg);
    testassert(!err);
    testassert(reg == x25);

    err = unw_get_reg(&curs, UNW_ARM64_X26, &reg);
    testassert(!err);
    testassert(reg == x26);

    err = unw_get_reg(&curs, UNW_ARM64_X27, &reg);
    testassert(!err);
    testassert(reg == x27);

    err = unw_get_reg(&curs, UNW_ARM64_X28, &reg);
    testassert(!err);
    testassert(reg == x28);

    err = unw_get_reg(&curs, UNW_ARM64_FP, &reg);
    testassert(!err);
    testassert(reg == fp);

    err = unw_get_reg(&curs, UNW_ARM64_SP, &reg);
    testassert(!err);
    testassert(reg == sp);

    err = unw_get_reg(&curs, UNW_REG_IP, &reg);
    testassert(!err);
    testassert(reg == pc);

    // libunwind restores PC into LR and doesn't track LR
    // err = unw_get_reg(&curs, UNW_ARM64_LR, &reg);
    // testassert(!err);
    // testassert(reg == lr);

    // set thread state to unwound state
    state->__x[19] = x19;
    state->__x[20] = x20;
    state->__x[20] = x21;
    state->__x[22] = x22;
    state->__x[23] = x23;
    state->__x[24] = x24;
    state->__x[25] = x25;
    state->__x[26] = x26;
    state->__x[27] = x27;
    state->__x[28] = x28;
    state->__fp = fp;
    state->__lr = pc;  // libunwind restores PC into LR
    state->__sp = sp;
    state->__pc = pc;

    caught = true;
}


void sigtrap(int sig, siginfo_t *info, void *cc)
{
    ucontext_t *uc = (ucontext_t *)cc;
    struct __darwin_mcontext64 *mc = (struct __darwin_mcontext64 *)uc->uc_mcontext;

    testprintf("    handled\n");

    testassert(sig == SIGTRAP);
    testassert((uintptr_t)info->si_addr == clobbered);

    handle_exception(&mc->__ss);
    // handle_exception changed register state for continuation
}


__asm__(
"\n  .text"
"\n  .globl _callit"
"\n  _callit:"
// save sp and return address to variables
"\n      mov   x16, sp"
"\n      adrp  x17, _sp@PAGE"
"\n      str   x16, [x17, _sp@PAGEOFF]"
"\n      adrp  x17, _pc@PAGE"
"\n      str   lr, [x17, _pc@PAGEOFF]"
// save other non-volatile registers to variables
"\n      adrp  x17, _x19@PAGE"
"\n      str   x19, [x17, _x19@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x20, [x17, _x20@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x21, [x17, _x21@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x22, [x17, _x22@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x23, [x17, _x23@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x24, [x17, _x24@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x25, [x17, _x25@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x26, [x17, _x26@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x27, [x17, _x27@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   x28, [x17, _x28@PAGEOFF]"
"\n      adrp  x17, _x19@PAGE"
"\n      str   fp,  [x17, _fp@PAGEOFF]"
"\n      br    x2"
        );


// arm64
#else

#error unknown architecture

#endif


insn_t set(uintptr_t dst, insn_t newvalue)
{
    uintptr_t start = dst & ~(PAGE_MAX_SIZE-1);
    mprotect((void*)start, PAGE_MAX_SIZE, PROT_READ|PROT_WRITE);
    insn_t oldvalue = *(insn_t *)dst;
    *(insn_t *)dst = newvalue;
    mprotect((void*)start, PAGE_MAX_SIZE, PROT_READ|PROT_EXEC);
    return oldvalue;
}

insn_t clobber(void *fn, uintptr_t offset)
{
    clobbered = (uintptr_t)fn + offset;
    return set((uintptr_t)fn + offset, BREAK_INSN);
}

void unclobber(void *fn, uintptr_t offset, insn_t oldvalue)
{
    set((uintptr_t)fn + offset, oldvalue);
}


uintptr_t *getOffsets(void *symbol, const char *symname, uintptr_t *outBase)
{
    uintptr_t *result = (uintptr_t *)malloc(1000 * sizeof(uintptr_t));
    uintptr_t *end = result + 1000;
    uintptr_t *p = result;

    // find library
    Dl_info dl;
    dladdr(symbol, &dl);

    // call `otool` on library
    unsetenv("DYLD_LIBRARY_PATH");
    unsetenv("DYLD_ROOT_PATH");
    unsetenv("DYLD_INSERT_LIBRARIES");
    unsetenv("DYLD_SHARED_REGION");
    unsetenv("DYLD_SHARED_CACHE_DIR");
    unsetenv("DYLD_SHARED_CACHE_DONT_VALIDATE");
    char *cmd;
    asprintf(&cmd, OTOOL "-tv -p _%s %s", 
             symname, dl.dli_fname);
    testprintf("%s\n", cmd);
    FILE *disa = popen(cmd, "r");
    free(cmd);
    testassert(disa);

    // read past "_symname:" line
    char *line;
    size_t len;
    while ((line = fgetln(disa, &len))) {
        if (0 == strncmp(1+line, symname, MIN(len-1, strlen(symname)))) break;
    }

    // read instructions and save offsets
    char op[128];
    long base = 0;
    long addr;
    while (2 == fscanf(disa, "%lx%s%*[^\n]\n", &addr, op)) {
        if (base == 0) base = addr;
        if (0 != strncmp(op, "nop", 3)) {
            testassert(p < end);
            *p++ = addr - base;
        } else {
            // assume nops are unreached (e.g. alignment padding)
        }
    }
    pclose(disa);

#if __arm64__
    // Also add breakpoints in _objc_msgSend_uncached_impcache
    // (which is the slow path and has a frame to unwind)
    if (0 != strcmp(symname, "_objc_msgSend_uncached_impcache")) {
        uintptr_t base2;
        uintptr_t *more_offsets = getOffsets(symbol, "_objc_msgSend_uncached_impcache", &base2);
        uintptr_t *q = more_offsets;
        // Skip prologue because it's imprecisely modeled in compact unwind
        testassert(*q != ~0UL);
        q++;
        testassert(*q != ~0UL);
        q++;
        while (*q != ~0UL) *p++ = *q++ + base2 - base;
        // Skip return because it's imprecisely modeled in compact unwind
        p--;
        free(more_offsets);
    }
#endif

    testassert(p > result);
    testassert(p < end);
    *p = ~0UL;
#if __x86_64__
    // hack: skip last instruction because libunwind blows up if it's 
    // one byte long and followed by the next function with no NOPs first
    p[-1] = ~0UL;
#endif
    if (outBase) *outBase = base;
    return result;
}

void CALLIT(void *o, void *sel_arg, SEL s, void *f, bool stret) __attribute__((noinline));
void CALLIT(void *o, void *sel_arg, SEL s, void *f, bool stret)
{
    uintptr_t message_ref[2];
    if (sel_arg != s) {
        // fixup dispatch
        // copy to a local buffer to keep sel_arg un-fixed-up
        memcpy(message_ref, sel_arg, sizeof(message_ref));
        sel_arg = message_ref;
    }
    if (!stret) callit(o, sel_arg, f);
#if SUPPORT_STRET
    else callit_stret(o, sel_arg, f);
#else
    else fail("stret?");
#endif
}

void test_dw_forward(void)
{
    return;
}

struct stret test_dw_forward_stret(void)
{
    return zero;
}

// sub = ordinary receiver object
// tagged = tagged receiver object
// SEL = selector to send
// sub_arg = arg to pass in receiver register (may be objc_super struct)
// tagged_arg = arg to pass in receiver register (may be objc_super struct)
// sel_arg = arg to pass in sel register (may be message_ref)
// uncaughtAllowed is the number of acceptable unreachable instructions
//   (for example, the ones that handle the corrupt-cache-error case)
void test_dw(const char *name, id sub, id tagged, bool stret, 
             int uncaughtAllowed)
{

    testprintf("DWARF FOR %s%s\n", name, stret ? " (stret)" : "");

    // We need 2 SELs of each alignment so we can generate hash collisions.
    // sel_registerName() never returns those alignments because they 
    // differ from malloc's alignment. So we create lots of compiled-in 
    // SELs here and hope something fits.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL sel = @selector(a);
    SEL lotsOfSels[] = {
        @selector(a1), @selector(a2), @selector(a3), @selector(a4), 
        @selector(a5), @selector(a6), @selector(a7), @selector(a8), 
        @selector(aa), @selector(ab), @selector(ac), @selector(ad), 
        @selector(ae), @selector(af), @selector(ag), @selector(ah), 
        @selector(A1), @selector(A2), @selector(A3), @selector(A4), 
        @selector(A5), @selector(A6), @selector(A7), @selector(A8), 
        @selector(AA), @selector(Ab), @selector(Ac), @selector(Ad), 
        @selector(Ae), @selector(Af), @selector(Ag), @selector(Ah), 
        @selector(bb1), @selector(bb2), @selector(bb3), @selector(bb4), 
        @selector(bb5), @selector(bb6), @selector(bb7), @selector(bb8), 
        @selector(bba), @selector(bbb), @selector(bbc), @selector(bbd), 
        @selector(bbe), @selector(bbf), @selector(bbg), @selector(bbh), 
        @selector(BB1), @selector(BB2), @selector(BB3), @selector(BB4), 
        @selector(BB5), @selector(BB6), @selector(BB7), @selector(BB8), 
        @selector(BBa), @selector(BBb), @selector(BBc), @selector(BBd), 
        @selector(BBe), @selector(BBf), @selector(BBg), @selector(BBh), 
        @selector(ccc1), @selector(ccc2), @selector(ccc3), @selector(ccc4), 
        @selector(ccc5), @selector(ccc6), @selector(ccc7), @selector(ccc8), 
        @selector(ccca), @selector(cccb), @selector(cccc), @selector(cccd), 
        @selector(ccce), @selector(cccf), @selector(cccg), @selector(ccch), 
        @selector(CCC1), @selector(CCC2), @selector(CCC3), @selector(CCC4), 
        @selector(CCC5), @selector(CCC6), @selector(CCC7), @selector(CCC8), 
        @selector(CCCa), @selector(CCCb), @selector(CCCc), @selector(CCCd), 
        @selector(CCCe), @selector(CCCf), @selector(CCCg), @selector(CCCh), 
    };
#pragma clang diagnostic pop
    
    {
        IMP imp = stret ? (IMP)test_dw_forward_stret : (IMP)test_dw_forward;
        Class cls = object_getClass(sub);
        Class tagcls = object_getClass(tagged);
        class_replaceMethod(cls, sel, imp, "");
        class_replaceMethod(tagcls, sel, imp, "");
        for (size_t i = 0; i < sizeof(lotsOfSels)/sizeof(lotsOfSels[0]); i++) {
            class_replaceMethod(cls, lotsOfSels[i], imp, "");
            class_replaceMethod(tagcls, lotsOfSels[i], imp, "");
        }
    }
    
    #define ALIGNCOUNT 16
    SEL sels[ALIGNCOUNT][2] = {{0}};
    for (int align = 0; align < ALIGNCOUNT; align++) {
        for (size_t i = 0; i < sizeof(lotsOfSels)/sizeof(lotsOfSels[0]); i++) {
            if ((uintptr_t)(void*)lotsOfSels[i] % ALIGNCOUNT == align) {
                if (sels[align][0]) {
                    sels[align][1] = lotsOfSels[i];
                } else {
                    sels[align][0] = lotsOfSels[i];
                }
            }
        }
        if (!sels[align][0]) fail("no SEL with alignment %d", align);
        if (!sels[align][1]) fail("only one SEL with alignment %d", align);
    }

    void *fn = dlsym(RTLD_DEFAULT, name);
    testassert(fn);

    // argument substitutions

    void *sub_arg = (void*)objc_unretainedPointer(sub);
    void *tagged_arg = (void*)objc_unretainedPointer(tagged);
    void *sel_arg = (void*)sel;

    struct objc_super sup_st = { sub, object_getClass(sub) };
    struct objc_super tagged_sup_st = { tagged, object_getClass(tagged) };
    struct { void *imp; SEL sel; } message_ref = { fn, sel };

    Class cache_cls = object_getClass(sub);

    if (strstr(name, "Super")) {
        // super version - replace receiver with objc_super
        // clear caches of superclass
        cache_cls = class_getSuperclass(cache_cls);
        sub_arg = &sup_st;
        tagged_arg = &tagged_sup_st;
    }

    if (strstr(name, "_fixup")) {
        // fixup version - replace sel with message_ref
        sel_arg = &message_ref;
    }


    uintptr_t *insnOffsets = getOffsets(fn, name, nil);
    uintptr_t offset;
    int uncaughtCount = 0;
    for (int oo = 0; insnOffsets[oo] != ~0UL; oo++) {
        offset = insnOffsets[oo];
        testprintf("OFFSET %lu\n", offset);

        insn_t saved_insn = clobber(fn, offset);
        caught = false;

        // nil
        if ((void*)objc_unretainedPointer(sub) == sub_arg) {
            SELF = nil;
            testprintf("  nil\n");
            CALLIT(nil, sel_arg, sel, fn, stret);
            CALLIT(nil, sel_arg, sel, fn, stret);
        }

        // uncached
        SELF = sub;
        testprintf("  uncached\n");
        _objc_flush_caches(cache_cls);
        CALLIT(sub_arg, sel_arg, sel, fn, stret);
        _objc_flush_caches(cache_cls);
        CALLIT(sub_arg, sel_arg, sel, fn, stret);

        // cached
        SELF = sub;
        testprintf("  cached\n");
        CALLIT(sub_arg, sel_arg, sel, fn, stret);
        CALLIT(sub_arg, sel_arg, sel, fn, stret);
        
        // uncached,tagged
        SELF = tagged;
        testprintf("  uncached,tagged\n");
        _objc_flush_caches(cache_cls);
        CALLIT(tagged_arg, sel_arg, sel, fn, stret);
        _objc_flush_caches(cache_cls);
        CALLIT(tagged_arg, sel_arg, sel, fn, stret);

        // cached,tagged
        SELF = tagged;
        testprintf("  cached,tagged\n");
        CALLIT(tagged_arg, sel_arg, sel, fn, stret);
        CALLIT(tagged_arg, sel_arg, sel, fn, stret);

        // multiple SEL alignments, collisions, wraps
        SELF = sub;
        for (int a = 0; a < ALIGNCOUNT; a++) {
            testprintf("  cached, SEL alignment %d\n", a);

            // Count both up and down to be independent of 
            // implementation's cache scan direction

            _objc_flush_caches(cache_cls);
            for (int x2 = 0; x2 < 8; x2++) {
                for (int s = 0; s < 4; s++) {
                    int align = (a+s) % ALIGNCOUNT;
                    CALLIT(sub_arg, sels[align][0], sels[align][0], fn, stret);
                    CALLIT(sub_arg, sels[align][1], sels[align][1], fn, stret);
                }
            }

            _objc_flush_caches(cache_cls);
            for (int x2 = 0; x2 < 8; x2++) {
                for (int s = 0; s < 4; s++) {
                    int align = abs(a-s) % ALIGNCOUNT;
                    CALLIT(sub_arg, sels[align][0], sels[align][0], fn, stret);
                    CALLIT(sub_arg, sels[align][1], sels[align][1], fn, stret);
                }
            }
        }
        
        unclobber(fn, offset, saved_insn);

        // remember offsets that were caught by none of the above
        if (caught) {
            insnOffsets[oo] = 0;
        } else {
            uncaughtCount++;
            testprintf("offset %s+%lu not caught (%d/%d)\n", 
                       name, offset, uncaughtCount, uncaughtAllowed);
        }
    }

    // Complain if too many offsets went uncaught.
    // Acceptably-uncaught offsets include the corrupt-cache-error handler.
    if (uncaughtCount != uncaughtAllowed) {
        for (int oo = 0; insnOffsets[oo] != ~0UL; oo++) {
            if (insnOffsets[oo]) {
                fprintf(stderr, "BAD: offset %s+%lu not caught\n", 
                        name, insnOffsets[oo]);
            }
        }
        fail("wrong instructions not reached for %s (missed %d, expected %d)",
             name, uncaughtCount, uncaughtAllowed);
    }

    free(insnOffsets);
}


// TEST_DWARF
#endif


void test_basic(id receiver)
{
    id idval;
    long long llval;
    struct stret stretval;
    double fpval;
    long double lfpval;
    vector_ulong2 vecval;

    // message uncached 
    // message uncached long long
    // message uncached stret
    // message uncached fpret
    // message uncached fpret long double
    // message uncached noarg (as above)
    // message cached 
    // message cached long long
    // message cached stret
    // message cached fpret
    // message cached fpret long double
    // message cached noarg (as above)
    // fixme verify that uncached lookup didn't happen the 2nd time?
    SELF = receiver;
    for (int i = 0; i < 5; i++) {
        testprintf("idret\n");
        state = 0;
        idval = nil;
        idval = [receiver idret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 101);
        testassert(idval == ID_RESULT);
        
        testprintf("llret\n");
        llval = 0;
        llval = [receiver llret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 102);
        testassert(llval == LL_RESULT);
        
        testprintf("stret\n");
        stretval = zero;
        stretval = [receiver stret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 103);
        testassert(stret_equal(stretval, STRET_RESULT));
        
        testprintf("fpret\n");
        fpval = 0;
        fpval = [receiver fpret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 104);
        testassert(fpval == FP_RESULT);
        
        testprintf("lfpret\n");
        lfpval = 0;
        lfpval = [receiver lfpret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 105);
        testassert(lfpval == LFP_RESULT);
        
        testprintf("vecret\n");
        vecval = 0;
        vecval = [receiver vecret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 106);
        testassert(vector_equal(vecval, VEC_RESULT));

#if __OBJC2__
        // explicitly call noarg messenger, even if compiler doesn't emit it
        state = 0;
        testprintf("idret noarg\n");
        idval = nil;
        idval = ((typeof(idmsg0))objc_msgSend_noarg)(receiver, @selector(idret_noarg));
        testassert(state == 111);
        testassert(idval == ID_RESULT);
        
        testprintf("llret noarg\n");
        llval = 0;
        llval = ((typeof(llmsg0))objc_msgSend_noarg)(receiver, @selector(llret_noarg));
        testassert(state == 112);
        testassert(llval == LL_RESULT);
        /*
          no objc_msgSend_stret_noarg
        stretval = zero;
        stretval = ((typeof(stretmsg0))objc_msgSend_stret_noarg)(receiver, @selector(stret_noarg));
        stretval = [receiver stret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
        testassert(state == 113);
        testassert(stret_equal(stretval, STRET_RESULT));
        */
# if !__i386__
        testprintf("fpret noarg\n");
        fpval = 0;
        fpval = ((typeof(fpmsg0))objc_msgSend_noarg)(receiver, @selector(fpret_noarg));
        testassert(state == 114);
        testassert(fpval == FP_RESULT);

        testprintf("vecret noarg\n");
        vecval = 0;
        vecval = ((typeof(vecmsg0))objc_msgSend_noarg)(receiver, @selector(vecret_noarg));
        testassert(state == 116);
        testassert(vector_equal(vecval, VEC_RESULT));
# endif
# if !__i386__ && !__x86_64__
        testprintf("lfpret noarg\n");
        lfpval = 0;
        lfpval = ((typeof(lfpmsg0))objc_msgSend_noarg)(receiver, @selector(lfpret_noarg));
        testassert(state == 115);
        testassert(lfpval == LFP_RESULT);
# endif
#endif
    }

    testprintf("basic done\n");
}

int main()
{
  PUSH_POOL {
    int i;

    id idval;
    long long llval;
    struct stret stretval;
    double fpval;
    long double lfpval;
    vector_ulong2 vecval;

#if __x86_64__
    struct stret *stretptr;
#endif

    uint64_t startTime;
    uint64_t totalTime;
    uint64_t targetTime;

    Method idmethod;
    Method llmethod;
    Method stretmethod;
    Method fpmethod;
    Method lfpmethod;
    Method vecmethod;

    id (*idfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);
    long long (*llfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);
    struct stret (*stretfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);
    double (*fpfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);
    long double (*lfpfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);
    vector_ulong2 (*vecfn)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double);

    id (*idmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    id (*idmsgsuper)(struct objc_super *, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    long long (*llmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    struct stret (*stretmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    struct stret (*stretmsgsuper)(struct objc_super *, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    double (*fpmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    long double (*lfpmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));
    vector_ulong2 (*vecmsg)(id, SEL, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double) __attribute__((unused));

    // get +initialize out of the way
    [Sub class];
#if OBJC_HAVE_TAGGED_POINTERS
    [TaggedSub class];
#endif

    ID_RESULT = [Super new];

    Sub *sub = [Sub new];
    Super *sup = [Super new];
#if OBJC_HAVE_TAGGED_POINTERS
    TaggedSub *tagged = objc_unretainedObject(_objc_makeTaggedPointer(OBJC_TAG_7, 999));
#endif

    // Basic cached and uncached dispatch.
    // Do this first before anything below caches stuff.
    testprintf("basic\n");
    test_basic(sub);
#if OBJC_HAVE_TAGGED_POINTERS
    testprintf("basic tagged\n");
    test_basic(tagged);
#endif

    idmethod = class_getInstanceMethod([Super class], @selector(idret::::::::::::::::::::::::::::::::::::));
    testassert(idmethod);
    llmethod = class_getInstanceMethod([Super class], @selector(llret::::::::::::::::::::::::::::::::::::));
    testassert(llmethod);
    stretmethod = class_getInstanceMethod([Super class], @selector(stret::::::::::::::::::::::::::::::::::::));
    testassert(stretmethod);
    fpmethod = class_getInstanceMethod([Super class], @selector(fpret::::::::::::::::::::::::::::::::::::));
    testassert(fpmethod);
    lfpmethod = class_getInstanceMethod([Super class], @selector(lfpret::::::::::::::::::::::::::::::::::::));
    testassert(lfpmethod);
    vecmethod = class_getInstanceMethod([Super class], @selector(vecret::::::::::::::::::::::::::::::::::::));
    testassert(vecmethod);

    idfn = (id (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke;
    llfn = (long long (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke;
    stretfn = (struct stret (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke_stret;
    fpfn = (double (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke;
    lfpfn = (long double (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke;
    vecfn = (vector_ulong2 (*)(id, Method, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, vector_ulong2, int, int, int, int, int, int, int, int, int, int, int, int, int, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double)) method_invoke;

    // cached message performance
    // catches failure to cache or (abi=2) failure to fixup (#5584187)
    // fixme unless they all fail
    // `.align 4` matches loop alignment to make -O0 work
    // fill cache first
    testprintf("time checks\n");

    SELF = sub;
    [sub voidret_nop];
    [sub voidret_nop2];
    [sub llret_nop];
    [sub stret_nop];
    [sub fpret_nop];
    [sub lfpret_nop];
    [sub vecret_nop];
    [sub voidret_nop];
    [sub voidret_nop2];
    [sub llret_nop];
    [sub stret_nop];
    [sub fpret_nop];
    [sub lfpret_nop];
    [sub vecret_nop];
    [sub voidret_nop];
    [sub voidret_nop2];
    [sub llret_nop];
    [sub stret_nop];
    [sub fpret_nop];
    [sub lfpret_nop];
    [sub vecret_nop];

    // Some of these times have high variance on some compilers. 
    // The errors we're trying to catch should be catastrophically slow, 
    // so the margins here are generous to avoid false failures.

    // Use voidret because id return is too slow for perf test with ARC.

    // Pick smallest of voidret_nop and voidret_nop2 time
    // in the hopes that one of them didn't collide in the method cache.

#define COUNT 1000000

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub voidret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    testprintf("time: voidret  %llu\n", totalTime);
    targetTime = totalTime;

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub voidret_nop2];  
    }
    totalTime = mach_absolute_time() - startTime;
    testprintf("time: voidret2  %llu\n", totalTime);
    if (totalTime < targetTime) targetTime = totalTime;

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub llret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    timecheck("llret ", totalTime, targetTime * 0.7, targetTime * 2.0);

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub stret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    timecheck("stret ", totalTime, targetTime * 0.7, targetTime * 5.0);

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {        
        [sub fpret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    timecheck("fpret ", totalTime, targetTime * 0.7, targetTime * 4.0);

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub lfpret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    timecheck("lfpret", totalTime, targetTime * 0.7, targetTime * 4.0);

    startTime = mach_absolute_time();
    ALIGN_();
    for (i = 0; i < COUNT; i++) {
        [sub vecret_nop];
    }
    totalTime = mach_absolute_time() - startTime;
    timecheck("vecret", totalTime, targetTime * 0.7, targetTime * 4.0);

#if __arm64__
    // Removing this testwarn(), or changing voidret_nop to nop;ret, 
    // changes the voidret_nop and stret_nop times above by a factor of 2.
    testwarn("rdar://13896922 nop;ret is faster than ret?");
#endif

#undef COUNT

    // method_invoke 
    // method_invoke long long
    // method_invoke_stret stret
    // method_invoke_stret fpret
    // method_invoke fpret long double
    testprintf("method_invoke\n");

    SELF = sup;

    state = 0;
    idval = nil;
    idval = (*idfn)(sup, idmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 1);
    testassert(idval == ID_RESULT);

    llval = 0;
    llval = (*llfn)(sup, llmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 2);
    testassert(llval == LL_RESULT);

    stretval = zero;
    stretval = (*stretfn)(sup, stretmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 3);
    testassert(stret_equal(stretval, STRET_RESULT));

    fpval = 0;
    fpval = (*fpfn)(sup, fpmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 4);
    testassert(fpval == FP_RESULT);

    lfpval = 0;
    lfpval = (*lfpfn)(sup, lfpmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 5);
    testassert(lfpval == LFP_RESULT);

    vecval = 0;
    vecval = (*vecfn)(sup, vecmethod, VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 6);
    testassert(vector_equal(vecval, VEC_RESULT));


    // message to nil
    // message to nil long long
    // message to nil stret
    // message to nil fpret
    // message to nil fpret long double
    // Use NIL_RECEIVER to avoid compiler optimizations.
    testprintf("message to nil\n");

    state = 0;
    idval = ID_RESULT;
    idval = [(id)NIL_RECEIVER idret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
    testassert(idval == nil);
    
    state = 0;
    llval = LL_RESULT;
    llval = [(id)NIL_RECEIVER llret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
    testassert(llval == 0LL);
    
    state = 0;
    stretval = zero;
    stretval = [(id)NIL_RECEIVER stret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
#if __clang__
    testassert(0 == memcmp(&stretval, &zero, sizeof(stretval)));
#else
    // no stret result guarantee
#endif

#if __x86_64__
    // check stret return register
    state = 0;
    stretval = zero;
    stretptr = ((struct stret *(*)(struct stret *, id, SEL))objc_msgSend_stret)
        (&stretval, nil, @selector(stret_nop));
    testassert(stretptr == &stretval);
    testassert(state == 0);
    // no stret result guarantee for hand-written calls, even with clang
#endif

#if __i386__
    // check struct-return address stack pop
    for (int i = 0; i < 10000000; i++) {
        state = 0;
        ((struct stret (*)(id, SEL))objc_msgSend_stret)
            (nil, @selector(stret_nop));
    }
#endif

    state = 0;
    fpval = FP_RESULT;
    fpval = [(id)NIL_RECEIVER fpret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
    testassert(fpval == 0.0);
    
    state = 0;
    lfpval = LFP_RESULT;
    lfpval = [(id)NIL_RECEIVER lfpret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
    testassert(lfpval == 0.0);
    
    state = 0;
    vecval = VEC_RESULT;
    vecval = [(id)NIL_RECEIVER vecret :VEC1:VEC2:VEC3:VEC4:VEC5:VEC6:VEC7:VEC8:1:2:3:4:5:6:7:8:9:10:11:12:13:1.0:2.0:3.0:4.0:5.0:6.0:7.0:8.0:9.0:10.0:11.0:12.0:13.0:14.0:15.0];
    testassert(state == 0);
    testassert(vector_all(vecval == 0));

    // message to nil, different struct types
    // This verifies that ordinary objc_msgSend() erases enough registers 
    // for structs that return in registers.
#define TEST_NIL_STRUCT(i,n)                                            \
    do {                                                                \
        struct stret_##i##n z;                                          \
        bzero(&z, sizeof(z));                                           \
        [Super stret_i##n##_nonzero];                                   \
        [Super stret_d##n##_nonzero];                                   \
        struct stret_##i##n val = [(id)NIL_RECEIVER stret_##i##n##_zero]; \
        testassert(0 == memcmp(&z, &val, sizeof(val)));             \
    } while (0)

    TEST_NIL_STRUCT(i,1);
    TEST_NIL_STRUCT(i,2);
    TEST_NIL_STRUCT(i,3);
    TEST_NIL_STRUCT(i,4);
    TEST_NIL_STRUCT(i,5);
    TEST_NIL_STRUCT(i,6);
    TEST_NIL_STRUCT(i,7);
    TEST_NIL_STRUCT(i,8);
    TEST_NIL_STRUCT(i,9);

#if __i386__
    testwarn("rdar://16267205 i386 struct{float} and struct{double}");
#else
    TEST_NIL_STRUCT(d,1);
#endif
    TEST_NIL_STRUCT(d,2);
    TEST_NIL_STRUCT(d,3);
    TEST_NIL_STRUCT(d,4);
    TEST_NIL_STRUCT(d,5);
    TEST_NIL_STRUCT(d,6);
    TEST_NIL_STRUCT(d,7);
    TEST_NIL_STRUCT(d,8);
    TEST_NIL_STRUCT(d,9);


#if __OBJC2__
    // message to nil noarg
    // explicitly call noarg messenger, even if compiler doesn't emit it
    state = 0;
    idval = ID_RESULT;
    idval = ((typeof(idmsg0))objc_msgSend_noarg)(nil, @selector(idret_noarg));
    testassert(state == 0);
    testassert(idval == nil);
    
    state = 0;
    llval = LL_RESULT;
    llval = ((typeof(llmsg0))objc_msgSend_noarg)(nil, @selector(llret_noarg));
    testassert(state == 0);
    testassert(llval == 0LL);

    // no stret_noarg messenger

# if !__i386__
    state = 0;
    fpval = FP_RESULT;
    fpval = ((typeof(fpmsg0))objc_msgSend_noarg)(nil, @selector(fpret_noarg));
    testassert(state == 0);
    testassert(fpval == 0.0);

    state = 0;
    vecval = VEC_RESULT;
    vecval = ((typeof(vecmsg0))objc_msgSend_noarg)(nil, @selector(vecret_noarg));
    testassert(state == 0);
    testassert(vector_all(vecval == 0));
# endif
# if !__i386__ && !__x86_64__
    state = 0;
    lfpval = LFP_RESULT;
    lfpval = ((typeof(lfpmsg0))objc_msgSend_noarg)(nil, @selector(lfpret_noarg));
    testassert(state == 0);
    testassert(lfpval == 0.0);
# endif
#endif


#if __OBJC2__
    // rdar://8271364 objc_msgSendSuper2 must not change objc_super
    testprintf("super struct\n");
    struct objc_super sup_st = {
        sub, 
        object_getClass(sub), 
    };

    SELF = sub;

    state = 100;
    idval = nil;
    idval = ((id(*)(struct objc_super *, SEL, vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2, int,int,int,int,int,int,int,int,int,int,int,int,int, double,double,double,double,double,double,double,double,double,double,double,double,double,double,double))objc_msgSendSuper2) (&sup_st, @selector(idret::::::::::::::::::::::::::::::::::::), VEC1,VEC2,VEC3,VEC4,VEC5,VEC6,VEC7,VEC8, 1,2,3,4,5,6,7,8,9,10,11,12,13, 1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0);
    testassert(state == 1);
    testassert(idval == ID_RESULT);
    testassert(sup_st.receiver == sub);
    testassert(sup_st.super_class == object_getClass(sub));

    state = 100;
    stretval = zero;
    stretval = ((struct stret(*)(struct objc_super *, SEL, vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2,vector_ulong2, int,int,int,int,int,int,int,int,int,int,int,int,int, double,double,double,double,double,double,double,double,double,double,double,double,double,double,double))objc_msgSendSuper2_stret) (&sup_st, @selector(stret::::::::::::::::::::::::::::::::::::), VEC1,VEC2,VEC3,VEC4,VEC5,VEC6,VEC7,VEC8, 1,2,3,4,5,6,7,8,9,10,11,12,13, 1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0);
    testassert(state == 3);
    testassert(stret_equal(stretval, STRET_RESULT));
    testassert(sup_st.receiver == sub);
    testassert(sup_st.super_class == object_getClass(sub));
#endif

#if __OBJC2__  &&  !__arm64__
    // Debug messengers.
    testprintf("debug messengers\n");

    state = 0;
    idmsg = (typeof(idmsg))objc_msgSend_debug;
    idval = nil;
    idval = (*idmsg)(sub, @selector(idret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 101);
    testassert(idval == ID_RESULT);
    
    state = 0;
    llmsg = (typeof(llmsg))objc_msgSend_debug;
    llval = 0;
    llval = (*llmsg)(sub, @selector(llret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 102);
    testassert(llval == LL_RESULT);
    
    state = 0;
    stretmsg = (typeof(stretmsg))objc_msgSend_stret_debug;
    stretval = zero;
    stretval = (*stretmsg)(sub, @selector(stret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 103);
    testassert(stret_equal(stretval, STRET_RESULT));
    
    state = 100;
    sup_st.receiver = sub;
    sup_st.super_class = object_getClass(sub);
    idmsgsuper = (typeof(idmsgsuper))objc_msgSendSuper2_debug;
    idval = nil;
    idval = (*idmsgsuper)(&sup_st, @selector(idret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 1);
    testassert(idval == ID_RESULT);
    
    state = 100;
    sup_st.receiver = sub;
    sup_st.super_class = object_getClass(sub);
    stretmsgsuper = (typeof(stretmsgsuper))objc_msgSendSuper2_stret_debug;
    stretval = zero;
    stretval = (*stretmsgsuper)(&sup_st, @selector(stret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 3);
    testassert(stret_equal(stretval, STRET_RESULT));

#if __i386__
    state = 0;
    fpmsg = (typeof(fpmsg))objc_msgSend_fpret_debug;
    fpval = 0;
    fpval = (*fpmsg)(sub, @selector(fpret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 104);
    testassert(fpval == FP_RESULT);
#endif
#if __x86_64__
    state = 0;
    lfpmsg = (typeof(lfpmsg))objc_msgSend_fpret_debug;
    lfpval = 0;
    lfpval = (*lfpmsg)(sub, @selector(lfpret::::::::::::::::::::::::::::::::::::), VEC1, VEC2, VEC3, VEC4, VEC5, VEC6, VEC7, VEC8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0);
    testassert(state == 105);
    testassert(lfpval == LFP_RESULT);

    // fixme fp2ret
#endif

// debug messengers
#endif


#if !TEST_DWARF
    testwarn("no unwind tables in this configuration");
#else
    // DWARF unwind tables
    testprintf("unwind tables\n");

    // install exception handler
    struct sigaction act;
    act.sa_sigaction = sigtrap;
    act.sa_mask = 0;
    act.sa_flags = SA_SIGINFO;
    sigaction(SIGTRAP, &act, NULL);

    SubDW *dw = [[SubDW alloc] init];

    objc_setForwardHandler((void*)test_dw_forward, (void*)test_dw_forward_stret);

# if __x86_64__
    test_dw("objc_msgSend",             dw, tagged, false, 0);
    test_dw("objc_msgSend_stret",       dw, tagged, true,  0);
    test_dw("objc_msgSend_fpret",       dw, tagged, false, 0);
    test_dw("objc_msgSend_fp2ret",      dw, tagged, false, 0);
    test_dw("objc_msgSendSuper",        dw, tagged, false, 0);
    test_dw("objc_msgSendSuper2",       dw, tagged, false, 0);
    test_dw("objc_msgSendSuper_stret",  dw, tagged, true,  0);
    test_dw("objc_msgSendSuper2_stret", dw, tagged, true,  0);
# elif __i386__
    test_dw("objc_msgSend",             dw, dw, false, 0);
    test_dw("objc_msgSend_stret",       dw, dw, true,  0);
    test_dw("objc_msgSend_fpret",       dw, dw, false, 0);
    test_dw("objc_msgSendSuper",        dw, dw, false, 0);
    test_dw("objc_msgSendSuper2",       dw, dw, false, 0);
    test_dw("objc_msgSendSuper_stret",  dw, dw, true,  0);
    test_dw("objc_msgSendSuper2_stret", dw, dw, true,  0);
# elif __arm64__
    test_dw("objc_msgSend",             dw, tagged, false, 1);
    test_dw("objc_msgSendSuper",        dw, tagged, false, 1);
    test_dw("objc_msgSendSuper2",       dw, tagged, false, 1);
# else
#   error unknown architecture
# endif

    // DWARF unwind tables
#endif

  } POP_POOL;
    succeed(__FILE__);
}

#endif
