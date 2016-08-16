// TEST_CONFIG

#if USE_FOUNDATION
#include <Foundation/Foundation.h>
#define SUPERCLASS NSObject
#define FILENAME "nscdtors.mm"
#else
#define SUPERCLASS TestRoot
#define FILENAME "cdtors.mm"
#endif

#include "test.h"

#include <pthread.h>
#include "objc/objc-internal.h"
#include "testroot.i"

static unsigned ctors1 = 0;
static unsigned dtors1 = 0;
static unsigned ctors2 = 0;
static unsigned dtors2 = 0;

class cxx1 {
    unsigned & ctors;
    unsigned& dtors;

  public:
    cxx1() : ctors(ctors1), dtors(dtors1) { ctors++; }

    ~cxx1() { dtors++; }
};
class cxx2 {
    unsigned& ctors;
    unsigned& dtors;

  public:
    cxx2() : ctors(ctors2), dtors(dtors2) { ctors++; }

    ~cxx2() { dtors++; }
};

/*
  Class hierarchy:
  TestRoot
   CXXBase
    NoCXXSub
     CXXSub

  This has two cxx-wielding classes, and a class in between without cxx.
*/


@interface CXXBase : SUPERCLASS {
    cxx1 baseIvar;
}
@end
@implementation CXXBase @end

@interface NoCXXSub : CXXBase {
    int nocxxIvar;
}
@end
@implementation NoCXXSub @end

@interface CXXSub : NoCXXSub {
    cxx2 subIvar;
}
@end
@implementation CXXSub @end


void test_single(void) 
{
    // Single allocation

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    testonthread(^{
        id o = [TestRoot new];
        testassert(ctors1 == 0  &&  dtors1 == 0  &&  
                   ctors2 == 0  &&  dtors2 == 0);
        testassert([o class] == [TestRoot class]);
        RELEASE_VAR(o);
    });
    testcollect();
    testassert(ctors1 == 0  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    testonthread(^{
        id o = [CXXBase new];
        testassert(ctors1 == 1  &&  dtors1 == 0  &&  
                   ctors2 == 0  &&  dtors2 == 0);
        testassert([o class] == [CXXBase class]);
        RELEASE_VAR(o);
    });
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    testonthread(^{
        id o = [NoCXXSub new];
        testassert(ctors1 == 1  &&  dtors1 == 0  &&  
                   ctors2 == 0  &&  dtors2 == 0);
        testassert([o class] == [NoCXXSub class]);
        RELEASE_VAR(o);
    });
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    testonthread(^{
        id o = [CXXSub new];
        testassert(ctors1 == 1  &&  dtors1 == 0  &&  
                   ctors2 == 1  &&  dtors2 == 0);
        testassert([o class] == [CXXSub class]);
        RELEASE_VAR(o);
    });
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 1  &&  dtors2 == 1);
}

