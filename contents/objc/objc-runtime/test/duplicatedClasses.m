// TEST_ENV OBJC_DEBUG_DUPLICATE_CLASSES=YES
// TEST_CRASHES
/* 
TEST_RUN_OUTPUT
objc\[\d+\]: Class GKScore is implemented in both [^\s]+ and [^\s]+ One of the two will be used. Which one is undefined.
CRASHED: SIG(ILL|TRAP)
OR
OK: duplicatedClasses.m
END
 */

#include "test.h"
#include "testroot.i"

@interface GKScore : TestRoot @end
@implementation GKScore @end

int main()
{
    if (objc_collectingEnabled()) {
        testwarn("rdar://19042235 test disabled because GameKit is not GC");
        succeed(__FILE__);
    }
    void *dl = dlopen("/System/Library/Frameworks/GameKit.framework/GameKit", RTLD_LAZY);
    if (!dl) fail("couldn't open GameKit");
    fail("should have crashed already");
}
