#include "test.h"

int state2 = 0;
extern int state1;

static void ctor(void)  __attribute__((constructor));
static void ctor(void) 
{
    // should be called during One's dlopen(), before Two's +load
    testassert(state1 == 111);
    testassert(state2 == 0);
}

OBJC_ROOT_CLASS
@interface Two @end
@implementation Two
+(void) load
{
    // Does not run until One's +load completes
    testassert(state1 == 1);
    state2 = 2;
}
@end
