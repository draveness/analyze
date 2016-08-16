#include "test.h"
#include "imageorder.h"

static void c3(void) __attribute__((constructor));
static void c3(void)
{
    testassert(state == 3);  // +load before C/C++
    testassert(cstate == 2);
    cstate = 3;
}


#if __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#endif

@implementation Super (cat3)
+(void) method {
    state = 3;
}
+(void) method3 {
    state = 3;
}
+(void) load {
    testassert(state == 2);
    state = 3;
}
@end

#if __clang__
#pragma clang diagnostic pop
#endif
