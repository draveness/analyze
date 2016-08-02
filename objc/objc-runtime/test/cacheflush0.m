#include "cacheflush.h"
#include "testroot.i"

@implementation TestRoot(cat)
+(int)classMethod { return 1; }
-(int)instanceMethod { return 1; }
@end
