// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <objc/runtime.h>


@interface Sub1 : TestRoot {
    // id isa;  // 0..4
    BOOL b;     // 4..5
}
@end

@implementation Sub1 @end

@interface Sub2 : Sub1 {
    // id isa   // 0..4    0..8
    // BOOL b   // 4..5    8..9
    BOOL b2;    // 5..6    9..10
    id o;       // 8..12   16..24
}
@end
@implementation Sub2 @end

@interface Sub3 : Sub1 {
    // id isa;  // 0..4    0..8
    // BOOL b;  // 4..5    8..9
    id o;       // 8..12   16..24
    BOOL b2;    // 12..13  24..25
}
@end
@implementation Sub3 @end

int main()
{
    testassert(sizeof(id) == class_getInstanceSize([TestRoot class]));
    testassert(2*sizeof(id) == class_getInstanceSize([Sub1 class]));
    testassert(3*sizeof(id) == class_getInstanceSize([Sub2 class]));
    testassert(4*sizeof(id) == class_getInstanceSize([Sub3 class]));

#if !__has_feature(objc_arc)
    id o;

    o = [TestRoot new];
    testassert(object_getIndexedIvars(o) == (char *)o + class_getInstanceSize(object_getClass(o)));
    RELEASE_VAR(o);
    o = [Sub1 new];
    testassert(object_getIndexedIvars(o) == (char *)o + class_getInstanceSize(object_getClass(o)));
    RELEASE_VAR(o);
    o = [Sub2 new];
    testassert(object_getIndexedIvars(o) == (char *)o + class_getInstanceSize(object_getClass(o)));
    RELEASE_VAR(o);
    o = [Sub3 new];
    testassert(object_getIndexedIvars(o) == (char *)o + class_getInstanceSize(object_getClass(o)));
    RELEASE_VAR(o);
#endif

    succeed(__FILE__);
}
