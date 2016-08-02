// TEST_CONFIG MEM=mrc,gc
// TEST_CFLAGS -Wno-deprecated-declarations

#import <objc/runtime.h>
#import <objc/objc-auto.h>
#ifndef OBJC_NO_GC
#include <auto_zone.h>
#else
static BOOL auto_zone_is_valid_pointer(void *a, void *b) { return a||b; }
#endif
#include "test.h"

OBJC_ROOT_CLASS
@interface Super { @public id isa; } @end
@implementation Super 
+(void) initialize { } 
+(Class) class { return self; }
@end

@interface Sub : Super { int array[128]; } @end
@implementation Sub @end

int main()
{
    Super *s;

    s = class_createInstance([Super class], 0);
    testassert(s);
    testassert(object_getClass(s) == [Super class]);
    testassert(malloc_size(s) >= class_getInstanceSize([Super class]));
    if (objc_collectingEnabled()) testassert(auto_zone_is_valid_pointer(objc_collectableZone(), s));

    object_dispose(s);

    s = class_createInstance([Sub class], 0);
    testassert(s);
    testassert(object_getClass(s) == [Sub class]);
    testassert(malloc_size(s) >= class_getInstanceSize([Sub class]));
    if (objc_collectingEnabled()) testassert(auto_zone_is_valid_pointer(objc_collectableZone(), s));

    object_dispose(s);

    s = class_createInstance([Super class], 100);
    testassert(s);
    testassert(object_getClass(s) == [Super class]);
    testassert(malloc_size(s) >= class_getInstanceSize([Super class]) + 100);
    if (objc_collectingEnabled()) testassert(auto_zone_is_valid_pointer(objc_collectableZone(), s));

    object_dispose(s);

    s = class_createInstance([Sub class], 100);
    testassert(s);
    testassert(object_getClass(s) == [Sub class]);
    testassert(malloc_size(s) >= class_getInstanceSize([Sub class]) + 100);
    if (objc_collectingEnabled()) testassert(auto_zone_is_valid_pointer(objc_collectableZone(), s));

    object_dispose(s);

    s = class_createInstance(Nil, 0);
    testassert(!s);

    succeed(__FILE__);
}
