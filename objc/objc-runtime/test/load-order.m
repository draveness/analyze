/*
TEST_BUILD
    $C{COMPILE} $DIR/load-order3.m -o load-order3.dylib -dynamiclib
    $C{COMPILE} $DIR/load-order2.m -o load-order2.dylib -x none load-order3.dylib -dynamiclib
    $C{COMPILE} $DIR/load-order1.m -o load-order1.dylib -x none load-order3.dylib load-order2.dylib -dynamiclib
    $C{COMPILE} $DIR/load-order.m  -o load-order.out -x none load-order3.dylib load-order2.dylib load-order1.dylib 
END
*/

#include "test.h"

extern int state1, state2, state3;

int main()
{
    testassert(state1 == 1  &&  state2 == 2  &&  state3 == 3);
    succeed(__FILE__);
}
