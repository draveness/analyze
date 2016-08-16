// TEST_CFLAGS -Wno-deprecated-declarations -Wl,-no_objc_category_merging

#include "test.h"
#include "testroot.i"
#include <objc/runtime.h>
#ifndef OBJC_NO_GC
#include <objc/objc-auto.h>
#include <auto_zone.h>
#endif

static int state;

@protocol Proto
+(void)classMethod;
-(void)instanceMethod;
@end

@interface Super : TestRoot <Proto> { 
    int i;
} 
@property int i;
@end

@implementation Super 
@synthesize i;

+(void)classMethod { 
    state = 1;
}

-(void)instanceMethod {
    state = 3;
}

@end


#if __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#endif

@implementation Super (Category)

+(void)classMethod { 
    state = 2;
}

-(void)instanceMethod {
    state = 4;
}

@end

#if __clang__
#pragma clang diagnostic pop
#endif


int main()
{
    Class clone;
    Class cls;
    Method *m1, *m2;
    int i;

    cls = [Super class];
    clone = objc_duplicateClass(cls, "Super_copy", 0);
#ifndef OBJC_NO_GC
    if (objc_collectingEnabled()) {
        testassert(auto_zone_size(objc_collectableZone(), objc_unretainedPointer(clone)));
        // objc_duplicateClass() doesn't duplicate the metaclass
        // no: testassert(auto_zone_size(objc_collectableZone(), clone->isa));
    }
#endif

    testassert(clone != cls);
    testassert(object_getClass(clone) == object_getClass(cls));
    testassert(class_getSuperclass(clone) == class_getSuperclass(cls));
    testassert(class_getVersion(clone) == class_getVersion(cls));
    testassert(class_isMetaClass(clone) == class_isMetaClass(cls));
    testassert(class_getIvarLayout(clone) == class_getIvarLayout(cls));
    testassert(class_getWeakIvarLayout(clone) == class_getWeakIvarLayout(cls));
#if !__OBJC2__
    testassert((clone->info & (CLS_CLASS|CLS_META)) == (cls->info & (CLS_CLASS|CLS_META)));
#endif

    // Check method list

    m1 = class_copyMethodList(cls, NULL);
    m2 = class_copyMethodList(clone, NULL);
    testassert(m1);
    testassert(m2);
    for (i = 0; m1[i]  &&  m2[i]; i++) {
        testassert(m1[i] != m2[i]);  // method list must be deep-copied
        testassert(method_getName(m1[i]) == method_getName(m2[i]));
        testassert(method_getImplementation(m1[i]) == method_getImplementation(m2[i]));
        testassert(method_getTypeEncoding(m1[i]) == method_getTypeEncoding(m2[i]));
    }
    testassert(m1[i] == NULL  &&  m2[i] == NULL);
    free(m1);
    free(m2);

    // Check ivar list
    Ivar *i1 = class_copyIvarList(cls, NULL);
    Ivar *i2 = class_copyIvarList(clone, NULL);
    testassert(i1);
    testassert(i2);
    for (i = 0; i1[i]  &&  i2[i]; i++) {
        testassert(i1[i] == i2[i]);  // ivars are not deep-copied
    }
    testassert(i1[i] == NULL  &&  i2[i] == NULL);
    free(i1);
    free(i2);

    // Check protocol list
    Protocol * __unsafe_unretained *p1 = class_copyProtocolList(cls, NULL);
    Protocol * __unsafe_unretained *p2 = class_copyProtocolList(clone, NULL);
    testassert(p1);
    testassert(p2);
    for (i = 0; p1[i]  &&  p2[i]; i++) {
        testassert(p1[i] == p2[i]);  // protocols are not deep-copied
    }
    testassert(p1[i] == NULL  &&  p2[i] == NULL);
    free(p1);
    free(p2);

    // Check property list
    objc_property_t *o1 = class_copyPropertyList(cls, NULL);
    objc_property_t *o2 = class_copyPropertyList(clone, NULL);
    testassert(o1);
    testassert(o2);
    for (i = 0; o1[i]  &&  o2[i]; i++) {
        testassert(o1[i] == o2[i]);  // properties are not deep-copied
    }
    testassert(o1[i] == NULL  &&  o2[i] == NULL);
    free(o1);
    free(o2);

    // Check method calls

    state = 0;
    [cls classMethod];
    testassert(state == 2);
    state = 0;
    [clone classMethod];
    testassert(state == 2);

    // #4511660 Make sure category implementation is still the preferred one
    id obj;
    obj = [cls new];
    state = 0;
    [obj instanceMethod];
    testassert(state == 4);
    RELEASE_VAR(obj);

    obj = [clone new];
    state = 0;
    [obj instanceMethod];
    testassert(state == 4);
    RELEASE_VAR(obj);

    succeed(__FILE__);
}
