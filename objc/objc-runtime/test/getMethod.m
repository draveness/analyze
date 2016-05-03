// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <objc/runtime.h>
#include <objc/message.h>

static int state = 0;

@interface Super : TestRoot @end
@implementation Super
+(void)classMethod { state = 1; }
-(void)instanceMethod { state = 4; } 
+(void)classMethodSuperOnly { state = 3; }
-(void)instanceMethodSuperOnly { state = 6; } 
@end

@interface Sub : Super @end
@implementation Sub
+(void)classMethod { state = 2; }
-(void)instanceMethod { state = 5; } 
@end

typedef void (*imp_t)(id, SEL);

int main()
{
    Class Super_cls, Sub_cls;
    Class buf[10];
    Method m;
    SEL sel;
    IMP imp;

    // don't use [Super class] to check laziness handing
    Super_cls = objc_getClass("Super");
    Sub_cls = objc_getClass("Sub");

    sel = sel_registerName("classMethod");
    m = class_getClassMethod(Super_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(object_getClass(Super_cls), sel));
    testassert(imp == object_getMethodImplementation(Super_cls, sel));
    state = 0;
    (*(imp_t)imp)(Super_cls, sel);
    testassert(state == 1);

    sel = sel_registerName("classMethod");
    m = class_getClassMethod(Sub_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(object_getClass(Sub_cls), sel));
    testassert(imp == object_getMethodImplementation(Sub_cls, sel));
    state = 0;
    (*(imp_t)imp)(Sub_cls, sel);
    testassert(state == 2);

    sel = sel_registerName("classMethodSuperOnly");
    m = class_getClassMethod(Sub_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(object_getClass(Sub_cls), sel));
    testassert(imp == object_getMethodImplementation(Sub_cls, sel));
    state = 0;
    (*(imp_t)imp)(Sub_cls, sel);
    testassert(state == 3);
    
    sel = sel_registerName("instanceMethod");
    m = class_getInstanceMethod(Super_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(Super_cls, sel));
    buf[0] = Super_cls;
    testassert(imp == object_getMethodImplementation(objc_unretainedObject(buf), sel));
    state = 0;
    (*(imp_t)imp)(objc_unretainedObject(buf), sel);
    testassert(state == 4);

    sel = sel_registerName("instanceMethod");
    m = class_getInstanceMethod(Sub_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(Sub_cls, sel));
    buf[0] = Sub_cls;
    testassert(imp == object_getMethodImplementation(objc_unretainedObject(buf), sel));
    state = 0;
    (*(imp_t)imp)(objc_unretainedObject(buf), sel);
    testassert(state == 5);

    sel = sel_registerName("instanceMethodSuperOnly");
    m = class_getInstanceMethod(Sub_cls, sel);
    testassert(m);
    testassert(sel == method_getName(m));
    imp = method_getImplementation(m);
    testassert(imp == class_getMethodImplementation(Sub_cls, sel));
    buf[0] = Sub_cls;
    testassert(imp == object_getMethodImplementation(objc_unretainedObject(buf), sel));
    state = 0;
    (*(imp_t)imp)(objc_unretainedObject(buf), sel);
    testassert(state == 6);

    // check class_getClassMethod(cls) == class_getInstanceMethod(cls->isa)
    sel = sel_registerName("classMethod");
    testassert(class_getClassMethod(Sub_cls, sel) == class_getInstanceMethod(object_getClass(Sub_cls), sel));

    sel = sel_registerName("nonexistent");
    testassert(! class_getInstanceMethod(Sub_cls, sel));
    testassert(! class_getClassMethod(Sub_cls, sel));
    testassert(class_getMethodImplementation(Sub_cls, sel) == (IMP)&_objc_msgForward);
    buf[0] = Sub_cls;
    testassert(object_getMethodImplementation(objc_unretainedObject(buf), sel) == (IMP)&_objc_msgForward);
#if !__arm64__
    testassert(class_getMethodImplementation_stret(Sub_cls, sel) == (IMP)&_objc_msgForward_stret);
    testassert(object_getMethodImplementation_stret(objc_unretainedObject(buf), sel) == (IMP)&_objc_msgForward_stret);
#endif

    testassert(! class_getInstanceMethod(NULL, NULL));
    testassert(! class_getInstanceMethod(NULL, sel));
    testassert(! class_getInstanceMethod(Sub_cls, NULL));
    testassert(! class_getClassMethod(NULL, NULL));
    testassert(! class_getClassMethod(NULL, sel));
    testassert(! class_getClassMethod(Sub_cls, NULL));

    succeed(__FILE__);
}
