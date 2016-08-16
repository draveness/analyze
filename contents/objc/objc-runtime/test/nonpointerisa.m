// TEST_CFLAGS -framework Foundation
// TEST_CONFIG MEM=mrc

#include "test.h"

#if !__OBJC2__

int main()
{
    succeed(__FILE__);
}

#else

#include <dlfcn.h>

#include <objc/objc-gdb.h>
#include <Foundation/Foundation.h>

#define ISA(x) (*((uintptr_t *)(x)))
#define INDEXED(x) (ISA(x) & 1)

#if SUPPORT_NONPOINTER_ISA
# if __x86_64__
#   define RC_ONE (1ULL<<56)
# elif __arm64__
#   define RC_ONE (1ULL<<45)
# else
#   error unknown architecture
# endif
#endif


void check_unindexed(id obj, Class cls)
{
    testassert(object_getClass(obj) == cls);
    testassert(!INDEXED(obj));

    uintptr_t isa = ISA(obj);
    testassert((Class)isa == cls);
    testassert((Class)(isa & objc_debug_isa_class_mask) == cls);
    testassert((Class)(isa & ~objc_debug_isa_class_mask) == 0);

    CFRetain(obj);
    testassert(ISA(obj) == isa);
    testassert([obj retainCount] == 2);
    [obj retain];
    testassert(ISA(obj) == isa);
    testassert([obj retainCount] == 3);
    CFRelease(obj);
    testassert(ISA(obj) == isa);
    testassert([obj retainCount] == 2);
    [obj release];
    testassert(ISA(obj) == isa);
    testassert([obj retainCount] == 1);
}


#if ! SUPPORT_NONPOINTER_ISA

int main()
{
    testprintf("Isa with index\n");
    id index_o = [NSObject new];
    check_unindexed(index_o, [NSObject class]);

    // These variables DO exist even without non-pointer isa support
    testassert(dlsym(RTLD_DEFAULT, "objc_debug_isa_class_mask"));
    testassert(dlsym(RTLD_DEFAULT, "objc_debug_isa_magic_mask"));
    testassert(dlsym(RTLD_DEFAULT, "objc_debug_isa_magic_value"));

    succeed(__FILE__);
}

#else
// SUPPORT_NONPOINTER_ISA

void check_indexed(id obj, Class cls)
{
    testassert(object_getClass(obj) == cls);
    testassert(INDEXED(obj));

    uintptr_t isa = ISA(obj);
    testassert((Class)(isa & objc_debug_isa_class_mask) == cls);
    testassert((Class)(isa & ~objc_debug_isa_class_mask) != 0);
    testassert((isa & objc_debug_isa_magic_mask) == objc_debug_isa_magic_value);

    CFRetain(obj);
    testassert(ISA(obj) == isa + RC_ONE);
    testassert([obj retainCount] == 2);
    [obj retain];
    testassert(ISA(obj) == isa + RC_ONE*2);
    testassert([obj retainCount] == 3);
    CFRelease(obj);
    testassert(ISA(obj) == isa + RC_ONE);
    testassert([obj retainCount] == 2);
    [obj release];
    testassert(ISA(obj) == isa);
    testassert([obj retainCount] == 1);
}


@interface OS_object <NSObject>
+(id)new;
@end

@interface Fake_OS_object : NSObject {
    int refcnt;
    int xref_cnt;
}
@end

@implementation Fake_OS_object
+(void)initialize {
    static bool initialized;
    if (!initialized) {
        initialized = true;
        testprintf("Indexed during +initialize\n");
        testassert(INDEXED(self));
        id o = [Fake_OS_object new];
        check_indexed(o, self);
        [o release];
    }
}
@end

@interface Sub_OS_object : OS_object @end

@implementation Sub_OS_object
@end



int main()
{
    uintptr_t isa;

    testprintf("Isa with index\n");
    id index_o = [Fake_OS_object new];
    check_indexed(index_o, [Fake_OS_object class]);

    testprintf("Weakly referenced\n");
    isa = ISA(index_o);
    id weak;
    objc_storeWeak(&weak, index_o);
    testassert(__builtin_popcountl(isa ^ ISA(index_o)) == 1);

    testprintf("Has associated references\n");
    id assoc = @"thing";
    isa = ISA(index_o);
    objc_setAssociatedObject(index_o, assoc, assoc, OBJC_ASSOCIATION_ASSIGN);
    testassert(__builtin_popcountl(isa ^ ISA(index_o)) == 1);


    testprintf("Isa without index\n");
    id unindex_o = [OS_object new];
    check_unindexed(unindex_o, [OS_object class]);


    id buf[4];
    id bufo = (id)buf;

    testprintf("Change isa 0 -> unindexed\n");
    bzero(buf, sizeof(buf));
    object_setClass(bufo, [OS_object class]);
    check_unindexed(bufo, [OS_object class]);

    testprintf("Change isa 0 -> indexed\n");
    bzero(buf, sizeof(buf));
    object_setClass(bufo, [NSObject class]);
    check_indexed(bufo, [NSObject class]);

    testprintf("Change isa indexed -> indexed\n");
    testassert(INDEXED(bufo));
    _objc_rootRetain(bufo);
    testassert(_objc_rootRetainCount(bufo) == 2);
    object_setClass(bufo, [Fake_OS_object class]);
    testassert(_objc_rootRetainCount(bufo) == 2);
    _objc_rootRelease(bufo);
    testassert(_objc_rootRetainCount(bufo) == 1);
    check_indexed(bufo, [Fake_OS_object class]);

    testprintf("Change isa indexed -> unindexed\n");
    // Retain count must be preserved.
    // Use root* to avoid OS_object's overrides.
    testassert(INDEXED(bufo));
    _objc_rootRetain(bufo);
    testassert(_objc_rootRetainCount(bufo) == 2);
    object_setClass(bufo, [OS_object class]);
    testassert(_objc_rootRetainCount(bufo) == 2);
    _objc_rootRelease(bufo);
    testassert(_objc_rootRetainCount(bufo) == 1);
    check_unindexed(bufo, [OS_object class]);

    testprintf("Change isa unindexed -> indexed (doesn't happen)\n");
    testassert(!INDEXED(bufo));
    _objc_rootRetain(bufo);
    testassert(_objc_rootRetainCount(bufo) == 2);
    object_setClass(bufo, [Fake_OS_object class]);
    testassert(_objc_rootRetainCount(bufo) == 2);
    _objc_rootRelease(bufo);
    testassert(_objc_rootRetainCount(bufo) == 1);
    check_unindexed(bufo, [Fake_OS_object class]);

    testprintf("Change isa unindexed -> unindexed\n");
    testassert(!INDEXED(bufo));
    _objc_rootRetain(bufo);
    testassert(_objc_rootRetainCount(bufo) == 2);
    object_setClass(bufo, [Sub_OS_object class]);
    testassert(_objc_rootRetainCount(bufo) == 2);
    _objc_rootRelease(bufo);
    testassert(_objc_rootRetainCount(bufo) == 1);
    check_unindexed(bufo, [Sub_OS_object class]);


    succeed(__FILE__);
}

// SUPPORT_NONPOINTER_ISA
#endif

// __OBJC2__
#endif
