#include "test.h"

extern int state3;

int state2 = 0;

OBJC_ROOT_CLASS
@interface Two @end
@implementation Two
+(void)load 
{ 
    testassert(state3 == 3);
    state2 = 2;
}
@end
