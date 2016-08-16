/* 
TEST_CRASHES
TEST_RUN_OUTPUT
objc\[\d+\]: tag index 7 used for two different classes \(was 0x[0-9a-fA-F]+ NSObject, now 0x[0-9a-fA-F]+ TestRoot\)
CRASHED: SIG(ILL|TRAP)
OR
no tagged pointers
OK: badTagClass.m
END
*/

#include "test.h"
#include "testroot.i"

#include <objc/objc-internal.h>
#include <objc/Protocol.h>

#if OBJC_HAVE_TAGGED_POINTERS

int main()
{
    // re-registration and nil registration allowed
    _objc_registerTaggedPointerClass(OBJC_TAG_7, [NSObject class]);
    _objc_registerTaggedPointerClass(OBJC_TAG_7, [NSObject class]);
    _objc_registerTaggedPointerClass(OBJC_TAG_7, nil);
    _objc_registerTaggedPointerClass(OBJC_TAG_7, [NSObject class]);

    // colliding registration disallowed
    _objc_registerTaggedPointerClass(OBJC_TAG_7, [TestRoot class]);

    fail(__FILE__);
}

#else

int main()
{
    fprintf(stderr, "no tagged pointers\n");
    succeed(__FILE__);
}

#endif
