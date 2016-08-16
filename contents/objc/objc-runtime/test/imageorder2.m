#include "test.h"
#include "imageorder.h"

static void c2(void) __attribute__((constructor));
static void c2(void)
{
    testassert(state == 2);  // +load before C/C++
    testassert(cstate == 1);
    cstate = 2;
}


#if __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#endif

@implementation Super (cat2)
+(void) method {
    fail("+[Super(cat2) method] not replaced!");
}
+(void) method2 {
    state = 2;
}
+(void) load {
    testassert(state == 1);
    state = 2;
}
@end

#if __clang__
#pragma clang diagnostic pop
#endif
