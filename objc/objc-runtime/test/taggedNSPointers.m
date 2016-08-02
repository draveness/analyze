// TEST_CFLAGS -framework Foundation

#include "test.h"
#include <objc/runtime.h>
#import <Foundation/Foundation.h>

#if OBJC_HAVE_TAGGED_POINTERS

void testTaggedNumber()
{
    NSNumber *taggedNS = [NSNumber numberWithInt: 1234];
    CFNumberRef taggedCF = (CFNumberRef)objc_unretainedPointer(taggedNS);
    int result;
    
    testassert( CFGetTypeID(taggedCF) == CFNumberGetTypeID() );
    testassert(_objc_getClassForTag(OBJC_TAG_NSNumber) == [taggedNS class]);
    
    CFNumberGetValue(taggedCF, kCFNumberIntType, &result);
    testassert(result == 1234);

    testassert(_objc_isTaggedPointer(taggedCF));
    testassert(_objc_getTaggedPointerTag(taggedCF) == OBJC_TAG_NSNumber);
    testassert(_objc_makeTaggedPointer(_objc_getTaggedPointerTag(taggedCF), _objc_getTaggedPointerValue(taggedCF)) == taggedCF);

    // do some generic object-y things to the taggedPointer instance
    CFRetain(taggedCF);
    CFRelease(taggedCF);
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject: taggedNS forKey: @"fred"];
    testassert(taggedNS == [dict objectForKey: @"fred"]);
    [dict setObject: @"bob" forKey: taggedNS];
    testassert([@"bob" isEqualToString: [dict objectForKey: taggedNS]]);
    
    NSNumber *iM88 = [NSNumber numberWithInt:-88];
    NSNumber *i12346 = [NSNumber numberWithInt: 12346];
    NSNumber *i12347 = [NSNumber numberWithInt: 12347];
    
    NSArray *anArray = [NSArray arrayWithObjects: iM88, i12346, i12347, nil];
    testassert([anArray count] == 3);
    testassert([anArray indexOfObject: i12346] == 1);
    
    NSSet *aSet = [NSSet setWithObjects: iM88, i12346, i12347, nil];
    testassert([aSet count] == 3);
    testassert([aSet containsObject: i12346]);
    
    [taggedNS performSelector: @selector(intValue)];
    testassert(![taggedNS isProxy]);
    testassert([taggedNS isKindOfClass: [NSNumber class]]);
    testassert([taggedNS respondsToSelector: @selector(intValue)]);
    
    (void)[taggedNS description];
}

int main()
{
    PUSH_POOL {
        testTaggedNumber(); // should be tested by CF... our tests are wrong, wrong, wrong.
    } POP_POOL;

    succeed(__FILE__);
}

// OBJC_HAVE_TAGGED_POINTERS
#else
// not OBJC_HAVE_TAGGED_POINTERS

// Tagged pointers not supported. Crash if an NSNumber actually 
// is a tagged pointer (which means this test is out of date).

int main() 
{
    PUSH_POOL {
        testassert(*(void **)objc_unretainedPointer([NSNumber numberWithInt:1234]));
    } POP_POOL;
    
    succeed(__FILE__);
}

#endif
