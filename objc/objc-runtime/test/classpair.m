// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"

#include "testroot.i"
#include <objc/runtime.h>
#include <string.h>
#ifndef OBJC_NO_GC
#include <objc/objc-auto.h>
#include <auto_zone.h>
#endif

@protocol Proto
-(void) instanceMethod;
+(void) classMethod;
@optional
-(void) instanceMethod2;
+(void) classMethod2;
@end

@protocol Proto2
-(void) instanceMethod;
+(void) classMethod;
@optional
-(void) instanceMethod2;
+(void) classMethod_that_does_not_exist;
@end

@protocol Proto3
-(void) instanceMethod;
+(void) classMethod_that_does_not_exist;
@optional
-(void) instanceMethod2;
+(void) classMethod2;
@end

static int super_initialize;

@interface Super : TestRoot
@property int superProp;
@end
@implementation Super 
@dynamic superProp;
+(void)initialize { super_initialize++; } 

+(void) classMethod { fail("+[Super classMethod] called"); }
+(void) classMethod2 { fail("+[Super classMethod2] called"); }
-(void) instanceMethod { fail("-[Super instanceMethod] called"); }
-(void) instanceMethod2 { fail("-[Super instanceMethod2] called"); }
@end

@interface WeakSuper : Super { __weak id weakIvar; } @end
@implementation WeakSuper @end

static int state;

static void instance_fn(id self, SEL _cmd __attribute__((unused)))
{
    testassert(!class_isMetaClass(object_getClass(self)));
    state++;
}

static void class_fn(id self, SEL _cmd __attribute__((unused)))
{
    testassert(class_isMetaClass(object_getClass(self)));
    state++;
}

static void fail_fn(id self __attribute__((unused)), SEL _cmd)
{
    fail("fail_fn '%s' called", sel_getName(_cmd));
}


