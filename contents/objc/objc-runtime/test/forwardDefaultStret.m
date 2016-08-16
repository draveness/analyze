/*
no arc, rdar://11368528 confused by Foundation
TEST_CONFIG MEM=mrc,gc
TEST_CRASHES
TEST_RUN_OUTPUT
objc\[\d+\]: \+\[NSObject fakeorama\]: unrecognized selector sent to instance 0x[0-9a-fA-F]+ \(no message forward handler is installed\)
CRASHED: SIG(ILL|TRAP)
OR
not OBJC2
objc\[\d+\]: NSObject: Does not recognize selector forward:: \(while forwarding fakeorama\)
CRASHED: SIG(ILL|TRAP)
END
*/

#include "test.h"

#include <objc/NSObject.h>

@interface NSObject (Fake)
-(struct stret)fakeorama;
@end

int main()
{
#if !__OBJC2__
    fprintf(stderr, "not OBJC2\n");
#endif
    [NSObject fakeorama];
    fail("should have crashed");
}

