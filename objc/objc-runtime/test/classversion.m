// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <objc/runtime.h>

int main()
{
    Class cls = [TestRoot class];
    testassert(class_getVersion(cls) == 0);
    testassert(class_getVersion(object_getClass(cls)) > 5);
    class_setVersion(cls, 100);
    testassert(class_getVersion(cls) == 100);

    testassert(class_getVersion(Nil) == 0);
    class_setVersion(Nil, 100);

    succeed(__FILE__);
}
