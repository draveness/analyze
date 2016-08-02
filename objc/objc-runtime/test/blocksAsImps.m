// TEST_CFLAGS -framework Foundation

#include "test.h"
#include <objc/runtime.h>
#import <Foundation/Foundation.h>

#include <Block_private.h>

#if !__has_feature(objc_arc)
#   define __bridge
#endif

#if !__clang__
    // gcc and llvm-gcc will never support struct-return marking
#   define STRET_OK 0
#   define STRET_SPECIAL 0
#elif __arm64__
    // stret supported, but is identical to non-stret
#   define STRET_OK 1
#   define STRET_SPECIAL 0
#else
    // stret supported and distinct from non-stret
#   define STRET_OK 1
#   define STRET_SPECIAL 1
#endif

typedef struct BigStruct {
    uintptr_t datums[200];
} BigStruct;

@interface Foo:NSObject
@end
@implementation Foo
- (BigStruct) methodThatReturnsBigStruct: (BigStruct) b
{
    return b;
}
@end

@interface Foo(bar)
- (int) boo: (int) a;
- (BigStruct) structThatIsBig: (BigStruct) b;
- (BigStruct) methodThatReturnsBigStruct: (BigStruct) b;
- (float) methodThatReturnsFloat: (float) aFloat;
@end

// This is void* instead of id to prevent interference from ARC.
typedef uintptr_t (*FuncPtr)(void *, SEL);
typedef BigStruct (*BigStructFuncPtr)(id, SEL, BigStruct);
typedef float (*FloatFuncPtr)(id, SEL, float);

BigStruct bigfunc(BigStruct a) {
    return a;
}

