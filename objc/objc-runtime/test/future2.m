#include "future.h"


@implementation Sub1
+(Class)classref { 
    return [Sub1 class];
}
+(int)method {
    return 1;
}
@end

@implementation SubSub1 
+(int)method {
    return 1 + [super method];
}
@end
