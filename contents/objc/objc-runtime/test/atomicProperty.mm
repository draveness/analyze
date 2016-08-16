// TEST_CONFIG CC=clang

#include "test.h"
#include <objc/runtime.h>
#include <objc/objc-internal.h>
#import <Foundation/NSObject.h>

class SerialNumber {
    size_t _number;
public:
    SerialNumber() : _number(42) {}
    SerialNumber(const SerialNumber &number) : _number(number._number + 1) {}
    SerialNumber &operator=(const SerialNumber &number) { _number = number._number + 1; return *this; }

    int operator==(const SerialNumber &number) { return _number == number._number; }
    int operator!=(const SerialNumber &number) { return _number != number._number; }
};

@interface TestAtomicProperty : NSObject {
    SerialNumber number;
}
@property(atomic) SerialNumber number;
@end

@implementation TestAtomicProperty

@synthesize number;

@end

int main()
{
    PUSH_POOL {
        SerialNumber number;
        TestAtomicProperty *test = [TestAtomicProperty new];
        test.number = number;
        testassert(test.number != number);
    } POP_POOL;

    succeed(__FILE__);
}
