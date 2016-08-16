/*
rdar://8553305

TEST_BUILD
    $C{COMPILE} $DIR/evil-category-0.m -dynamiclib -o libevil.dylib
    $C{COMPILE} $DIR/evil-main.m -x none -DNOT_EVIL libevil.dylib -o evil-category-0.out
END
*/

// NOT EVIL version

#define EVIL_INSTANCE_METHOD 0
#define EVIL_CLASS_METHOD 0

#define OMIT_CAT 0
#define OMIT_NL_CAT 0

#include "evil-category-def.m"
