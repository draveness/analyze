/*
rdar://8553305

TEST_CONFIG OS=iphoneos
TEST_CRASHES

TEST_BUILD
    $C{COMPILE} $DIR/evil-class-1.m -dynamiclib -o libevil.dylib
    $C{COMPILE} $DIR/evil-main.m -x none libevil.dylib -o evil-class-1.out
END

TEST_RUN_OUTPUT
objc\[\d+\]: bad method implementation \(0x[0-9a-f]+ at 0x[0-9a-f]+\)
CRASHED: SIG(ILL|TRAP)
END
*/

#define EVIL_SUPER 1
#define EVIL_SUPER_META 0
#define EVIL_SUB 0
#define EVIL_SUB_META 0

#define OMIT_SUPER 0
#define OMIT_NL_SUPER 0
#define OMIT_SUB 0
#define OMIT_NL_SUB 0

#include "evil-class-def.m"
