#include <stdio.h>
#include <objc/runtime.h>
#import <Foundation/Foundation.h>

@interface TargetClass : NSObject
@end

@interface TargetClass(LoadedMethods)
- (void) m0;
- (void) m1;
- (void) m2;
- (void) m3;
- (void) m4;
- (void) m5;
- (void) m6;
- (void) m7;
- (void) m8;
- (void) m9;
- (void) m10;
- (void) m11;
- (void) m12;
- (void) m13;
- (void) m14;
- (void) m15;
@end

@interface TN:TargetClass
@end

@implementation TN
- (void) m1 { [super m1]; }
- (void) m3 { [self m1]; }

- (void) m2
{
    [self willChangeValueForKey: @"m4"];
    [self didChangeValueForKey: @"m4"];
}

- (void)observeValueForKeyPath:(NSString *) keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
    // suppress warning
    keyPath = nil;
    object = nil;
    change = nil;
    context = NULL; 
}
@end

@implementation TargetClass(LoadedMethods)
- (void) m0 { ; }
- (void) m1 { ; }
- (void) m2 { ; }
- (void) m3 { ; }
- (void) m4 { ; }
- (void) m5 { ; }
- (void) m6 { ; }
- (void) m7 { ; }
- (void) m8 { ; }
- (void) m9 { ; }
- (void) m10 { ; }
- (void) m11 { ; }
- (void) m12 { ; }
- (void) m13 { ; }
- (void) m14 { ; }
- (void) m15 { ; }
@end
