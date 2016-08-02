#include "test.h"

extern int state2, state3;

int state1 = 0;

OBJC_ROOT_CLASS
@interface One @end
@implementation One
+(void)load 
{ 
    testassert(state2 == 2  &&  state3 == 3);
    state1 = 1;
}
@end