@interface Deallocator : NSObject @end
@implementation Deallocator
-(void) methodThatNobodyElseCalls1 { }
-(void) methodThatNobodyElseCalls2 { }
id retain_imp(Deallocator *self, SEL _cmd) {
    _objc_flush_caches([Deallocator class]);
    [self methodThatNobodyElseCalls1];
    struct objc_super sup = { self, [[Deallocator class] superclass] };
    return ((id(*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}
void dealloc_imp(Deallocator *self, SEL _cmd) {
    _objc_flush_caches([Deallocator class]);
    [self methodThatNobodyElseCalls2];
    struct objc_super sup = { self, [[Deallocator class] superclass] };
    ((void(*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}
+(void) load {
    class_addMethod(self, sel_registerName("retain"), (IMP)retain_imp, "");
    class_addMethod(self, sel_registerName("dealloc"), (IMP)dealloc_imp, "");
}
@end

/* Code copied from objc-block-trampolines.m to test Block innards */
typedef enum {
    ReturnValueInRegisterArgumentMode,
#if STRET_SPECIAL
    ReturnValueOnStackArgumentMode,
#endif
    
    ArgumentModeMax
} ArgumentMode;

static ArgumentMode _argumentModeForBlock(id block) {
    ArgumentMode aMode = ReturnValueInRegisterArgumentMode;
#if STRET_SPECIAL
    if ( _Block_use_stret((__bridge void *)block) )
        aMode = ReturnValueOnStackArgumentMode;
#else
    testassert(!_Block_use_stret((__bridge void *)block));
#endif
    
    return aMode;
}
/* End copied code */

int main () {
    // make sure the bits are in place
    int (^registerReturn)() = ^(){ return 42; };
    ArgumentMode aMode;
    
    aMode = _argumentModeForBlock(registerReturn);
    testassert(aMode == ReturnValueInRegisterArgumentMode);

#if STRET_OK
    BigStruct (^stackReturn)() = ^() { BigStruct k; return k; };
    aMode = _argumentModeForBlock(stackReturn);
# if STRET_SPECIAL
    testassert(aMode == ReturnValueOnStackArgumentMode);
# else
    testassert(aMode == ReturnValueInRegisterArgumentMode);
# endif
#endif

#define TEST_QUANTITY 100000
    static FuncPtr funcArray[TEST_QUANTITY];

    uintptr_t i;
    for(i = 0; i<TEST_QUANTITY; i++) {
        uintptr_t (^block)(void *self) = ^uintptr_t(void *self) {
            testassert(i == (uintptr_t)self);
            return i;
        };
        block = (__bridge id)_Block_copy((__bridge void *)block);
        
        funcArray[i] =  (FuncPtr) imp_implementationWithBlock(block);
        
        testassert(block((void *)i) == i);
        
        id blockFromIMPResult = imp_getBlock((IMP)funcArray[i]);
        testassert(blockFromIMPResult == (id)block);
        
        _Block_release((__bridge void *)block);
    }
    
    for(i = 0; i<TEST_QUANTITY; i++) {
        uintptr_t result = funcArray[i]((void *)i, 0);
        testassert(i == result);
    }
    
    for(i = 0; i < TEST_QUANTITY; i= i + 3) {
	imp_removeBlock((IMP)funcArray[i]);
	id shouldBeNull = imp_getBlock((IMP)funcArray[i]);
	testassert(shouldBeNull == NULL);
    }
    
    for(i = 0; i < TEST_QUANTITY; i= i + 3) {
        uintptr_t j = i * i;
        
        uintptr_t (^block)(void *) = ^uintptr_t(void *self) {
            testassert(j == (uintptr_t)self);
            return j;
        };
        funcArray[i] =  (FuncPtr) imp_implementationWithBlock(block);
        
        testassert(block((void *)j) == j);
        testassert(funcArray[i]((void *)j, 0) == j);
    }
    
    for(i = 0; i < TEST_QUANTITY; i= i + 3) {
        uintptr_t j = i * i;
        uintptr_t result = funcArray[i]((void *)j, 0);
        testassert(j == result);
    }
    
    int (^implBlock)(id, int);
    
    implBlock = ^(id self __attribute__((unused)), int a){
        return -1 * a;
    };
    
    PUSH_POOL {
    
        IMP methodImp = imp_implementationWithBlock(implBlock);
    
        BOOL success = class_addMethod([Foo class], @selector(boo:), methodImp, "i@:i");
        testassert(success);

        Foo *f = [Foo new];
        int (*impF)(id self, SEL _cmd, int x) = (int(*)(id, SEL, int)) [Foo instanceMethodForSelector: @selector(boo:)];
        
        int x = impF(f, @selector(boo:), -42);
        
        testassert(x == 42);
        testassert([f boo: -42] == 42);
        
#if STRET_OK
        BigStruct a;
        for(i=0; i<200; i++)
            a.datums[i] = i;    
        
        // slightly more straightforward here
        __block unsigned int state = 0;
        BigStruct (^structBlock)(id, BigStruct) = ^BigStruct(id self __attribute__((unused)), BigStruct c) {
            state++;
            return c;
        };
        BigStruct blockDirect = structBlock(nil, a);
        testassert(!memcmp(&a, &blockDirect, sizeof(BigStruct)));
        testassert(state==1);
        
        IMP bigStructIMP = imp_implementationWithBlock(structBlock);
        
        class_addMethod([Foo class], @selector(structThatIsBig:), bigStructIMP, "oh, type strings, how I hate thee. Fortunately, the runtime doesn't generally care.");
        
        BigStruct b;
        
        BigStructFuncPtr bFunc;
        
        b = bigfunc(a);
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        b = bigfunc(a);
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        
        bFunc = (BigStructFuncPtr) [Foo instanceMethodForSelector: @selector(methodThatReturnsBigStruct:)];
        
        b = bFunc(f, @selector(methodThatReturnsBigStruct:), a);
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        
        b = [f methodThatReturnsBigStruct: a];
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        
        bFunc = (BigStructFuncPtr) [Foo instanceMethodForSelector: @selector(structThatIsBig:)];
        
        b = bFunc(f, @selector(structThatIsBig:), a);
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        testassert(state==2);
        
        b = [f structThatIsBig: a];
        testassert(!memcmp(&a, &b, sizeof(BigStruct)));
        testassert(state==3);
        // STRET_OK
#endif
        
        
        IMP floatIMP = imp_implementationWithBlock(^float (id self __attribute__((unused)), float aFloat ) {
            return aFloat;
        });
        class_addMethod([Foo class], @selector(methodThatReturnsFloat:), floatIMP, "ooh.. type string unspecified again... oh noe... runtime might punish. not.");
        
        float e = (float)0.001;
        float retF = (float)[f methodThatReturnsFloat: 37.1212f];
        testassert( ((retF - e) < 37.1212) && ((retF + e) > 37.1212) );
        

#if !__has_feature(objc_arc)        
        // Make sure imp_implementationWithBlock() and imp_removeBlock() 
        // don't deadlock while calling Block_copy() and Block_release()
        Deallocator *dead = [[Deallocator alloc] init];
        IMP deadlockImp = imp_implementationWithBlock(^{ [dead self]; });
        [dead release];
        imp_removeBlock(deadlockImp);
#endif

    } POP_POOL;

    succeed(__FILE__);
}

