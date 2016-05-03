/*
TEST_BUILD
    $C{COMPILE} $DIR/weak2.m -DWEAK_FRAMEWORK=1 -DWEAK_IMPORT= -UEMPTY  -dynamiclib -o libweakframework.dylib

    $C{COMPILE} $DIR/weakframework-not-missing.m -L. -weak-lweakframework -o weakframework-not-missing.out
END
*/

#define WEAK_FRAMEWORK 1
#define WEAK_IMPORT
#include "weak.m"
