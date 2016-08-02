/*
TEST_CRASHES
TEST_RUN_OUTPUT
objc1
OK: badCache.m
OR
crash now
objc\[\d+\]: Method cache corrupted.*
objc\[\d+\]: .*
objc\[\d+\]: .*
objc\[\d+\]: .*
objc\[\d+\]: .*
objc\[\d+\]: Method cache corrupted\.
CRASHED: SIG(ILL|TRAP)
END
*/


#include "test.h"

#if !__OBJC2__  ||  __arm__

int main()
{
    fprintf(stderr, "objc1\n");
    succeed(__FILE__);
}

#else

#include "testroot.i"

#if __LP64__
typedef uint32_t mask_t;
#else
typedef uint16_t mask_t;
#endif

struct bucket_t {
    uintptr_t sel;
    uintptr_t imp;
};

struct cache_t {
    struct bucket_t *buckets;
    mask_t mask;
    mask_t occupied;
};

struct class_t {
    void *isa;
    void *supercls;
    struct cache_t cache;
};

@interface Subclass : TestRoot @end
@implementation Subclass @end

int main()
{
    Class cls = [TestRoot class];
    id obj = [cls new];
    [obj self];

    struct cache_t *cache = &((__bridge struct class_t *)cls)->cache;

#   define COUNT 4
    struct bucket_t *buckets = calloc(sizeof(struct bucket_t), COUNT+1);
    for (int i = 0; i < COUNT; i++) {
        buckets[i].sel = ~0;
        buckets[i].imp = ~0;
    }
    buckets[COUNT].sel = 1;
    buckets[COUNT].imp = (uintptr_t)buckets;

    cache->mask = COUNT-1;
    cache->occupied = 0;
    cache->buckets = buckets;

    fprintf(stderr, "crash now\n");
    [obj self];

    fail("should have crashed");
}

#endif
