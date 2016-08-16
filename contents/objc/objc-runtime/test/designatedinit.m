// TEST_CONFIG
/* TEST_BUILD_OUTPUT
.*designatedinit.m:\d+:\d+: warning: designated initializer should only invoke a designated initializer on 'super'.*
.*designatedinit.m:\d+:\d+: note: .*
.*designatedinit.m:\d+:\d+: warning: method override for the designated initializer of the superclass '-init' not found.*
.*NSObject.h:\d+:\d+: note: .*
END */

#define NS_ENFORCE_NSOBJECT_DESIGNATED_INITIALIZER 1
#include "test.h"
#include <objc/NSObject.h>

@interface C : NSObject
-(id) initWithInt:(int)i NS_DESIGNATED_INITIALIZER;
@end

@implementation C
-(id) initWithInt:(int)__unused i {
    return [self init];
}
@end

int main()
{
    succeed(__FILE__);
}
