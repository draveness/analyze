// TEST_CONFIG MEM=mrc

#include "test.h"
#include "testroot.i"

@implementation TestRoot (Loader)
+(void)load 
{
    [[TestRoot new] autorelease];
    testassert(TestRootAutorelease == 1);
    testassert(TestRootDealloc == 0);
}
@end

int main()
{
    // +load's autoreleased object should have deallocated
    testassert(TestRootDealloc == 1);

    [[TestRoot new] autorelease];
    testassert(TestRootAutorelease == 2);

    objc_autoreleasePoolPop(objc_autoreleasePoolPush());

    [[TestRoot new] autorelease];
    testassert(TestRootAutorelease == 3);

    testonthread(^{
        [[TestRoot new] autorelease];
        testassert(TestRootAutorelease == 4);
        testassert(TestRootDealloc == 1);
    });

    // thread's autoreleased object should have deallocated
    testassert(TestRootDealloc == 2);

    succeed(__FILE__);
}
