// This file is used in the customrr-nsobject-*.m tests

#include "test.h"
#include <objc/NSObject.h>

#if __OBJC2__
#   define BYPASS 1
#else
// old ABI does not implement the optimization
#   define BYPASS 0
#endif

static int Retains;
static int Releases;
static int Autoreleases;
static int PlusInitializes;
static int Allocs;
static int AllocWithZones;

id (*RealRetain)(id self, SEL _cmd);
void (*RealRelease)(id self, SEL _cmd);
id (*RealAutorelease)(id self, SEL _cmd);
id (*RealAlloc)(id self, SEL _cmd);
id (*RealAllocWithZone)(id self, SEL _cmd, void *zone);

id HackRetain(id self, SEL _cmd) { Retains++; return RealRetain(self, _cmd); }
void HackRelease(id self, SEL _cmd) { Releases++; return RealRelease(self, _cmd); }
id HackAutorelease(id self, SEL _cmd) { Autoreleases++; return RealAutorelease(self, _cmd); }

id HackAlloc(Class self, SEL _cmd) { Allocs++; return RealAlloc(self, _cmd); }
id HackAllocWithZone(Class self, SEL _cmd, void *zone) { AllocWithZones++; return RealAllocWithZone(self, _cmd, zone); }

void HackPlusInitialize(id self __unused, SEL _cmd __unused) { PlusInitializes++; }


int main(int argc __unused, char **argv)
{
    Class cls = objc_getClass("NSObject");
    Method meth;

    meth = class_getClassMethod(cls, @selector(initialize));
    method_setImplementation(meth, (IMP)HackPlusInitialize);

    // We either swizzle the method normally (testing that it properly 
    // disables optimizations), or we hack the implementation into place 
    // behind objc's back (so we can see whether it got called with the 
    // optimizations still enabled).

    meth = class_getClassMethod(cls, @selector(allocWithZone:));
    RealAllocWithZone = (typeof(RealAllocWithZone))method_getImplementation(meth);
#if SWIZZLE_AWZ
    method_setImplementation(meth, (IMP)HackAllocWithZone);
#else
    ((IMP *)meth)[2] = (IMP)HackAllocWithZone;
#endif

    meth = class_getInstanceMethod(cls, @selector(release));
    RealRelease = (typeof(RealRelease))method_getImplementation(meth);
#if SWIZZLE_RELEASE
    method_setImplementation(meth, (IMP)HackRelease);
#else
    ((IMP *)meth)[2] = (IMP)HackRelease;
#endif

    // These other methods get hacked for counting purposes only

    meth = class_getInstanceMethod(cls, @selector(retain));
    RealRetain = (typeof(RealRetain))method_getImplementation(meth);
    ((IMP *)meth)[2] = (IMP)HackRetain;

    meth = class_getInstanceMethod(cls, @selector(autorelease));
    RealAutorelease = (typeof(RealAutorelease))method_getImplementation(meth);
    ((IMP *)meth)[2] = (IMP)HackAutorelease;

    meth = class_getClassMethod(cls, @selector(alloc));
    RealAlloc = (typeof(RealAlloc))method_getImplementation(meth);
    ((IMP *)meth)[2] = (IMP)HackAlloc;

    // Verify that the swizzles occurred before +initialize by provoking it now
    testassert(PlusInitializes == 0);
    [NSObject self];
    testassert(PlusInitializes == 1);

#if !__OBJC2__
    // hack: fool the expected output because old ABI doesn't optimize this 
# if SWIZZLE_AWZ
    fprintf(stderr, "objc[1234]: CUSTOM AWZ:  NSObject (meta)\n");
# endif
# if SWIZZLE_RELEASE
    fprintf(stderr, "objc[1234]: CUSTOM RR:  NSObject\n");
# endif
#endif

    id obj;

    Allocs = 0;
    AllocWithZones = 0;
    obj = objc_alloc(cls);
#if SWIZZLE_AWZ || !BYPASS
    testprintf("swizzled AWZ should be called\n");
    testassert(Allocs == 1);
    testassert(AllocWithZones == 1);
#else
    testprintf("unswizzled AWZ should be bypassed\n");
    testassert(Allocs == 0);
    testassert(AllocWithZones == 0);
#endif

    Allocs = 0;
    AllocWithZones = 0;
    obj = [NSObject alloc];
#if SWIZZLE_AWZ || !BYPASS
    testprintf("swizzled AWZ should be called\n");
    testassert(Allocs == 1);
    testassert(AllocWithZones == 1);
#else
    testprintf("unswizzled AWZ should be bypassed\n");
    testassert(Allocs == 1);
    testassert(AllocWithZones == 0);
#endif

    Retains = 0;
    objc_retain(obj);
#if SWIZZLE_RELEASE || !BYPASS
    testprintf("swizzled release should force retain\n");
    testassert(Retains == 1);
#else
    testprintf("unswizzled release should bypass retain\n");
    testassert(Retains == 0);
#endif

    Releases = 0;
    Autoreleases = 0;
    PUSH_POOL {
        objc_autorelease(obj);
#if SWIZZLE_RELEASE || !BYPASS
        testprintf("swizzled release should force autorelease\n");
        testassert(Autoreleases == 1);
#else
        testprintf("unswizzled release should bypass autorelease\n");
        testassert(Autoreleases == 0);
#endif
    } POP_POOL

#if SWIZZLE_RELEASE || !BYPASS
    testprintf("swizzled release should be called\n");
    testassert(Releases == 1);
#else
    testprintf("unswizzled release should be bypassed\n");
    testassert(Releases == 0);
#endif

    succeed(basename(argv[0]));
}
