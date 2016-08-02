// TEST_CONFIG MEM=mrc,gc

#include "test.h"
#include <objc/NSObject.h>

@interface Test : NSObject {
@public
    char bytes[32-sizeof(void*)];
}
@end
@implementation Test
@end


int main()
{
    Test *o0 = [Test new];
    [o0 retain];
    Test *o1 = class_createInstance([Test class], 32);
    [o1 retain];
    id o2 = object_copy(o0, 0);
    id o3 = object_copy(o1, 0);
    id o4 = object_copy(o1, 32);
    testassert(malloc_size(o0) == 32);
    testassert(malloc_size(o1) == 64);
    testassert(malloc_size(o2) == 32);
    testassert(malloc_size(o3) == 32);
    testassert(malloc_size(o4) == 64);
    if (!objc_collecting_enabled()) {
        testassert([o0 retainCount] == 2);
        testassert([o1 retainCount] == 2);
        testassert([o2 retainCount] == 1);
        testassert([o3 retainCount] == 1);
        testassert([o4 retainCount] == 1);
    }
    succeed(__FILE__);
}
