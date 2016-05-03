// Test OBJC_DEBUG_POOL_ALLOCATION (which is also enabled by MallocStackLogging)

// TEST_ENV OBJC_DEBUG_POOL_ALLOCATION=YES
// TEST_CFLAGS -framework Foundation
// TEST_CONFIG MEM=mrc

#include "test.h"

#define FOUNDATION 0
#define NAME "rr-autorelease-stacklogging"

#include "rr-autorelease2.m"