static void cycle(void)
{    
    Class cls;
    BOOL ok;
    objc_property_t prop;
    char namebuf[256];
    
    testassert(!objc_getClass("Sub"));
    testassert([Super class]);

    // Test subclass with bells and whistles
    
    cls = objc_allocateClassPair([Super class], "Sub", 0);
    testassert(cls);
#ifndef OBJC_NO_GC
    if (objc_collectingEnabled()) {
        testassert(auto_zone_size(objc_collectableZone(), objc_unretainedPointer(cls)));
        testassert(auto_zone_size(objc_collectableZone(), objc_unretainedPointer(object_getClass(cls))));
    }
#endif
    
    class_addMethod(cls, @selector(instanceMethod), 
                    (IMP)&instance_fn, "v@:");
    class_addMethod(object_getClass(cls), @selector(classMethod), 
                    (IMP)&class_fn, "v@:");
    class_addMethod(object_getClass(cls), @selector(initialize), 
                    (IMP)&class_fn, "v@:");
    class_addMethod(object_getClass(cls), @selector(load), 
                    (IMP)&fail_fn, "v@:");

    ok = class_addProtocol(cls, @protocol(Proto));
    testassert(ok);
    ok = class_addProtocol(cls, @protocol(Proto));
    testassert(!ok);

    char attrname[2];
    char attrvalue[2];
    objc_property_attribute_t attrs[1];
    unsigned int attrcount = sizeof(attrs) / sizeof(attrs[0]);

    attrs[0].name = attrname;
    attrs[0].value = attrvalue;
    strcpy(attrname, "T");
    strcpy(attrvalue, "x");

    strcpy(namebuf, "subProp");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(ok);
    strcpy(namebuf, "subProp");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(!ok);
    strcpy(attrvalue, "i");
    class_replaceProperty(cls, namebuf, attrs, attrcount);
    strcpy(namebuf, "superProp");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(!ok);
    bzero(namebuf, sizeof(namebuf));
    bzero(attrs, sizeof(attrs));
    bzero(attrname, sizeof(attrname));
    bzero(attrvalue, sizeof(attrvalue));

#ifndef __LP64__
# define size 4
# define align 2
#else
#define size 8
# define align 3
#endif

    /*
      {
        int ivar;
        id ivarid;
        id* ivaridstar;
        Block_t ivarblock;
      }
    */
    ok = class_addIvar(cls, "ivar", 4, 2, "i");
    testassert(ok);
    ok = class_addIvar(cls, "ivarid", size, align, "@");
    testassert(ok);
    ok = class_addIvar(cls, "ivaridstar", size, align, "^@");
    testassert(ok);
    ok = class_addIvar(cls, "ivarblock", size, align, "@?");
    testassert(ok);

    ok = class_addIvar(cls, "ivar", 4, 2, "i");
    testassert(!ok);
    ok = class_addIvar(object_getClass(cls), "classvar", 4, 2, "i");
    testassert(!ok);

    objc_registerClassPair(cls);

    // should call cls's +initialize, not super's
    // Provoke +initialize using class_getMethodImplementation(class method)
    //   in order to test getNonMetaClass's slow case
    super_initialize = 0;
    state = 0;
    class_getMethodImplementation(object_getClass(cls), @selector(class));
    testassert(super_initialize == 0);
    testassert(state == 1);

    testassert(cls == [cls class]);
    testassert(cls == objc_getClass("Sub"));

    testassert(!class_isMetaClass(cls));
    testassert(class_isMetaClass(object_getClass(cls)));

    testassert(class_getSuperclass(cls) == [Super class]);
    testassert(class_getSuperclass(object_getClass(cls)) == object_getClass([Super class]));

    testassert(class_getInstanceSize(cls) >= sizeof(Class) + 4 + 3*size);
    testassert(class_conformsToProtocol(cls, @protocol(Proto)));

    if (objc_collectingEnabled()) {
        testassert(0 == strcmp((char *)class_getIvarLayout(cls), "\x01\x13"));
        testassert(NULL == class_getWeakIvarLayout(cls));
    }

    class_addMethod(cls, @selector(instanceMethod2), 
                    (IMP)&instance_fn, "v@:");
    class_addMethod(object_getClass(cls), @selector(classMethod2), 
                    (IMP)&class_fn, "v@:");

    ok = class_addIvar(cls, "ivar2", 4, 4, "i");
    testassert(!ok);
    ok = class_addIvar(object_getClass(cls), "classvar2", 4, 4, "i");
    testassert(!ok);

    ok = class_addProtocol(cls, @protocol(Proto2));
    testassert(ok);
    ok = class_addProtocol(cls, @protocol(Proto2));
    testassert(!ok);
    ok = class_addProtocol(cls, @protocol(Proto));
    testassert(!ok);

    attrs[0].name = attrname;
    attrs[0].value = attrvalue;
    strcpy(attrname, "T");
    strcpy(attrvalue, "i");

    strcpy(namebuf, "subProp2");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(ok);
    strcpy(namebuf, "subProp");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(!ok);
    strcpy(namebuf, "superProp");
    ok = class_addProperty(cls, namebuf, attrs, attrcount);
    testassert(!ok);
    bzero(namebuf, sizeof(namebuf));
    bzero(attrs, sizeof(attrs));
    bzero(attrname, sizeof(attrname));
    bzero(attrvalue, sizeof(attrvalue));

    prop = class_getProperty(cls, "subProp");
    testassert(prop);
    testassert(0 == strcmp(property_getName(prop), "subProp"));
    testassert(0 == strcmp(property_getAttributes(prop), "Ti"));
    prop = class_getProperty(cls, "subProp2");
    testassert(prop);
    testassert(0 == strcmp(property_getName(prop), "subProp2"));
    testassert(0 == strcmp(property_getAttributes(prop), "Ti"));

    // note: adding more methods here causes a false leak check failure
    state = 0;
    [cls classMethod];
    [cls classMethod2];
    testassert(state == 2);

    // put instance tests on a separate thread so they 
    // are reliably GC'd before class destruction
    testonthread(^{
        id obj = [cls new];
        state = 0;
        [obj instanceMethod];
        [obj instanceMethod2];
        testassert(state == 2);
        RELEASE_VAR(obj);
    });

    // Test ivar layouts of sub-subclass
    Class cls2 = objc_allocateClassPair(cls, "SubSub", 0);
    testassert(cls2);

    /*
      {
        id ivarid2;
        id idarray[16];
        void* ptrarray[16];
        char a;
        char b;
        char c;
      }
    */
    ok = class_addIvar(cls2, "ivarid2", size, align, "@");
    testassert(ok);
    ok = class_addIvar(cls2, "idarray", 16*sizeof(id), align, "[16@]");
    testassert(ok);
    ok = class_addIvar(cls2, "ptrarray", 16*sizeof(void*), align, "[16^]");
    testassert(ok);
    ok = class_addIvar(cls2, "a", 1, 0, "c");
    testassert(ok);    
    ok = class_addIvar(cls2, "b", 1, 0, "c");
    testassert(ok);    
    ok = class_addIvar(cls2, "c", 1, 0, "c");
    testassert(ok);    

    objc_registerClassPair(cls2);

    if (objc_collectingEnabled()) {
        testassert(0 == strcmp((char *)class_getIvarLayout(cls2), "\x01\x1f\x05\xf0\x10"));
        testassert(NULL == class_getWeakIvarLayout(cls2));
    }

    // 1-byte ivars should be well packed
    testassert(ivar_getOffset(class_getInstanceVariable(cls2, "b")) == 
               ivar_getOffset(class_getInstanceVariable(cls2, "a")) + 1);
    testassert(ivar_getOffset(class_getInstanceVariable(cls2, "c")) == 
               ivar_getOffset(class_getInstanceVariable(cls2, "b")) + 1);

    testcollect();  // GC: finalize "obj" above before disposing its class
    objc_disposeClassPair(cls2);
    objc_disposeClassPair(cls);
    
    testassert(!objc_getClass("Sub"));


    // Test unmodified ivar layouts

    cls = objc_allocateClassPair([Super class], "Sub2", 0);
    testassert(cls);
    objc_registerClassPair(cls);
    if (objc_collectingEnabled()) {
        const char *l1, *l2;
        l1 = (char *)class_getIvarLayout([Super class]);
        l2 = (char *)class_getIvarLayout(cls);
        testassert(l1 == l2  ||  0 == strcmp(l1, l2));
        l1 = (char *)class_getWeakIvarLayout([Super class]);
        l2 = (char *)class_getWeakIvarLayout(cls);
        testassert(l1 == l2  ||  0 == strcmp(l1, l2));
    }
    objc_disposeClassPair(cls);

    cls = objc_allocateClassPair([WeakSuper class], "Sub3", 0);
    testassert(cls);
    objc_registerClassPair(cls);
    if (objc_collectingEnabled()) {
        const char *l1, *l2;
        l1 = (char *)class_getIvarLayout([WeakSuper class]);
        l2 = (char *)class_getIvarLayout(cls);
        testassert(l1 == l2  ||  0 == strcmp(l1, l2));
        l1 = (char *)class_getWeakIvarLayout([WeakSuper class]);
        l2 = (char *)class_getWeakIvarLayout(cls);
        testassert(l1 == l2  ||  0 == strcmp(l1, l2));
    }
    objc_disposeClassPair(cls);

    // Test layout setters
    if (objc_collectingEnabled()) {
        cls = objc_allocateClassPair([Super class], "Sub4", 0);
        testassert(cls);
        class_setIvarLayout(cls, (uint8_t *)"foo");
        class_setWeakIvarLayout(cls, NULL);
        objc_registerClassPair(cls);
        testassert(0 == strcmp("foo", (char *)class_getIvarLayout(cls)));
        testassert(NULL == class_getWeakIvarLayout(cls));
        objc_disposeClassPair(cls);

        cls = objc_allocateClassPair([Super class], "Sub5", 0);
        testassert(cls);
        class_setIvarLayout(cls, NULL);
        class_setWeakIvarLayout(cls, (uint8_t *)"bar");
        objc_registerClassPair(cls);
        testassert(NULL == class_getIvarLayout(cls));
        testassert(0 == strcmp("bar", (char *)class_getWeakIvarLayout(cls)));
        objc_disposeClassPair(cls);
    }
}

int main()
{
    int count = 1000;

    testonthread(^{ cycle(); });
    testonthread(^{ cycle(); });
    testonthread(^{ cycle(); });

    leak_mark();
    while (count--) {
        testonthread(^{ cycle(); });
    }
#if __OBJC_GC__
    testwarn("rdar://19042235 possible leaks suppressed under GC");
    leak_check(16000);
#else
    leak_check(0);
#endif

    succeed(__FILE__);
}

