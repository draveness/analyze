// gc-on app loading gc-off dylib: should crash

/*
TEST_CONFIG MEM=gc OS=macosx
TEST_CRASHES

TEST_RUN_OUTPUT
objc\[\d+\]: '.*libnogc.dylib' was not compiled with -fobjc-gc or -fobjc-gc-only, but the application requires GC
objc\[\d+\]: \*\*\* GC capability of application and some libraries did not match
CRASHED: SIGILL
END

TEST_BUILD
    $C{COMPILE_C} $DIR/gc.c -dynamiclib -o libnoobjc.dylib
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o libnogc.dylib
    $C{COMPILE} $DIR/gc.m -dynamiclib -o libsupportsgc.dylib -fobjc-gc
    $C{COMPILE} $DIR/gc.m -dynamiclib -o librequiresgc.dylib -fobjc-gc-only
    $C{COMPILE} $DIR/gc.m -dynamiclib -o librequiresgc.fake.dylib -fobjc-gc -install_name librequiresgc.dylib

    $C{COMPILE} $DIR/gc-main.m -x none libnogc.dylib  -o gcenforcer-nogc-2.out
END
*/
