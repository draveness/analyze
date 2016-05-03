// TEST_CFLAGS -framework Foundation
// TEST_CONFIG MEM=mrc ARCH=x86_64

// Stress-test nonpointer isa's side table retain count transfers.

// x86_64 only. arm64's side table limit is high enough that bugs 
// are harder to reproduce.

#include "test.h"
#import <Foundation/Foundation.h>

#define OBJECTS 1
#define LOOPS 256
#define THREADS 16
#if __x86_64__
#   define RC_HALF  (1ULL<<7)
#else
#   error sorry
#endif
#define RC_DELTA RC_HALF

static bool Deallocated = false;
@interface Deallocator : NSObject @end
@implementation Deallocator
-(void)dealloc {
    Deallocated = true;
    [super dealloc];
}
@end

// This is global to avoid extra retains by the dispatch block objects.
static Deallocator *obj;

int main() {
    dispatch_queue_t queue = 
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (size_t i = 0; i < OBJECTS; i++) {
        obj = [Deallocator new];

        dispatch_apply(THREADS, queue, ^(size_t i __unused) {
            for (size_t a = 0; a < LOOPS; a++) {
                for (size_t b = 0; b < RC_DELTA; b++) {
                    [obj retain];
                }
                for (size_t b = 0; b < RC_DELTA; b++) {
                    [obj release];
                }
            }
        });

        testassert(!Deallocated);
        [obj release];
        testassert(Deallocated);
        Deallocated = false;
    }

    succeed(__FILE__);
}
