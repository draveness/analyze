/*
rdar://8553305

TEST_CONFIG OS=iphoneos
TEST_CRASHES

TEST_BUILD
    $C{COMPILE} $DIR/evil-category-00.m $DIR/evil-main.m -o evil-category-00.out
END

TEST_RUN_OUTPUT
CRASHED: SIGSEGV
END
*/

// NOT EVIL version: apps are allowed through (then crash in +load)

#define EVIL_INSTANCE_METHOD 1
#define EVIL_CLASS_METHOD 1

#define OMIT_CAT 0
#define OMIT_NL_CAT 0

#include "evil-category-def.m"
