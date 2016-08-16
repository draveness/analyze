// TEST_CONFIG MEM=gc OS=macosx

#include "test.h"
#include <string.h>
#include <objc/objc-runtime.h>

@class NSObject;

void printlayout(const char *name, const uint8_t *layout)
{
    testprintf("%s: ", name);

    if (!layout) { 
        testprintf("NULL\n");
        return;
    }

    const uint8_t *c;
    for (c = layout; *c; c++) {
        testprintf("%02x ", *c);
    }

    testprintf("00\n");
}

OBJC_ROOT_CLASS
@interface Super { id isa; } @end
@implementation Super @end


// strong: 0c 00  (0a00 without structs)
// weak: NULL
@interface AllScanned : Super { 
    id id1;
    NSObject *o1;
    __strong void *v1;
    __strong intptr_t *i1;
    __strong long *l1;
    /* fixme
    struct {
        id id1;
        id id2;
    } str;
    */
    id arr1[4];
} 
@end
@implementation AllScanned @end

// strong: 00
// weak: 1b 00 (18 00 without structs)
@interface AllWeak : Super {
    __weak id id1;
    __weak NSObject *o1;
    __weak void *v1;
    __weak intptr_t *i1;
    __weak long *l1;
    /* fixme
    struct {
        __weak id id1;
        __weak id id2;
    } str; 
    */
    __weak id arr1[4];
}
@end
@implementation AllWeak @end

// strong: ""
// weak: NULL
OBJC_ROOT_CLASS
@interface NoScanned { long i;  } @end
@implementation NoScanned @end

int main() 
{
    const uint8_t *layout;

    layout = class_getIvarLayout(objc_getClass("AllScanned"));
    printlayout("AllScanned", layout);
    layout = class_getWeakIvarLayout(objc_getClass("AllScanned"));
    printlayout("AllScanned weak", layout);
    // testassert(0 == strcmp(layout, "\x0a"));

    layout = class_getIvarLayout(objc_getClass("AllWeak"));
    printlayout("AllWeak", layout);
    layout = class_getWeakIvarLayout(objc_getClass("AllWeak"));
    printlayout("AllWeak weak", layout);
    // testassert(0 == strcmp(layout, ""));

    layout = class_getIvarLayout(objc_getClass("NoScanned"));
    printlayout("NoScanned", layout);
    // testassert(0 == strcmp(layout, ""));

    succeed(__FILE__);
    return 0;
}
