// TEST_CONFIG 

#include "test.h"

#if __OBJC_GC__ && __cplusplus && __i386__

int main()
{
    testwarn("rdar://19042235 test disabled for 32-bit objc++ GC because of unknown bit rot");
    succeed(__FILE__);
}

#else

#include "testroot.i"
#include <stdint.h>
#include <string.h>
#include <objc/objc-runtime.h>

@interface Weak : TestRoot {
  @public
    __weak id value;
}
@end
@implementation Weak
@end

Weak *oldObject;
Weak *newObject;

void *fn(void *arg __unused)
{
    objc_registerThreadWithCollector();

    return NULL;
}

int main()
{
    testonthread(^{
        TestRoot *value;

        PUSH_POOL {
            value = [TestRoot new];
            testassert(value);
            oldObject = [Weak new];
            testassert(oldObject);
            
            oldObject->value = value;
            testassert(oldObject->value == value);
            
            newObject = [oldObject copy];
            testassert(newObject);
            testassert(newObject->value == oldObject->value);
            
            newObject->value = nil;
            testassert(newObject->value == nil);
            testassert(oldObject->value == value);
        } POP_POOL;
        
        testcollect();
        TestRootDealloc = 0;
        TestRootFinalize = 0;
        RELEASE_VAR(value);
    });

    testcollect();
    testassert(TestRootDealloc || TestRootFinalize);

#if defined(__OBJC_GC__)  ||  __has_feature(objc_arc)
    testassert(oldObject->value == nil);
#else
    testassert(oldObject->value != nil);
#endif
    testassert(newObject->value == nil);

    RELEASE_VAR(newObject);
    RELEASE_VAR(oldObject);

    succeed(__FILE__);
    return 0;
}

#endif
