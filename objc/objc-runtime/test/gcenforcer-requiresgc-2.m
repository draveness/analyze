// gc-off app loading gc-required dylib: should crash
// linker sees librequiresgc.fake.dylib, runtime uses librequiresgc.dylib

/*
TEST_CONFIG MEM=gc OS=macosx

TEST_BUILD
    $C{COMPILE_C} $DIR/gc.c -dynamiclib -o libnoobjc.dylib
    $C{COMPILE_NOMEM} $DIR/gc.m -dynamiclib -o libnogc.dylib
    $C{COMPILE} $DIR/gc.m -dynamiclib -o libsupportsgc.dylib -fobjc-gc
    $C{COMPILE} $DIR/gc.m -dynamiclib -o librequiresgc.dylib -fobjc-gc-only
    $C{COMPILE} $DIR/gc.m -dynamiclib -o librequiresgc.fake.dylib -fobjc-gc -install_name librequiresgc.dylib

    $C{COMPILE} $DIR/gc-main.m -x none librequiresgc.fake.dylib -o gcenforcer-requiresgc-2.out
END
*/
