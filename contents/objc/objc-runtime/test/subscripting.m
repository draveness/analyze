// TEST_CONFIG MEM=arc,mrc CC=clang LANGUAGE=objc,objc++
// TEST_CFLAGS -framework Foundation

#if !__OBJC2__

#include "test.h"

int main()
{
    succeed(__FILE__);
}

#else

#import <Foundation/Foundation.h>
#import <Foundation/NSDictionary.h>
#import <objc/runtime.h>
#import <objc/objc-abi.h>
#include "test.h"

@interface TestIndexed : NSObject <NSFastEnumeration> {
    NSMutableArray *indexedValues;
}
@property(readonly) NSUInteger count;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index;
@end

@implementation TestIndexed

- (id)init {
    if ((self = [super init])) {
        indexedValues = [NSMutableArray new];
    }
    return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc {
    [indexedValues release];
    [super dealloc];
}
#endif

- (NSUInteger)count { return [indexedValues count]; }
- (id)objectAtIndexedSubscript:(NSUInteger)index { return [indexedValues objectAtIndex:index]; }
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index {
    if (index == NSNotFound)
        [indexedValues addObject:object];
    else
        [indexedValues replaceObjectAtIndex:index withObject:object];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"indexedValues = %@", indexedValues];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
    return [indexedValues countByEnumeratingWithState:state objects:buffer count:len];
}


@end

@interface TestKeyed : NSObject <NSFastEnumeration> {
    NSMutableDictionary *keyedValues;
}
@property(readonly) NSUInteger count;
- (id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
@end

@implementation TestKeyed

- (id)init {
    if ((self = [super init])) {
        keyedValues = [NSMutableDictionary new];
    }
    return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc {
    [keyedValues release];
    [super dealloc];
}
#endif

- (NSUInteger)count { return [keyedValues count]; }
- (id)objectForKeyedSubscript:(id)key { return [keyedValues objectForKey:key]; }
- (void)setObject:(id)object forKeyedSubscript:(id)key {
    [keyedValues setObject:object forKey:key];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"keyedValues = %@", keyedValues];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
    return [keyedValues countByEnumeratingWithState:state objects:buffer count:len];
}

@end

int main() {
    PUSH_POOL {

#if __has_feature(objc_bool)    // placeholder until we get a more precise macro.
        TestIndexed *testIndexed = [TestIndexed new];
        id objects[] = { @1, @2, @3, @4, @5 };
        size_t i, count = sizeof(objects) / sizeof(id);
        for (i = 0; i < count; ++i) {
            testIndexed[NSNotFound] = objects[i];
        }
        for (i = 0; i < count; ++i) {
            id object = testIndexed[i];
            testassert(object == objects[i]);
        }
        if (getenv("VERBOSE")) {
            i = 0;
            for (id object in testIndexed) {
                NSString *message = [NSString stringWithFormat:@"testIndexed[%zu] = %@\n", i++, object];
                testprintf([message UTF8String]);
            }
        }

        TestKeyed *testKeyed = [TestKeyed new];
        id keys[] = { @"One", @"Two", @"Three", @"Four", @"Five" };
        for (i = 0; i < count; ++i) {
            id key = keys[i];
            testKeyed[key] = objects[i];
        }
        for (i = 0; i < count; ++i) {
            id key = keys[i];
            id object = testKeyed[key];
            testassert(object == objects[i]);
        }
        if (getenv("VERBOSE")) {
            for (id key in testKeyed) {
                NSString *message = [NSString stringWithFormat:@"testKeyed[@\"%@\"] = %@\n", key, testKeyed[key]];
                testprintf([message UTF8String]);
            }
        }
#endif
        
    } POP_POOL;

    succeed(__FILE__);

    return 0;
}

// __OBJC2__
#endif
