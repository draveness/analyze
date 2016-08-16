#include "test.h"

int state3 = 0;

OBJC_ROOT_CLASS
@interface Three @end
@implementation Three
+(void)load 
{ 
    state3 = 3;
}
@end