void test_inplace(void) 
{
    __unsafe_unretained volatile id o;
    char o2[64];

    id (*objc_constructInstance_fn)(Class, void*) = (id(*)(Class, void*))dlsym(RTLD_DEFAULT, "objc_constructInstance");
    void (*objc_destructInstance_fn)(id) = (void(*)(id))dlsym(RTLD_DEFAULT, "objc_destructInstance");

    // In-place allocation

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    o = objc_constructInstance_fn([TestRoot class], o2);
    testassert(ctors1 == 0  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    testassert([o class] == [TestRoot class]);
    objc_destructInstance_fn(o), o = nil;
    testcollect();
    testassert(ctors1 == 0  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    o = objc_constructInstance_fn([CXXBase class], o2);
    testassert(ctors1 == 1  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    testassert([o class] == [CXXBase class]);
    objc_destructInstance_fn(o), o = nil;
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    o = objc_constructInstance_fn([NoCXXSub class], o2);
    testassert(ctors1 == 1  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    testassert([o class] == [NoCXXSub class]);
    objc_destructInstance_fn(o), o = nil;
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 0  &&  dtors2 == 0);

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    o = objc_constructInstance_fn([CXXSub class], o2);
    testassert(ctors1 == 1  &&  dtors1 == 0  &&  
               ctors2 == 1  &&  dtors2 == 0);
    testassert([o class] == [CXXSub class]);
    objc_destructInstance_fn(o), o = nil;
    testcollect();
    testassert(ctors1 == 1  &&  dtors1 == 1  &&  
               ctors2 == 1  &&  dtors2 == 1);
}


#if __has_feature(objc_arc) 

void test_batch(void) 
{
    // not converted to ARC yet
    return;
}

#else

// Like class_createInstances(), but refuses to accept zero allocations
static unsigned 
reallyCreateInstances(Class cls, size_t extraBytes, id *dst, unsigned want)
{
    unsigned count;
    while (0 == (count = class_createInstances(cls, extraBytes, dst, want))) {
        testprintf("class_createInstances created nothing; retrying\n");
        RELEASE_VALUE([[TestRoot alloc] init]);
    }
    return count;
}

void test_batch(void) 
{
    id o2[100];
    unsigned int count, i;

    // Batch allocation

    for (i = 0; i < 100; i++) {
        o2[i] = (id)malloc(class_getInstanceSize([TestRoot class]));
    }
    for (i = 0; i < 100; i++) {
        free(o2[i]);
    }

    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    count = reallyCreateInstances([TestRoot class], 0, o2, 10);
    testassert(count > 0);
    testassert(ctors1 == 0  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    for (i = 0; i < count; i++) testassert([o2[i] class] == [TestRoot class]);
    for (i = 0; i < count; i++) object_dispose(o2[i]), o2[i] = nil;
    testcollect();
    testassert(ctors1 == 0  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);

    for (i = 0; i < 100; i++) {
        // prime batch allocator
        free(malloc(class_getInstanceSize([TestRoot class])));
    }
    
    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    count = reallyCreateInstances([CXXBase class], 0, o2, 10);
    testassert(count > 0);
    testassert(ctors1 == count  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    for (i = 0; i < count; i++) testassert([o2[i] class] == [CXXBase class]);
    for (i = 0; i < count; i++) object_dispose(o2[i]), o2[i] = nil;
    testcollect();
    testassert(ctors1 == count  &&  dtors1 == count  &&  
               ctors2 == 0  &&  dtors2 == 0);

    for (i = 0; i < 100; i++) {
        // prime batch allocator
        free(malloc(class_getInstanceSize([TestRoot class])));
    }
    
    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    count = reallyCreateInstances([NoCXXSub class], 0, o2, 10);
    testassert(count > 0);
    testassert(ctors1 == count  &&  dtors1 == 0  &&  
               ctors2 == 0  &&  dtors2 == 0);
    for (i = 0; i < count; i++) testassert([o2[i] class] == [NoCXXSub class]);
    for (i = 0; i < count; i++) object_dispose(o2[i]), o2[i] = nil;
    testcollect();
    testassert(ctors1 == count  &&  dtors1 == count  &&  
               ctors2 == 0  &&  dtors2 == 0);

    for (i = 0; i < 100; i++) {
        // prime batch allocator
        free(malloc(class_getInstanceSize([TestRoot class])));
    }
    
    ctors1 = dtors1 = ctors2 = dtors2 = 0;
    count = reallyCreateInstances([CXXSub class], 0, o2, 10);
    testassert(count > 0);
    testassert(ctors1 == count  &&  dtors1 == 0  &&  
               ctors2 == count  &&  dtors2 == 0);
    for (i = 0; i < count; i++) testassert([o2[i] class] == [CXXSub class]);
    for (i = 0; i < count; i++) object_dispose(o2[i]), o2[i] = nil;
    testcollect();
    testassert(ctors1 == count  &&  dtors1 == count  &&  
               ctors2 == count  &&  dtors2 == count);
}

// not ARC
#endif


int main()
{
    if (objc_collectingEnabled()) {
        testwarn("rdar://19042235 test disabled in GC because it is slow");
        succeed(FILENAME);
    }

    for (int i = 0; i < 1000; i++) {
        testonthread(^{ test_single(); });
        testonthread(^{ test_inplace(); });
        testonthread(^{ test_batch(); });
    }

    testonthread(^{ test_single(); });
    testonthread(^{ test_inplace(); });
    testonthread(^{ test_batch(); });

    leak_mark();

    for (int i = 0; i < 1000; i++) {
        testonthread(^{ test_single(); });
        testonthread(^{ test_inplace(); });
        testonthread(^{ test_batch(); });
    }

    leak_check(0);

    // fixme ctor exceptions aren't caught inside .cxx_construct ?
    // Single allocation, ctors fail
    // In-place allocation, ctors fail
    // Batch allocation, ctors fail for every object
    // Batch allocation, ctors fail for every other object

    succeed(FILENAME);
}
