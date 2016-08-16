// TEST_CONFIG 

#include "test.h"

#if !__OBJC2__

int main()
{
    succeed(__FILE__);
}

#else

#include <objc/objc-internal.h>

// Reuse evil-class-def.m as a non-evil class definition.

#define EVIL_SUPER 0
#define EVIL_SUPER_META 0
#define EVIL_SUB 0
#define EVIL_SUB_META 0

#define OMIT_SUPER 1
#define OMIT_NL_SUPER 1
#define OMIT_SUB 1
#define OMIT_NL_SUB 1

#include "evil-class-def.m"

int main()
{
    // This definition is ABI and is never allowed to change.
    testassert(OBJC_MAX_CLASS_SIZE == 32*sizeof(void*));

    struct objc_image_info ii = { 0, 0 };

    // Read a root class.
    testassert(!objc_getClass("Super"));

    extern intptr_t OBJC_CLASS_$_Super[OBJC_MAX_CLASS_SIZE/sizeof(void*)];
    Class Super = objc_readClassPair((__bridge Class)(void*)&OBJC_CLASS_$_Super, &ii);
    testassert(Super);

    testassert(objc_getClass("Super") == Super);
    testassert(0 == strcmp(class_getName(Super), "Super"));
    testassert(class_getSuperclass(Super) == nil);
    testassert(class_getClassMethod(Super, @selector(load)));
    testassert(class_getInstanceMethod(Super, @selector(load)));
    testassert(class_getInstanceVariable(Super, "super_ivar"));
    testassert(class_getInstanceSize(Super) == sizeof(void*));
    [Super load];

    // Read a non-root class.
    testassert(!objc_getClass("Sub"));

    extern intptr_t OBJC_CLASS_$_Sub[OBJC_MAX_CLASS_SIZE/sizeof(void*)];
    intptr_t Sub2_buf[OBJC_MAX_CLASS_SIZE/sizeof(void*)];
    memcpy(Sub2_buf, &OBJC_CLASS_$_Sub, sizeof(Sub2_buf));
    Class Sub = objc_readClassPair((__bridge Class)(void*)&OBJC_CLASS_$_Sub, &ii);
    testassert(Sub);

    testassert(0 == strcmp(class_getName(Sub), "Sub"));
    testassert(objc_getClass("Sub") == Sub);
    testassert(class_getSuperclass(Sub) == Super);
    testassert(class_getClassMethod(Sub, @selector(load)));
    testassert(class_getInstanceMethod(Sub, @selector(load)));
    testassert(class_getInstanceVariable(Sub, "sub_ivar"));
    testassert(class_getInstanceSize(Sub) == 2*sizeof(void*));
    [Sub load];

    // Reading a class whose name already exists fails.
    testassert(! objc_readClassPair((__bridge Class)(void*)Sub2_buf, &ii));

    succeed(__FILE__);
}

#endif
