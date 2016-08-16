// TEST_CFLAGS -framework AppleScriptObjC -framework Foundation
// TEST_CONFIG MEM=gc

// Verify that non-trivial AppleScriptObjC apps run with GC ON.

#include <Foundation/Foundation.h>
#include "test.h"

@interface NonTrivial : NSObject @end
@implementation NonTrivial @end

int main()
{
    [NSBundle class];
    testassert(objc_collectingEnabled());
    succeed(__FILE__);
}
