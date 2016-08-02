// TEST_CONFIG

// initialize.m
// Test basic +initialize behavior
// * +initialize before class method
// * superclass +initialize before subclass +initialize
// * subclass inheritance of superclass implementation
// * messaging during +initialize
// * +initialize provoked by class_getMethodImplementation
// * +initialize not provoked by objc_getClass
#include "test.h"
#include "testroot.i"

int state = 0;

@interface Super0 : TestRoot @end
@implementation Super0
+(void)initialize {
    fail("objc_getClass() must not trigger +initialize");
}
@end

@interface Super : TestRoot @end
@implementation Super 
+(void)initialize {
    testprintf("in [Super initialize]\n");
    testassert(state == 0);
    state = 1;
}
+(void)method { 
    fail("[Super method] shouldn't be called");
}
@end

@interface Sub : Super @end
@implementation Sub
+(void)initialize { 
    testprintf("in [Sub initialize]\n");
    testassert(state == 1);
    state = 2;
}
+(void)method { 
    testprintf("in [Sub method]\n");
    testassert(state == 2);
    state = 3;
}
@end


@interface Super2 : TestRoot @end
@interface Sub2 : Super2 @end

@implementation Super2
+(void)initialize { 
    if (self == objc_getClass("Sub2")) {
        testprintf("in [Super2 initialize] of Sub2\n");
        testassert(state == 1);
        state = 2;
    } else if (self == objc_getClass("Super2")) {
        testprintf("in [Super2 initialize] of Super2\n");
        testassert(state == 0);
        state = 1;
    } else {
        fail("in [Super2 initialize] of unknown class");
    }
}
+(void)method { 
    testprintf("in [Super2 method]\n");
    testassert(state == 2);
    state = 3;
}
@end

@implementation Sub2
// nothing here
@end


@interface Super3 : TestRoot @end
@interface Sub3 : Super3 @end

@implementation Super3
+(void)initialize { 
    if (self == [Sub3 class]) {  // this message triggers [Sub3 initialize]
        testprintf("in [Super3 initialize] of Sub3\n");
        testassert(state == 0);
        state = 1;
    } else if (self == [Super3 class]) {
        testprintf("in [Super3 initialize] of Super3\n");
        testassert(state == 1);
        state = 2;
    } else {
        fail("in [Super3 initialize] of unknown class");
    }
}
+(void)method { 
    testprintf("in [Super3 method]\n");
    testassert(state == 2);
    state = 3;
}
@end

@implementation Sub3
// nothing here
@end


@interface Super4 : TestRoot @end
@implementation Super4
-(void)instanceMethod { 
    testassert(state == 1);
    state = 2;
}
+(void)initialize {
    testprintf("in [Super4 initialize]\n");
    testassert(state == 0);
    state = 1;
    id x = [[self alloc] init];
    [x instanceMethod];
    RELEASE_VALUE(x);
}
@end


@interface Super5 : TestRoot @end
@implementation Super5
-(void)instanceMethod { 
}
+(void)classMethod {
    testassert(state == 1);
    state = 2;
}
+(void)initialize {
    testprintf("in [Super5 initialize]\n");
    testassert(state == 0);
    state = 1;
    class_getMethodImplementation(self, @selector(instanceMethod));
    // this is the "memoized" case for getNonMetaClass
    class_getMethodImplementation(object_getClass(self), @selector(classMethod));
    [self classMethod];
}
@end


@interface Super6 : TestRoot @end
@interface Sub6 : Super6 @end
@implementation Super6
+(void)initialize {
    static bool once;
    bool wasOnce;
    testprintf("in [Super6 initialize] (#%d)\n", 1+(int)once);
    if (!once) {
        once = true;
        wasOnce = true;
        testassert(state == 0);
        state = 1;
    } else {
        wasOnce = false;
        testassert(state == 2);
        state = 3;
    }
    [Sub6 class];
    if (wasOnce) {
        testassert(state == 5);
        state = 6;
    } else {
        testassert(state == 3);
        state = 4;
    }
}
@end
@implementation Sub6
+(void)initialize {
    testprintf("in [Sub6 initialize]\n");
    testassert(state == 1);
    state = 2;
    [super initialize];
    testassert(state == 4);
    state = 5;
}
@end


@interface Super7 : TestRoot @end
@interface Sub7 : Super7 @end
@implementation Super7
+(void)initialize {
    static bool once;
    bool wasOnce;
    testprintf("in [Super7 initialize] (#%d)\n", 1+(int)once);
    if (!once) {
        once = true;
        wasOnce = true;
        testassert(state == 0);
        state = 1;
    } else {
        wasOnce = false;
        testassert(state == 2);
        state = 3;
    }
    [Sub7 class];
    if (wasOnce) {
        testassert(state == 5);
        state = 6;
    } else {
        testassert(state == 3);
        state = 4;
    }
}
@end
@implementation Sub7
+(void)initialize {
    testprintf("in [Sub7 initialize]\n");
    testassert(state == 1);
    state = 2;
    [super initialize];
    testassert(state == 4);
    state = 5;
}
@end


int main()
{
    Class cls;

    // objc_getClass() must not +initialize anything
    state = 0;
    objc_getClass("Super0");
    testassert(state == 0);

    // initialize superclass, then subclass
    state = 0;
    [Sub method];
    testassert(state == 3);

    // check subclass's inheritance of superclass initialize
    state = 0;
    [Sub2 method];
    testassert(state == 3);

    // check subclass method called from superclass initialize
    state = 0;
    [Sub3 method];
    testassert(state == 3);

    // check class_getMethodImplementation (instance method)
    state = 0;
    cls = objc_getClass("Super4");
    testassert(state == 0);
    class_getMethodImplementation(cls, @selector(classMethod));
    testassert(state == 2);

    // check class_getMethodImplementation (class method)
    // this is the "slow" case for getNonMetaClass
    state = 0;
    cls = objc_getClass("Super5");
    testassert(state == 0);
    class_getMethodImplementation(object_getClass(cls), @selector(instanceMethod));
    testassert(state == 2);

    // check +initialize cycles
    // this is the "cls is a subclass" case for getNonMetaClass
    state = 0;
    [Super6 class];
    testassert(state == 6);

    // check +initialize cycles
    // this is the "cls is a subclass" case for getNonMetaClass
    state = 0;
    [Sub7 class];
    testassert(state == 6);

    succeed(__FILE__);

    return 0;
}
