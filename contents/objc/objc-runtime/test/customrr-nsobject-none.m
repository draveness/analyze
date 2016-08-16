/* 

TEST_CONFIG MEM=mrc
TEST_ENV OBJC_PRINT_CUSTOM_RR=YES OBJC_PRINT_CUSTOM_AWZ=YES

TEST_BUILD
    $C{COMPILE} $DIR/customrr-nsobject.m -o customrr-nsobject-none.out
END

TEST_RUN_OUTPUT
OK: customrr-nsobject-none.out
END

*/

