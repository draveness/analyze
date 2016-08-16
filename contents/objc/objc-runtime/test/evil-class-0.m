/*
rdar://8553305

TEST_BUILD
    $C{COMPILE} $DIR/evil-class-0.m -dynamiclib -o libevil.dylib
    $C{COMPILE} $DIR/evil-main.m -x none -DNOT_EVIL libevil.dylib -o evil-class-0.out
END
*/

// NOT EVIL version

#define EVIL_SUPER 0
#define EVIL_SUPER_META 0
#define EVIL_SUB 0
#define EVIL_SUB_META 0

#define OMIT_SUPER 0
#define OMIT_NL_SUPER 0
#define OMIT_SUB 0
#define OMIT_NL_SUB 0

#include "evil-class-def.m"
