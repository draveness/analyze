/*
rdar://8553305

TEST_BUILD
    $C{COMPILE} $DIR/evil-class-000.m -dynamiclib -o libevil.dylib
    $C{COMPILE} $DIR/evil-main.m -x none -DNOT_EVIL libevil.dylib -o evil-class-000.out
END
*/

// NOT EVIL version: all classes omitted from all lists

#define EVIL_SUPER 1
#define EVIL_SUPER_META 1
#define EVIL_SUB 1
#define EVIL_SUB_META 1

#define OMIT_SUPER 1
#define OMIT_NL_SUPER 1
#define OMIT_SUB 1
#define OMIT_NL_SUB 1

#include "evil-class-def.m"
