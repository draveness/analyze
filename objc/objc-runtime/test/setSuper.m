// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"
#include "testroot.i"
#include <objc/runtime.h>

@interface Super1 : TestRoot @end
@implementation Super1
+(int)classMethod { return 1; }
-(int)instanceMethod { return 10000; }
@end

@interface Super2 : TestRoot @end
@implementation Super2
+(int)classMethod { return 2; }
-(int)instanceMethod { return 20000; }
@end

@interface Sub : Super1 @end
@implementation Sub
+(int)classMethod { return [super classMethod] + 100; }
-(int)instanceMethod { 
    return [super instanceMethod] + 1000000;
}
@end

int main()
{
    Class cls;
    Sub *obj = [Sub new];

    testassert(101 == [[Sub class] classMethod]);
    testassert(1010000 == [obj instanceMethod]);

    cls = class_setSuperclass([Sub class], [Super2 class]);

    testassert(cls == [Super1 class]);
    testassert(object_getClass(cls) == object_getClass([Super1 class]));

    testassert(102 == [[Sub class] classMethod]);
    testassert(1020000 == [obj instanceMethod]);

    succeed(__FILE__);
}
