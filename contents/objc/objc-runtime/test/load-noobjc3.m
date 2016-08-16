#include "test.h"

#if __OBJC2__

extern int state;

__attribute__((constructor))
static void ctor(void)
{
    state = 1;
}

#endif
