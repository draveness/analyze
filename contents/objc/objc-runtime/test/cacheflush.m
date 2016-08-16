/*
TEST_BUILD
    $C{COMPILE} $DIR/cacheflush0.m -o cacheflush0.dylib -dynamiclib
    $C{COMPILE} $DIR/cacheflush2.m -x none cacheflush0.dylib -o cacheflush2.dylib -dynamiclib
    $C{COMPILE} $DIR/cacheflush3.m -x none cacheflush0.dylib -o cacheflush3.dylib -dynamiclib
    $C{COMPILE} $DIR/cacheflush.m  -x none cacheflush0.dylib -o cacheflush.out
END
*/

#include "test.h"
#include <objc/runtime.h>
#include <dlfcn.h>

#include "cacheflush.h"

@interface Sub : TestRoot @end
@implementation Sub @end


int main()
{
    TestRoot *sup = [TestRoot new];
    Sub *sub = [Sub new];

    // Fill method cache
    testassert(1 == [TestRoot classMethod]);
    testassert(1 == [sup instanceMethod]);
    testassert(1 == [TestRoot classMethod]);
    testassert(1 == [sup instanceMethod]);

    testassert(1 == [Sub classMethod]);
    testassert(1 == [sub instanceMethod]);
    testassert(1 == [Sub classMethod]);
    testassert(1 == [sub instanceMethod]);

    // Dynamically load a category
    dlopen("cacheflush2.dylib", 0);

    // Make sure old cache results are gone
    testassert(2 == [TestRoot classMethod]);
    testassert(2 == [sup instanceMethod]);

    testassert(2 == [Sub classMethod]);
    testassert(2 == [sub instanceMethod]);

    // Dynamically load another category
    dlopen("cacheflush3.dylib", 0);

    // Make sure old cache results are gone
    testassert(3 == [TestRoot classMethod]);
    testassert(3 == [sup instanceMethod]);

    testassert(3 == [Sub classMethod]);
    testassert(3 == [sub instanceMethod]);

    // fixme test subclasses

    // fixme test objc_flush_caches(), class_addMethod(), class_addMethods()

    succeed(__FILE__);
}
