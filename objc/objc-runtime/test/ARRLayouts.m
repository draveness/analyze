/*
TEST_CONFIG MEM=arc CC=clang
TEST_BUILD
    $C{COMPILE_NOLINK_NOMEM} -c $DIR/MRRBase.m
    $C{COMPILE_NOLINK_NOMEM} -c $DIR/MRRARR.m
    $C{COMPILE_NOLINK}       -c $DIR/ARRBase.m
    $C{COMPILE_NOLINK}       -c $DIR/ARRMRR.m
    $C{COMPILE} -fobjc-arc $DIR/ARRLayouts.m -x none MRRBase.o MRRARR.o ARRBase.o ARRMRR.o -framework Foundation -o ARRLayouts.out
END
*/

#include "test.h"
#import <stdio.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ARRMRR.h"
#import "MRRARR.h"

@interface NSObject (Layouts)
+ (const char *)strongLayout;
+ (const char *)weakLayout;
@end

void printlayout(const char *name, const uint8_t *layout)
{
    if (! getenv("VERBOSE")) return;

    testprintf("%s: ", name);

    if (!layout) { 
        fprintf(stderr, "NULL\n");
        return;
    }

    const uint8_t *c;
    for (c = layout; *c; c++) {
        fprintf(stderr, "%02x ", *c);
    }

    fprintf(stderr, "00\n");
}

@implementation NSObject (Layouts)

+ (const char *)strongLayout {
    const uint8_t *layout = class_getIvarLayout(self);
    printlayout("strong", layout);
    return (const char *)layout;
}

+ (const char *)weakLayout {
    const uint8_t *weakLayout = class_getWeakIvarLayout(self);
    printlayout("weak", weakLayout);
    return (const char *)weakLayout;
}

+ (Ivar)instanceVariable:(const char *)name {
    return class_getInstanceVariable(self, name);
}

@end

int main (int argc  __unused, const char * argv[] __unused) {
    // Under ARR, layout strings are relative to the class' own ivars.
    testassert(strcmp([ARRBase strongLayout], "\x11\x20") == 0);
    testassert(strcmp([ARRBase weakLayout], "\x31") == 0);
    testassert([MRRBase strongLayout] == NULL);
    testassert([MRRBase weakLayout] == NULL);
    testassert(strcmp([ARRMRR strongLayout], "\x01") == 0);
    testassert([ARRMRR weakLayout] == NULL);
    testassert([MRRARR strongLayout] == NULL);
    testassert([MRRARR weakLayout] == NULL);
    
    // now check consistency between dynamic accessors and KVC, etc.
    ARRMRR *am = [ARRMRR new];
    MRRARR *ma = [MRRARR new];

    NSString *am_description = [[NSString alloc] initWithFormat:@"%s %p", "ARRMRR", am];
    NSString *ma_description = [[NSString alloc] initWithFormat:@"%s %p", "MRRARR", ma];

    am.number = M_PI;
    object_setIvar(am, [ARRMRR instanceVariable:"object"], am_description);
    testassert(CFGetRetainCount(objc_unretainedPointer(am_description)) == 1);
    am.pointer = @selector(ARRMRR);
    object_setIvar(am, [ARRMRR instanceVariable:"delegate"], ma);
    testassert(CFGetRetainCount(objc_unretainedPointer(ma)) == 1);
    
    ma.number = M_E;
    object_setIvar(ma, [MRRARR instanceVariable:"object"], ma_description);
    testassert(CFGetRetainCount(objc_unretainedPointer(ma_description)) == 2);
    ma.pointer = @selector(MRRARR);
    ma.delegate = am;
    object_setIvar(ma, [MRRARR instanceVariable:"delegate"], am);
    testassert(CFGetRetainCount(objc_unretainedPointer(am)) == 1);
    
    succeed(__FILE__);
    return 0;
}
