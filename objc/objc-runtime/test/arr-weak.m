// TEST_CONFIG MEM=mrc
// TEST_CRASHES
/*
TEST_RUN_OUTPUT
objc\[\d+\]: Cannot form weak reference to instance \(0x[0-9a-f]+\) of class Crash. It is possible that this object was over-released, or is in the process of deallocation.
CRASHED: SIG(ILL|TRAP)
END
*/

#include "test.h"

#include <Foundation/NSObject.h>

static id weak;
static id weak2;
static id weak3;
static id weak4;
static bool did_dealloc;

static int state;

@interface NSObject (WeakInternals)
-(BOOL)_tryRetain;
-(BOOL)_isDeallocating;
@end

@interface Test : NSObject @end
@implementation Test 
-(void)dealloc {
    testprintf("Weak storeOrNil does not crash while deallocating\n");
    weak4 = (id)0x100;  // old value must not be used
    id result = objc_initWeakOrNil(&weak4, self);
    testassert(result == nil);
    testassert(weak4 == nil);
    result = objc_storeWeakOrNil(&weak4, self);
    testassert(result == nil);
    testassert(weak4 == nil);

    // The value returned by objc_loadWeak() is now nil, 
    // but the storage is not yet cleared.
    testassert(weak == self);
    testassert(weak2 == self);

    // objc_loadWeak() does not eagerly clear the storage.
    testassert(objc_loadWeakRetained(&weak) == nil);
    testassert(weak != nil);

    // dealloc clears the storage.
    testprintf("Weak references clear during super dealloc\n");
    testassert(weak2 != nil);
    [super dealloc];
    testassert(weak == nil);
    testassert(weak2 == nil);

    did_dealloc = true;
}
@end

@interface CustomTryRetain : Test @end
@implementation CustomTryRetain
-(BOOL)_tryRetain { state++; return [super _tryRetain]; }
@end

@interface CustomIsDeallocating : Test @end
@implementation CustomIsDeallocating
-(BOOL)_isDeallocating { state++; return [super _isDeallocating]; }
@end

@interface CustomAllowsWeakReference : Test @end
@implementation CustomAllowsWeakReference
-(BOOL)allowsWeakReference { state++; return [super allowsWeakReference]; }
@end

@interface CustomRetainWeakReference : Test @end
@implementation CustomRetainWeakReference
-(BOOL)retainWeakReference { state++; return [super retainWeakReference]; }
@end

@interface Crash : NSObject @end
@implementation Crash
-(void)dealloc {
    testassert(weak == self);
    testassert(weak2 == self);
    testassert(objc_loadWeakRetained(&weak) == nil);
    testassert(objc_loadWeakRetained(&weak2) == nil);

    testprintf("Weak storeOrNil does not crash while deallocating\n");
    id result = objc_storeWeakOrNil(&weak, self);
    testassert(result == nil);

    testprintf("Weak store crashes while deallocating\n");
    objc_storeWeak(&weak, self);
    fail("objc_storeWeak of deallocating value should have crashed");
    [super dealloc];
}
@end


