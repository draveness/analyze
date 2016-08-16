#include "test.h"
#if __OBJC2__

extern semaphore_t go;

OBJC_ROOT_CLASS 
@interface noobjc @end
@implementation noobjc
+(void)load 
{
    semaphore_signal(go);
    while (1) sleep(1);
}
@end

#endif
