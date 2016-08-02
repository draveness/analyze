// TEST_ENV OBJC_DISABLE_TAGGED_POINTERS=YES
// TEST_CRASHES
/* 
TEST_RUN_OUTPUT
objc\[\d+\]: tagged pointers are disabled
CRASHED: SIG(ILL|TRAP)
OR
OK: taggedPointersDisabled.m
END
*/

#include "test.h"
#include <objc/objc-internal.h>

#if !OBJC_HAVE_TAGGED_POINTERS

int main()
{
    succeed(__FILE__);
}

#else

int main()
{
    testassert(!_objc_taggedPointersEnabled());
    _objc_registerTaggedPointerClass((objc_tag_index_t)0, nil);
    fail("should have crashed in _objc_registerTaggedPointerClass()");
}

#endif
