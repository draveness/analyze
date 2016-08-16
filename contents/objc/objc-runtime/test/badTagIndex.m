/* 
TEST_CRASHES
TEST_RUN_OUTPUT
objc\[\d+\]: tag index 8 is too large.
CRASHED: SIG(ILL|TRAP)
OR
no tagged pointers
OK: badTagIndex.m
END
*/

#include "test.h"

#include <objc/objc-internal.h>
#include <objc/NSObject.h>

#if OBJC_HAVE_TAGGED_POINTERS

int main()
{
    _objc_registerTaggedPointerClass((objc_tag_index_t)8, [NSObject class]);
    fail(__FILE__);
}

#else

int main()
{
    fprintf(stderr, "no tagged pointers\n");
    succeed(__FILE__);
}

#endif
