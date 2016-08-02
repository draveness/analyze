/* 
need exception-safe ARC for exception deallocation tests 
TEST_CFLAGS -fobjc-arc-exceptions -framework Foundation

llvm-gcc unavoidably warns about our deliberately out-of-order handlers

TEST_BUILD_OUTPUT
In file included from .*
.*exc.m: In function .*
.*exc.m:\d+: warning: exception of type .* will be caught
.*exc.m:\d+: warning:    by earlier handler for .*
.*exc.m:\d+: warning: exception of type .* will be caught
.*exc.m:\d+: warning:    by earlier handler for .*
.*exc.m:\d+: warning: exception of type .* will be caught
.*exc.m:\d+: warning:    by earlier handler for .*
OR
END
*/

#define USE_FOUNDATION 1
#include "exc.m"
