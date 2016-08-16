// TEST_CONFIG

#include "test.h"
#include "testroot.i"

int state = 0;
int catstate = 0;
int deallocstate = 0;

@interface Deallocator : TestRoot @end
@implementation Deallocator
-(id)init {
    self = [super init];
    if (objc_collectingEnabled()) {
        deallocstate = 1;
    }
    return self;
}
-(void)dealloc {
    deallocstate = 1;
    SUPER_DEALLOC();
}
@end


@interface Super : TestRoot @end
@implementation Super
+(void)initialize { 
    if (self == [Super class]) {
        testprintf("in +[Super initialize]\n");
        testassert(state == 2);
        state = 3;
    } else { 
        testprintf("in +[Super initialize] on behalf of Sub\n");
        testassert(state == 3);
        state = 4;
    }
} 
-(void)load { fail("-[Super load] called!"); }
+(void)load { 
    testprintf("in +[Super load]\n");
    testassert(state == 0); 
    state = 1;
} 
@end

@interface Sub : Super { }  @end
@implementation Sub
+(void)load { 
    testprintf("in +[Sub load]\n");
    testassert(state == 1); 
    state = 2;
} 
-(void)load { fail("-[Sub load] called!"); } 
@end

@interface SubNoLoad : Super { } @end
@implementation SubNoLoad @end

@interface Super (Category) @end
@implementation Super (Category) 
-(void)load { fail("-[Super(Category) load called!"); }
+(void)load {
    testprintf("in +[Super(Category) load]\n");
    testassert(state >= 1); 
    catstate++;
}
@end


@interface Sub (Category) @end
@implementation Sub (Category) 
-(void)load { fail("-[Sub(Category) load called!"); }
+(void)load {
    testprintf("in +[Sub(Category) load]\n");
    testassert(state >= 2); 
    catstate++;

    // test autorelease pool
    __autoreleasing id x;
    x = AUTORELEASE([Deallocator new]);
}
@end


@interface SubNoLoad (Category) @end
@implementation SubNoLoad (Category) 
-(void)load { fail("-[SubNoLoad(Category) load called!"); }
+(void)load {
    testprintf("in +[SubNoLoad(Category) load]\n");
    testassert(state >= 1); 
    catstate++;
}
@end

int main()
{
    testassert(state == 2);
    testassert(catstate == 3);
    testassert(deallocstate == 1);
    [Sub class];
    testassert(state == 4);
    testassert(catstate == 3);

    succeed(__FILE__);
}
