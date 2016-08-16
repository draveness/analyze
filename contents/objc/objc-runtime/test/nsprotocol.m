// TEST_CONFIG

#include "test.h"

#if __OBJC2__

#include <objc/Protocol.h>

int main()
{
    // Class Protocol is always a subclass of NSObject

    testassert(objc_getClass("NSObject"));

    Class cls = objc_getClass("Protocol");
    testassert(class_getInstanceMethod(cls, sel_registerName("isProxy")));
    testassert(class_getSuperclass(cls) == objc_getClass("NSObject"));

    succeed(__FILE__);
}

#else

#include <dlfcn.h>
#include <objc/Protocol.h>

int main()
{
    // Class Protocol is never a subclass of NSObject
    // CoreFoundation adds NSObject methods to Protocol when it loads

    testassert(objc_getClass("NSObject"));
    
    Class cls = objc_getClass("Protocol");
    testassert(!class_getInstanceMethod(cls, sel_registerName("isProxy")));
    testassert(class_getSuperclass(cls) != objc_getClass("NSObject"));
    
    void *dl = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
    testassert(dl);
    
    testassert(class_getInstanceMethod(cls, sel_registerName("isProxy")));
    testassert(class_getSuperclass(cls) != objc_getClass("NSObject"));
    
    succeed(__FILE__);
}

#endif
