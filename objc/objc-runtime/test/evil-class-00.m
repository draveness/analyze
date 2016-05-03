/*
rdar://8553305

TEST_CONFIG OS=iphoneos
TEST_CRASHES

TEST_BUILD
    $C{COMPILE} $DIR/evil-class-00.m $DIR/evil-main.m -o evil-class-00.out
END

TEST_RUN_OUTPUT
CRASHED: SIGSEGV
END
*/

// NOT EVIL version: apps are allowed through (then crash in +load)

#define EVIL_SUPER 0
#define EVIL_SUPER_META 1
#define EVIL_SUB 0
#define EVIL_SUB_META 0

#define OMIT_SUPER 1
#define OMIT_NL_SUPER 1
#define OMIT_SUB 1
#define OMIT_NL_SUB 0

#include "evil-class-def.m"
