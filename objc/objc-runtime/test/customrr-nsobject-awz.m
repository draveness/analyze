/* 

TEST_CONFIG MEM=mrc
TEST_ENV OBJC_PRINT_CUSTOM_RR=YES OBJC_PRINT_CUSTOM_AWZ=YES

TEST_BUILD
    $C{COMPILE} $DIR/customrr-nsobject.m -o customrr-nsobject-awz.out -DSWIZZLE_AWZ=1
END

TEST_RUN_OUTPUT
objc\[\d+\]: CUSTOM AWZ:  NSObject \(meta\)
OK: customrr-nsobject-awz.out
END

*/

