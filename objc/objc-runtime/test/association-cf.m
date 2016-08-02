// TEST_CFLAGS -framework CoreFoundation

#include <CoreFoundation/CoreFoundation.h>
#include <objc/runtime.h>

#include "test.h"

#if __has_feature(objc_arc)

int main()
{
    testwarn("rdar://11368528 confused by Foundation");
    succeed(__FILE__);
}

#else

int main()
{
    // rdar://6164781 setAssociatedObject on pure-CF object crashes LP64

    id obj;
    id array = objc_retainedObject(CFArrayCreate(0, 0, 0, 0));
    testassert(array);

    testassert(! objc_getClass("NSCFArray"));

    objc_setAssociatedObject(array, (void*)1, array, OBJC_ASSOCIATION_ASSIGN);

    obj = objc_getAssociatedObject(array, (void*)1);
    testassert(obj == array);

    RELEASE_VAR(array);

    succeed(__FILE__);
}

#endif
