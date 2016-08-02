// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <string.h>
#include <objc/runtime.h>

@interface Fake : TestRoot @end
@implementation Fake @end

int main()
{
    TestRoot *obj = [TestRoot new];
    Class __unsafe_unretained * buf = (Class *)objc_unretainedPointer(obj);
    *buf = [Fake class];

    testassert(object_getClass(obj) == [Fake class]);
    testassert(object_setClass(obj, [TestRoot class]) == [Fake class]);
    testassert(object_getClass(obj) == [TestRoot class]);
    testassert(object_setClass(nil, [TestRoot class]) == nil);

    testassert(malloc_size(buf) >= sizeof(id));
    bzero(buf, malloc_size(buf));
    testassert(object_setClass(obj, [TestRoot class]) == nil);

    testassert(object_getClass(obj) == [TestRoot class]);
    testassert(object_getClass([TestRoot class]) == object_getClass([TestRoot class]));
    testassert(object_getClass(nil) == Nil);

    testassert(0 == strcmp(object_getClassName(obj), "TestRoot"));
    testassert(0 == strcmp(object_getClassName([TestRoot class]), "TestRoot"));
    testassert(0 == strcmp(object_getClassName(nil), "nil"));
    
    testassert(0 == strcmp(class_getName([TestRoot class]), "TestRoot"));
    testassert(0 == strcmp(class_getName(object_getClass([TestRoot class])), "TestRoot"));
    testassert(0 == strcmp(class_getName(nil), "nil"));

    succeed(__FILE__);
}
