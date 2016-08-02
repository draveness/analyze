// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <objc/objc-runtime.h>

@interface Sub : TestRoot @end
@implementation Sub @end

int main()
{
    // [super ...] messages are tested in msgSend.m

    testassert(class_getSuperclass([Sub class]) == [TestRoot class]);
    testassert(class_getSuperclass(object_getClass([Sub class])) == object_getClass([TestRoot class]));
    testassert(class_getSuperclass([TestRoot class]) == Nil);
    testassert(class_getSuperclass(object_getClass([TestRoot class])) == [TestRoot class]);
    testassert(class_getSuperclass(Nil) == Nil);

    succeed(__FILE__);
}
