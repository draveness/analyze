/*
TEST_CONFIG OS=macosx

TEST_BUILD
    $C{COMPILE_C} $DIR/gc.c -dynamiclib -o libnoobjc.dylib
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o libnogc.dylib
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o libsupportsgc.dylib -fobjc-gc
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o librequiresgc.dylib -fobjc-gc-only
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o librequiresgc.fake.dylib -fobjc-gc -install_name librequiresgc.dylib

    $C{COMPILE} $DIR/gcenforcer.m -o gcenforcer.out
END
*/

#include "test.h"
#include <objc/objc-auto.h>
#include <dlfcn.h>

int main()
{
    int i;
    for (i = 0; i < 1000; i++) {
        testassert(dlopen_preflight("libsupportsgc.dylib"));
        testassert(dlopen_preflight("libnoobjc.dylib"));
        
        if (objc_collectingEnabled()) {
            testassert(dlopen_preflight("librequiresgc.dylib"));
            testassert(! dlopen_preflight("libnogc.dylib"));
        } else {
            testassert(! dlopen_preflight("librequiresgc.dylib"));
            testassert(dlopen_preflight("libnogc.dylib"));
        }
    }

    succeed(__FILE__);
}
