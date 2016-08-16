#include "test.h"

extern void fn(void);

int main(int argc __unused, char **argv)
{
    fn();

#if TARGET_OS_EMBEDDED && !defined(NOT_EVIL)
#pragma unused (argv)
    fail("All that is necessary for the triumph of evil is that good men do nothing.");
#else
    succeed(basename(argv[0]));
#endif
}
