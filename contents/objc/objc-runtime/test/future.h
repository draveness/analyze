#include "test.h"

@interface Sub1 : TestRoot
+(int)method;
+(Class)classref;
@end

@interface Sub2 : TestRoot
+(int)method;
+(Class)classref;
@end

@interface SubSub1 : Sub1 @end

@interface SubSub2 : Sub2 @end
