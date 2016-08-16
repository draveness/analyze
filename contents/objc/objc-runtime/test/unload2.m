#include "unload.h"
#include "testroot.i"
#import <objc/objc-api.h>

@implementation SmallClass : TestRoot
-(void)unload2_instance_method { }
@end


@implementation BigClass : TestRoot
@end

OBJC_ROOT_CLASS
@interface UnusedClass { id isa; } @end
@implementation UnusedClass @end


@protocol SmallProtocol
-(void)unload2_category_method;
@end

@interface SmallClass (Category) <SmallProtocol> @end

@implementation SmallClass (Category)
-(void)unload2_category_method { }
@end