void cycle(Class cls, Test *obj, Test *obj2, bool storeOrNil)
{
    testprintf("Cycling class %s\n", class_getName(cls));

    id result;

    id (*storeWeak)(id *location, id obj);
    id (*initWeak)(id *location, id obj);
    if (storeOrNil) {
        testprintf("Using objc_storeWeakOrNil\n");
        storeWeak = objc_storeWeakOrNil;
        initWeak = objc_initWeakOrNil;
    } else {
        testprintf("Using objc_storeWeak\n");
        storeWeak = objc_storeWeak;
        initWeak = objc_initWeak;
    }

    // state counts calls to custom weak methods
    // Difference test classes have different expected values.
    int storeTarget;
    int loadTarget;
    if (cls == [Test class]) {
        storeTarget = 0;
        loadTarget = 0;
    }
    else if (cls == [CustomTryRetain class] || 
             cls == [CustomRetainWeakReference class])
    {
        storeTarget = 0;
        loadTarget = 1;
    }
    else if (cls == [CustomIsDeallocating class] || 
             cls == [CustomAllowsWeakReference class])
    {
        storeTarget = 1;
        loadTarget = 0;
    }
    else fail("wut");

    testprintf("Weak assignment\n");
    state = 0;
    result = storeWeak(&weak, obj);
    testassert(state == storeTarget);
    testassert(result == obj);
    testassert(weak == obj);

    testprintf("Weak assignment to the same value\n");
    state = 0;
    result = storeWeak(&weak, obj);
    testassert(state == storeTarget);
    testassert(result == obj);
    testassert(weak == obj);

    testprintf("Weak load\n");
    state = 0;
    result = objc_loadWeakRetained(&weak);
    if (state != loadTarget) testprintf("state %d target %d\n", state, loadTarget);
    testassert(state == loadTarget);
    testassert(result == obj);
    testassert(result == weak);
    [result release];

    testprintf("Weak assignment to different value\n");
    state = 0;
    result = storeWeak(&weak, obj2);
    testassert(state == storeTarget);
    testassert(result == obj2);
    testassert(weak == obj2);

    testprintf("Weak assignment to NULL\n");
    state = 0;
    result = storeWeak(&weak, NULL);
    testassert(state == 0);
    testassert(result == NULL);
    testassert(weak == NULL);

    testprintf("Weak re-assignment to NULL\n");
    state = 0;
    result = storeWeak(&weak, NULL);
    testassert(state == 0);
    testassert(result == NULL);
    testassert(weak == NULL);

    testprintf("Weak move\n");
    state = 0;
    result = storeWeak(&weak, obj);
    testassert(state == storeTarget);
    testassert(result == obj);
    testassert(weak == obj);
    weak2 = (id)(PAGE_MAX_SIZE-16);
    objc_moveWeak(&weak2, &weak);
    testassert(weak == nil);
    testassert(weak2 == obj);
    storeWeak(&weak2, NULL);

    testprintf("Weak copy\n");
    state = 0;
    result = storeWeak(&weak, obj);
    testassert(state == storeTarget);
    testassert(result == obj);
    testassert(weak == obj);
    weak2 = (id)(PAGE_MAX_SIZE-16);
    objc_copyWeak(&weak2, &weak);
    testassert(weak == obj);
    testassert(weak2 == obj);
    storeWeak(&weak, NULL);
    storeWeak(&weak2, NULL);

    testprintf("Weak clear\n");

    id obj3 = [cls new];

    state = 0;
    result = storeWeak(&weak, obj3);
    testassert(state == storeTarget);
    testassert(result == obj3);
    testassert(weak == obj3);

    state = 0;
    result = storeWeak(&weak2, obj3);
    testassert(state == storeTarget);
    testassert(result == obj3);
    testassert(weak2 == obj3);

    did_dealloc = false;
    [obj3 release];
    testassert(did_dealloc);
    testassert(weak == NULL);
    testassert(weak2 == NULL);


    testprintf("Weak init and destroy\n");

    id obj4 = [cls new];
    
    state = 0;
    weak = (id)0x100;  // old value must not be used
    result = initWeak(&weak, obj4);
    testassert(state == storeTarget);
    testassert(result == obj4);
    testassert(weak == obj4);
    
    state = 0;
    weak2 = (id)0x100;  // old value must not be used
    result = initWeak(&weak2, obj4);
    testassert(state == storeTarget);
    testassert(result == obj4);
    testassert(weak2 == obj4);
    
    state = 0;
    weak3 = (id)0x100;  // old value must not be used
    result = initWeak(&weak3, obj4);
    testassert(state == storeTarget);
    testassert(result == obj4);
    testassert(weak3 == obj4);

    state = 0;
    objc_destroyWeak(&weak3);
    testassert(state == 0);
    testassert(weak3 == obj4);  // storage is unchanged

    did_dealloc = false;
    [obj4 release];
    testassert(did_dealloc);
    testassert(weak == NULL);   // not destroyed earlier so cleared now
    testassert(weak2 == NULL);  // not destroyed earlier so cleared now
    testassert(weak3 == obj4);  // destroyed earlier so not cleared now

    objc_destroyWeak(&weak);
    objc_destroyWeak(&weak2);
}


void test_class(Class cls)
{
    // prime strong and weak side tables before leak checking
    Test *prime[256] = {nil};
    for (size_t i = 0; i < sizeof(prime)/sizeof(prime[0]); i++) {
        objc_storeWeak(&prime[i], [cls new]);
    }

    Test *obj = [cls new];
    Test *obj2 = [cls new];

    for (int i = 0; i < 100000; i++) {
        cycle(cls, obj, obj2, false);
        cycle(cls, obj, obj2, true);
    }
    leak_mark();
    for (int i = 0; i < 100000; i++) {
        cycle(cls, obj, obj2, false);
        cycle(cls, obj, obj2, true);
    }
    // allow some slop for side table expansion
    // 5120 is common with this configuration
    leak_check(6000);

    // rdar://14105994
    id weaks[8];
    for (size_t i = 0; i < sizeof(weaks)/sizeof(weaks[0]); i++) {
        objc_storeWeak(&weaks[i], obj);
    }
    for (size_t i = 0; i < sizeof(weaks)/sizeof(weaks[0]); i++) {
        objc_storeWeak(&weaks[i], nil);
    }
}

int main()
{
    test_class([Test class]);
    test_class([CustomTryRetain class]);
    test_class([CustomIsDeallocating class]);
    test_class([CustomAllowsWeakReference class]);
    test_class([CustomRetainWeakReference class]);


    id result;

    Crash *obj3 = [Crash new];
    result = objc_storeWeak(&weak, obj3);
    testassert(result == obj3);
    testassert(weak == obj3);

    result = objc_storeWeak(&weak2, obj3);
    testassert(result == obj3);
    testassert(weak2 == obj3);

    [obj3 release];
    fail("should have crashed in -[Crash dealloc]");
}
