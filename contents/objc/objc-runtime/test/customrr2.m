// These options must match customrr.m
// TEST_CONFIG MEM=mrc
/*
TEST_BUILD
    $C{COMPILE} $DIR/customrr.m -fvisibility=default -o customrr2.out -DTEST_EXCHANGEIMPLEMENTATIONS=1
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/customrr-cat1.m -o customrr-cat1.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/customrr-cat2.m -o customrr-cat2.dylib
END
*/
