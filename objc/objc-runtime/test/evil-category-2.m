/*
rdar://8553305

TEST_CONFIG OS=iphoneos
TEST_CRASHES

TEST_BUILD
    $C{COMPILE} $DIR/evil-category-2.m -dynamiclib -o libevil.dylib
    $C{COMPILE} $DIR/evil-main.m -x none libevil.dylib -o evil-category-2.out
END

TEST_RUN_OUTPUT
objc\[\d+\]: bad method implementation \(0x[0-9a-f]+ at 0x[0-9a-f]+\)
CRASHED: SIG(ILL|TRAP)
END
*/

#define EVIL_INSTANCE_METHOD 0
#define EVIL_CLASS_METHOD 1

#define OMIT_CAT 0
#define OMIT_NL_CAT 0

#include "evil-category-def.m"
