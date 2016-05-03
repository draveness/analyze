// TEST_CFLAGS -framework Foundation

#include "test.h"
#import <Foundation/Foundation.h>

/* foreach tester */

int Errors = 0;

bool testHandwritten(const char *style, const char *test, const char *message, id collection, NSSet *reference) {
    unsigned int counter = 0;
    bool result = true;
    testprintf("testing: %s %s %s\n", style, test, message);
/*
    for (id elem in collection)
        if ([reference member:elem]) ++counter;
 */
   NSFastEnumerationState state; 
   id __unsafe_unretained buffer[4];
   state.state = 0;
   NSUInteger limit = [collection countByEnumeratingWithState:&state objects:buffer count:4];
   if (limit != 0) {
        unsigned long mutationsPtr = *state.mutationsPtr;
        do {
            unsigned long innerCounter = 0;
            do {
                if (mutationsPtr != *state.mutationsPtr) objc_enumerationMutation(collection);
                id elem = state.itemsPtr[innerCounter++];
                
                if ([reference member:elem]) ++counter;
                
            } while (innerCounter < limit);
        } while ((limit = [collection countByEnumeratingWithState:&state objects:buffer count:4]));
    }
            
 
 
    if (counter == [reference count]) {
        testprintf("success: %s %s %s\n", style, test, message);
    }
    else {
        result = false;
        printf("** failed: %s %s %s (%d vs %d)\n", style, test, message, counter, (int)[reference count]);
        ++Errors;
    }
    return result;
}

bool testCompiler(const char *style, const char *test, const char *message, id collection, NSSet *reference) {
    unsigned int counter = 0;
    bool result = true;
    testprintf("testing: %s %s %s\n", style, test, message);
    for (id elem in collection)
        if ([reference member:elem]) ++counter;
    if (counter == [reference count]) {
        testprintf("success: %s %s %s\n", style, test, message);
    }
    else {
        result = false;
        printf("** failed: %s %s %s (%d vs %d)\n", style, test, message, counter, (int)[reference count]);
        ++Errors;
    }
    return result;
}

void testContinue(NSArray *array) {
    bool broken = false;
    testprintf("testing: continue statements\n");
    for (id __unused elem in array) {
        if ([array count])
            continue;
        broken = true;
    }
    if (broken) {
        printf("** continue statement did not work\n");
        ++Errors;
    }
}

            
// array is filled with NSNumbers, in order, from 0 - N
bool testBreak(unsigned int where, NSArray *array) {
    PUSH_POOL {
        unsigned int counter = 0;
        id enumerator = [array objectEnumerator];
        for (id __unused elem in enumerator) {
            if (++counter == where)
                break;
        }
        if (counter != where) {
            ++Errors;
            printf("*** break at %d didn't work (actual was %d)\n", where, counter);
            return false;
        }
        for (id __unused elem in enumerator)
            ++counter;
        if (counter != [array count]) {
            ++Errors;
            printf("*** break at %d didn't finish (actual was %d)\n", where, counter);
            return false;
        }
    } POP_POOL;
    return true;
}
    
bool testBreaks(NSArray *array) {
    bool result = true;
    testprintf("testing breaks\n");
    unsigned int counter = 0;
    for (counter = 1; counter < [array count]; ++counter) {
        result = testBreak(counter, array) && result;
    }
    return result;
}
        
bool testCompleteness(const char *test, const char *message, id collection, NSSet *reference) {
    bool result = true;
    result = result && testHandwritten("handwritten", test, message, collection, reference);
    result = result && testCompiler("compiler", test, message, collection, reference);
    return result;
}

bool testEnumerator(const char *test, const char *message, id collection, NSSet *reference) {
    bool result = true;
    result = result && testHandwritten("handwritten", test, message, [collection objectEnumerator], reference);
    result = result && testCompiler("compiler", test, message, [collection objectEnumerator], reference);
    return result;
}    
    
NSMutableSet *ReferenceSet = nil;
NSMutableArray *ReferenceArray = nil;

void makeReferences(int n) {
    if (!ReferenceSet) {
        int i;
        ReferenceSet = [[NSMutableSet alloc] init];
        ReferenceArray = [[NSMutableArray alloc] init];
        for (i = 0; i < n; ++i) {
            NSNumber *number = [[NSNumber alloc] initWithInt:i];
            [ReferenceSet addObject:number];
            [ReferenceArray addObject:number];
            RELEASE_VAR(number);
        }
    }
}
    
void testCollections(const char *test, NSArray *array, NSSet *set) {
    PUSH_POOL {
        id collection;
        collection = [NSMutableArray arrayWithArray:array];
        testCompleteness(test, "mutable array", collection, set);
        testEnumerator(test, "mutable array enumerator", collection, set);
        collection = [NSArray arrayWithArray:array];
        testCompleteness(test, "immutable array", collection, set);
        testEnumerator(test, "immutable array enumerator", collection, set);
        collection = set;
        testCompleteness(test, "immutable set", collection, set);
        testEnumerator(test, "immutable set enumerator", collection, set);
        collection = [NSMutableSet setWithArray:array];
        testCompleteness(test, "mutable set", collection, set);
        testEnumerator(test, "mutable set enumerator", collection, set);
    } POP_POOL;
}

void testInnerDecl(const char *test, const char *message, id collection) {
    unsigned int counter = 0;
    for (id __unused x in collection)
        ++counter;
    if (counter != [collection count]) {
        printf("** failed: %s %s\n", test, message);
        ++Errors;
    }
}


void testOuterDecl(const char *test, const char *message, id collection) {
    unsigned int counter = 0;
    id x;
    for (x in collection)
        ++counter;
    if (counter != [collection count]) {
        printf("** failed: %s %s\n", test, message);
        ++Errors;
    }
}
void testInnerExpression(const char *test, const char *message, id collection) {
    unsigned int counter = 0;
    for (id __unused x in [collection self])
        ++counter;
    if (counter != [collection count]) {
        printf("** failed: %s %s\n", test, message);
        ++Errors;
    }
}
void testOuterExpression(const char *test, const char *message, id collection) {
    unsigned int counter = 0;
    id x;
    for (x in [collection self])
        ++counter;
    if (counter != [collection count]) {
        printf("** failed: %s %s\n", test, message);
        ++Errors;
    }
}

void testExpressions(const char *message, id collection) {
    testInnerDecl("inner", message, collection);
    testOuterDecl("outer", message, collection);
    testInnerExpression("outer expression", message, collection);
    testOuterExpression("outer expression", message, collection);
}
    

int main() {
    PUSH_POOL {
        testCollections("nil", nil, nil);
        testCollections("empty", [NSArray array], [NSSet set]);
        makeReferences(100);
        testCollections("100 item", ReferenceArray, ReferenceSet);
        testExpressions("array", ReferenceArray);
        testBreaks(ReferenceArray);
        testContinue(ReferenceArray);
        if (Errors == 0) succeed(__FILE__);
        else fail("foreach %d errors detected\n", Errors);
    } POP_POOL;
    exit(Errors);
}
