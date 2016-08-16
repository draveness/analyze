// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <objc/objc-runtime.h>

int main()
{
    testassert(!class_isMetaClass([TestRoot class]));
    testassert(class_isMetaClass(object_getClass([TestRoot class])));
    testassert(!class_isMetaClass(nil));
    succeed(__FILE__);
}
