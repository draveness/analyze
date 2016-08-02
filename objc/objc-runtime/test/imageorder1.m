#include "test.h"
#include "imageorder.h"

int state = -1;
int cstate = 0;

static void c1(void) __attribute__((constructor));
static void c1(void)
{
    testassert(state == 1);  // +load before C/C++
    testassert(cstate == 0);
    cstate = 1;
}


#if __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#endif

@implementation Super (cat1)
+(void) method {
    fail("+[Super(cat1) method] not replaced!");
}
+(void) method1 {
    state = 1;
}
+(void) load {
    testassert(state == 0);
    state = 1;
}
@end

#if __clang__
#pragma clang diagnostic pop
#endif


@implementation Super
+(void) initialize { }
+(void) method {
    fail("+[Super method] not replaced!");
}
+(void) method0 {
    state = 0;
}
+(void) load {
    testassert(state == -1);
    state = 0;
}
@end

