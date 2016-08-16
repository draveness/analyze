// TEST_CONFIG MEM=mrc
/*
TEST_RUN_OUTPUT
objc\[\d+\]: Deallocator object 0x[0-9a-fA-F]+ overreleased while already deallocating; break on objc_overrelease_during_dealloc_error to debug
OK: bigrc.m
OR
no overrelease enforcement
OK: bigrc.m
END
 */

#include "test.h"
#include "testroot.i"

static size_t LOTS;

@interface Deallocator : TestRoot @end
@implementation Deallocator

-(void)dealloc 
{
    id o = self;
    size_t rc = 1;


    testprintf("Retain a lot during dealloc\n");

    testassert(rc == 1);
    testassert([o retainCount] == rc);
    do {
        [o retain];
        if (rc % 0x100000 == 0) testprintf("%zx/%zx ++\n", rc, LOTS);
    } while (++rc < LOTS);

    testassert([o retainCount] == rc);

    do {
        [o release];
        if (rc % 0x100000 == 0) testprintf("%zx/%zx --\n", rc, LOTS);
    } while (--rc > 1);

    testassert(rc == 1);
    testassert([o retainCount] == rc);


    testprintf("Overrelease during dealloc\n");

    // Not all architectures enforce this.
#if !SUPPORT_NONPOINTER_ISA
    testwarn("no overrelease enforcement");
    fprintf(stderr, "no overrelease enforcement\n");
#endif
    [o release];

    [super dealloc];
}

@end


int main()
{
    Deallocator *o = [Deallocator new];
    size_t rc = 1;

    [o retain];

    uintptr_t isa = *(uintptr_t *)o;
    if (isa & 1) {
        // Assume refcount in high bits.
        LOTS = 1 << (4 + __builtin_clzll(isa));
        testprintf("LOTS %zu via cntlzw\n", LOTS);
    } else {
        LOTS = 0x1000000;
        testprintf("LOTS %zu via guess\n", LOTS);
    }

    [o release];    


    testprintf("Retain a lot\n");

    testassert(rc == 1);
    testassert([o retainCount] == rc);
    do {
        [o retain];
        if (rc % 0x100000 == 0) testprintf("%zx/%zx ++\n", rc, LOTS);
    } while (++rc < LOTS);

    testassert([o retainCount] == rc);

    do {
        [o release];
        if (rc % 0x100000 == 0) testprintf("%zx/%zx --\n", rc, LOTS);
    } while (--rc > 1);

    testassert(rc == 1);
    testassert([o retainCount] == rc);


    testprintf("tryRetain a lot\n");

    id w;
    objc_storeWeak(&w, o);
    testassert(w == o);

    testassert(rc == 1);
    testassert([o retainCount] == rc);
    do {
        objc_loadWeakRetained(&w);
        if (rc % 0x100000 == 0) testprintf("%zx/%zx ++\n", rc, LOTS);
    } while (++rc < LOTS);

    testassert([o retainCount] == rc);

    do {
        [o release];
        if (rc % 0x100000 == 0) testprintf("%zx/%zx --\n", rc, LOTS);
    } while (--rc > 1);

    testassert(rc == 1);
    testassert([o retainCount] == rc);
    
    testprintf("dealloc\n");

    testassert(TestRootDealloc == 0);
    testassert(w != nil);
    [o release];
    testassert(TestRootDealloc == 1);
    testassert(w == nil);

    succeed(__FILE__);
}
