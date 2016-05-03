#include <objc/objc.h>
#include "test.h"

@interface TestRoot(cat)
+(int)classMethod;
-(int)instanceMethod;
@end
