// TEST_CONFIG CC=clang MEM=mrc
// TEST_CFLAGS -Os

#include "test.h"
#include "testroot.i"

#if __i386__

int main()
{
    // no optimization on i386 (neither Mac nor Simulator)
    succeed(__FILE__);
}

#else

#include <objc/objc-internal.h>
#include <objc/objc-abi.h>
#include <Foundation/Foundation.h>

@interface TestObject : TestRoot @end
@implementation TestObject @end


#ifdef __arm__
#   define MAGIC      asm volatile("mov r7, r7")
#   define NOT_MAGIC  asm volatile("mov r6, r6")
#elif __arm64__
#   define MAGIC      asm volatile("mov x29, x29")
#   define NOT_MAGIC  asm volatile("mov x28, x28")
#elif __x86_64__
#   define MAGIC      asm volatile("")
#   define NOT_MAGIC  asm volatile("nop")
#else
#   error unknown architecture
#endif


int
main()
{
    TestObject *tmp, *obj;
    
#ifdef __x86_64__
    // need to get DYLD to resolve the stubs on x86
    PUSH_POOL {
        TestObject *warm_up = [[TestObject alloc] init];
        testassert(warm_up);
        warm_up = objc_retainAutoreleasedReturnValue(warm_up);
        warm_up = objc_unsafeClaimAutoreleasedReturnValue(warm_up);
        [warm_up release];
        warm_up = nil;
    } POP_POOL;
#endif
    
    testprintf("  Successful +1 -> +1 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_autoreleaseReturnValue(obj);
        MAGIC;
        tmp = objc_retainAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 0);
        
        [tmp release];
        testassert(TestRootDealloc == 1);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 0);

    } POP_POOL;
    
    testprintf("Unsuccessful +1 -> +1 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_autoreleaseReturnValue(obj);
        NOT_MAGIC;
        tmp = objc_retainAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 1);
        
        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 1);

    } POP_POOL;
    testassert(TestRootDealloc == 1);
    testassert(TestRootRetain == 1);
    testassert(TestRootRelease == 2);
    testassert(TestRootAutorelease == 1);


    testprintf("  Successful +0 -> +1 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_retainAutoreleaseReturnValue(obj);
        MAGIC;
        tmp = objc_retainAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 0);
        
        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 0);

        [tmp release];
        testassert(TestRootDealloc == 1);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 2);
        testassert(TestRootAutorelease == 0);

    } POP_POOL;
    
    testprintf("Unsuccessful +0 -> +1 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_retainAutoreleaseReturnValue(obj);
        NOT_MAGIC;
        tmp = objc_retainAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 2);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 1);
        
        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 2);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 1);

        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 2);
        testassert(TestRootRelease == 2);
        testassert(TestRootAutorelease == 1);

    } POP_POOL;
    testassert(TestRootDealloc == 1);
    testassert(TestRootRetain == 2);
    testassert(TestRootRelease == 3);
    testassert(TestRootAutorelease == 1);


    testprintf("  Successful +1 -> +0 handshake\n");
    
    PUSH_POOL {
        obj = [[[TestObject alloc] init] retain];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_autoreleaseReturnValue(obj);
        MAGIC;
        tmp = objc_unsafeClaimAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 0);
        
        [tmp release];
        testassert(TestRootDealloc == 1);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 2);
        testassert(TestRootAutorelease == 0);

    } POP_POOL;

    testprintf("Unsuccessful +1 -> +0 handshake\n");
    
    PUSH_POOL {
        obj = [[[TestObject alloc] init] retain];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_autoreleaseReturnValue(obj);
        NOT_MAGIC;
        tmp = objc_unsafeClaimAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 1);
        
        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 1);

    } POP_POOL;
    testassert(TestRootDealloc == 1);
    testassert(TestRootRetain == 0);
    testassert(TestRootRelease == 2);
    testassert(TestRootAutorelease == 1);

    
    testprintf("  Successful +0 -> +0 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_retainAutoreleaseReturnValue(obj);
        MAGIC;
        tmp = objc_unsafeClaimAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 0);
        
        [tmp release];
        testassert(TestRootDealloc == 1);
        testassert(TestRootRetain == 0);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 0);

    } POP_POOL;

    testprintf("Unsuccessful +0 -> +0 handshake\n");
    
    PUSH_POOL {
        obj = [[TestObject alloc] init];
        testassert(obj);
        
        TestRootRetain = 0;
        TestRootRelease = 0;
        TestRootAutorelease = 0;
        TestRootDealloc = 0;

        tmp = objc_retainAutoreleaseReturnValue(obj);
        NOT_MAGIC;
        tmp = objc_unsafeClaimAutoreleasedReturnValue(tmp);

        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 0);
        testassert(TestRootAutorelease == 1);
        
        [tmp release];
        testassert(TestRootDealloc == 0);
        testassert(TestRootRetain == 1);
        testassert(TestRootRelease == 1);
        testassert(TestRootAutorelease == 1);

    } POP_POOL;
    testassert(TestRootDealloc == 1);
    testassert(TestRootRetain == 1);
    testassert(TestRootRelease == 2);
    testassert(TestRootAutorelease == 1);

    succeed(__FILE__);
    
    return 0;
}


#endif
