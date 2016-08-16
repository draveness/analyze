// TEST_CONFIG

#include "test.h"
#include <mach/mach.h>
#include <malloc/malloc.h>

// Look for malloc zone "ObjC" iff OBJC_USE_INTERNAL_ZONE is set.
// This fails if objc tries to allocate before checking its own 
// environment variables (rdar://6688423)

int main()
{
    if (is_guardmalloc()) {
        // guard malloc confuses this test
        succeed(__FILE__);
    }

    kern_return_t kr;
    vm_address_t *zones;
    unsigned int count, i;
    BOOL has_objc = NO, want_objc = NO;

    want_objc = (getenv("OBJC_USE_INTERNAL_ZONE") != NULL) ? YES : NO;
    testprintf("want objc %s\n", want_objc ? "YES" : "NO");

    kr = malloc_get_all_zones(mach_task_self(), NULL, &zones, &count);
    testassert(!kr);
    for (i = 0; i < count; i++) {
        const char *name = malloc_get_zone_name((malloc_zone_t *)zones[i]);
        if (name) {
            BOOL is_objc = (0 == strcmp(name, "ObjC_Internal")) ? YES : NO;
            if (is_objc) has_objc = YES;
            testprintf("zone %s\n", name);
        }
    }

    testassert(want_objc == has_objc);

    succeed(__FILE__);
}
