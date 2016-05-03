// TEST_CONFIG MEM=arc
// TEST_CFLAGS -framework Foundation

// Problem: If weak reference operations provoke +initialize, the runtime 
// can deadlock (recursive weak lock, or lock inversion between weak lock
// and +initialize lock).
// Solution: object_setClass() and objc_storeWeak() perform +initialize 
// if needed so that no weakly-referenced object can ever have an 
// un-+initialized isa.

#include <Foundation/Foundation.h>
#include <objc/objc-internal.h>
#include "test.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Warc-unsafe-retained-assign"

// This is StripedMap's pointer hash
uintptr_t hash(id obj) {
    uintptr_t addr = (uintptr_t)obj;
    return ((addr >> 4) ^ (addr >> 9)) % 64;
}

bool sameAlignment(id o1, id o2)
{
    return hash(o1) == hash(o2);
}

// Return a new string object that uses the same striped weak locks as `obj`.
NSMutableString *newAlignedString(id obj) 
{
    NSMutableArray *strings = [NSMutableArray new];
    NSMutableString *result;
    do {
        result = [NSMutableString new];
        [strings addObject:result];
    } while (!sameAlignment(obj, result));
    return result;
}


__weak NSObject *weak1;
__weak NSMutableString *weak2;
NSMutableString *strong2;

@interface A : NSObject @end
@implementation A
+(void)initialize {
    weak2 = strong2;  // weak store #2
    strong2 = nil;
}
@end

void testA() 
{
    // Weak store #1 provokes +initialize which performs weak store #2.
    // Solution: weak store #1 runs +initialize if needed 
    // without holding locks.
    @autoreleasepool {
        A *obj = [A new];
        strong2 = newAlignedString(obj);
        [obj addObserver:obj forKeyPath:@"foo" options:0 context:0];
        weak1 = obj;  // weak store #1
        [obj removeObserver:obj forKeyPath:@"foo"];
        obj = nil;
    }
}


__weak NSObject *weak3;
__weak NSMutableString *weak4;
NSMutableString *strong4;

@interface B : NSObject @end
@implementation B
+(void)initialize {
    weak4 = strong4;  // weak store #4
    strong4 = nil;
}
@end


void testB() 
{
    // Weak load #3 provokes +initialize which performs weak store #4.
    // Solution: object_setClass() runs +initialize if needed 
    // without holding locks.
    @autoreleasepool {
        B *obj = [B new];
        strong4 = newAlignedString(obj);
        weak3 = obj;
        [obj addObserver:obj forKeyPath:@"foo" options:0 context:0];
        [weak3 self];  // weak load #3
        [obj removeObserver:obj forKeyPath:@"foo"];
        obj = nil;
    }
}


__weak id weak5;

@interface C : NSObject @end
@implementation C
+(void)initialize {
    weak5 = [self new];
}
@end

void testC()
{
    // +initialize performs a weak store of itself. 
    // Make sure the retry in objc_storeWeak() doesn't spin.
    @autoreleasepool {
        [C self];
    }
}


int main()
{
    alarm(10);  // replace hangs with crashes

    testA();
    testB();
    testC();

    succeed(__FILE__);
}

