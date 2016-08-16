// TEST_CONFIG

// DO NOT include anything else here
#include <objc/objc.h>
// DO NOT include anything else here
Class c = Nil;
SEL s;
IMP i;
id o = nil;
BOOL b = YES;
BOOL b2 = NO;
#if !__has_feature(objc_arc)
__strong void *p;
#endif
id __unsafe_unretained u;
id __weak w;

void fn(void) __unused;
void fn(void) {
    id __autoreleasing a __unused;
}

#if __llvm__ && !__clang__
// llvm-gcc defines _NSConcreteGlobalBlock wrong
#else
// rdar://10118972 wrong type inference for blocks returning YES and NO
BOOL (^block1)(void) = ^{ return YES; };
BOOL (^block2)(void) = ^{ return NO; };
#endif

#include "test.h"

int main()
{
    testassert(YES);
    testassert(!NO);
#if __cplusplus
    testwarn("rdar://12371870 -Wnull-conversion");
    testassert(!(bool)nil);
    testassert(!(bool)Nil);
#else
    testassert(!nil);
    testassert(!Nil);
#endif

#if __has_feature(objc_bool)
    // YES[array] is disallowed for objc just as true[array] is for C++
#else
    // this will fail if YES and NO do not have enough parentheses
    int array[2] = { 888, 999 };
    testassert(NO[array] == 888);
    testassert(YES[array] == 999);
#endif

    succeed(__FILE__);
}
