/*
TEST_BUILD
    $C{COMPILE} $DIR/imageorder1.m -o imageorder1.dylib -dynamiclib
    $C{COMPILE} $DIR/imageorder2.m -x none imageorder1.dylib -o imageorder2.dylib -dynamiclib
    $C{COMPILE} $DIR/imageorder3.m -x none imageorder2.dylib imageorder1.dylib -o imageorder3.dylib -dynamiclib
    $C{COMPILE} $DIR/imageorder.m  -x none imageorder3.dylib imageorder2.dylib imageorder1.dylib -o imageorder.out
END
*/

#include "test.h"
#include "imageorder.h"
#include <objc/runtime.h>
#include <dlfcn.h>

int main()
{
    // +load methods and C static initializers
    testassert(state == 3);
    testassert(cstate == 3);

    Class cls = objc_getClass("Super");
    testassert(cls);

    // make sure all categories arrived
    state = -1;
    [Super method0];
    testassert(state == 0);
    [Super method1];
    testassert(state == 1);
    [Super method2];
    testassert(state == 2);
    [Super method3];
    testassert(state == 3);

    // make sure imageorder3.dylib is the last category to attach
    state = 0;
    [Super method];
    testassert(state == 3);

    succeed(__FILE__);
}
