// TEST_CONFIG MEM=mrc,gc

#include "test.h"

#import <Foundation/NSObject.h>

@interface Sub : NSObject @end
@implementation Sub 
+(id)allocWithZone:(NSZone *)zone { 
    testprintf("in +[Sub alloc]\n");
    return [super allocWithZone:zone];
    }
-(void)dealloc { 
    testprintf("in -[Sub dealloc]\n");
    [super dealloc];
}
@end


// These declarations and definitions can be used 
// to check the compile-time type of an object.
@interface NSObject (Checker)
// fixme this isn't actually enforced
+(void)NSObjectInstance __attribute__((unavailable));
@end
@implementation NSObject (Checker)
-(void)NSObjectInstance { }
+(void)NSObjectClass { }
@end
@interface Sub (Checker)
-(void)NSObjectInstance __attribute__((unavailable));
+(void)NSObjectClass __attribute__((unavailable));
@end
@implementation Sub (Checker)
-(void)SubInstance { }
+(void)SubClass { }
@end

int main()
{
    PUSH_POOL {
        [[Sub new] autorelease];
    } POP_POOL;

    // Verify that dot syntax on class objects works with some instance methods
    // (void)NSObject.self;  fixme
    (void)NSObject.class;
    (void)NSObject.superclass;
    (void)NSObject.hash;
    (void)NSObject.description;
    (void)NSObject.debugDescription;

    // Verify that some methods return the correct type.
    Class cls;
    NSObject *nsobject = nil;
    Sub *subobject = nil;

    cls = [NSObject self];
    cls = [Sub self];
    nsobject = [nsobject self];
    subobject = [subobject self];
    [[NSObject self] NSObjectClass];
    [[nsobject self] NSObjectInstance];
    [[Sub self] SubClass];
    [[subobject self] SubInstance];

    // fixme
    // cls = NSObject.self;
    // cls = Sub.self;
    // [NSObject.self NSObjectClass];
    // [nsobject.self NSObjectInstance];
    // [Sub.self SubClass];
    // [subobject.self SubInstance];

    cls = [NSObject class];
    cls = [nsobject class];
    cls = [Sub class];
    cls = [subobject class];
    [[NSObject class] NSObjectClass];
    [[nsobject class] NSObjectClass];
    [[Sub class] SubClass];
    [[subobject class] SubClass];

    cls = NSObject.class;
    cls = nsobject.class;
    cls = Sub.class;
    cls = subobject.class;
    [NSObject.class NSObjectClass];
    [nsobject.class NSObjectClass];
    [Sub.class SubClass];
    [subobject.class SubClass];


    cls = [NSObject superclass];
    cls = [nsobject superclass];
    cls = [Sub superclass];
    cls = [subobject superclass];
    [[NSObject superclass] NSObjectClass];
    [[nsobject superclass] NSObjectClass];
    [[Sub superclass] NSObjectClass];
    [[subobject superclass] NSObjectClass];

    cls = NSObject.superclass;
    cls = nsobject.superclass;
    cls = Sub.superclass;
    cls = subobject.superclass;
    [NSObject.superclass NSObjectClass];
    [nsobject.superclass NSObjectClass];
    [Sub.superclass NSObjectClass];
    [subobject.superclass NSObjectClass];


    succeed(__FILE__);
}
