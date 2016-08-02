// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"

#if TARGET_OS_IPHONE

int main()
{
    succeed(__FILE__);
}

#else

#include "testroot.i"
#include <objc/objc-gdb.h>
#include <objc/runtime.h>

int main()
{
    // Class hashes
#if __OBJC2__

    Class result;

    // Class should not be realized yet
    // fixme not true during class hash rearrangement
    // result = NXMapGet(gdb_objc_realized_classes, "TestRoot");
    // testassert(!result);

    [TestRoot class];
    // Now class should be realized

    result = (Class)objc_unretainedObject(NXMapGet(gdb_objc_realized_classes, "TestRoot"));
    testassert(result);
    testassert(result == [TestRoot class]);

    result = (Class)objc_unretainedObject(NXMapGet(gdb_objc_realized_classes, "DoesNotExist"));
    testassert(!result);

#else

    struct objc_class query;
    Class result;

    query.name = "TestRoot";
    result = (Class)NXHashGet(_objc_debug_class_hash, &query);
    testassert(result);
    testassert((id)result == [TestRoot class]);

    query.name = "DoesNotExist";
    result = (Class)NXHashGet(_objc_debug_class_hash, &query);
    testassert(!result);

#endif

    succeed(__FILE__);
}

#endif
