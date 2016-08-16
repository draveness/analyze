// TEST_CONFIG

#include "test.h"

#include <stdlib.h>
#include <pthread.h>
#include <objc/runtime.h>
#include <objc/objc-sync.h>
#include <Foundation/NSObject.h>
#include <System/pthread_machdep.h>

// synchronized stress test
// Single locked counter incremented by many threads.

#if defined(__arm__)
#define THREADS 16
#define COUNT 1024*24
#else
// 64 / 1024*24 test takes about 20s on 4x2.6GHz Mac Pro
#define THREADS 64
#define COUNT 1024*24
#endif

static id lock;
static int count;

static void *threadfn(void *arg)
{
    int n, d;
    int depth = 1 + (int)(intptr_t)arg % 4;

    objc_registerThreadWithCollector();

    for (n = 0; n < COUNT; n++) {
        // Lock
        for (d = 0; d < depth; d++) {
            int err = objc_sync_enter(lock);
            testassert(err == OBJC_SYNC_SUCCESS);
        }
        
        // Increment
        count++;
        
        // Unlock
        for (d = 0; d < depth; d++) {
            int err = objc_sync_exit(lock);
            testassert(err == OBJC_SYNC_SUCCESS);
        }
    }

    // Verify lack of objc pthread data (should have used sync fast cache)
#ifdef __PTK_FRAMEWORK_OBJC_KEY0
    testassert(! pthread_getspecific(__PTK_FRAMEWORK_OBJC_KEY0));
#endif

    return NULL;
}

int main()
{
    pthread_t threads[THREADS];
    int t;
    int err;

    lock = [[NSObject alloc] init];

    // Verify objc pthread data on this thread (from +initialize)
    // Worker threads shouldn't have any because of sync fast cache.
#ifdef __PTK_FRAMEWORK_OBJC_KEY0
    testassert(pthread_getspecific(__PTK_FRAMEWORK_OBJC_KEY0));
#endif

    // Start the threads
    for (t = 0; t < THREADS; t++) {
        pthread_create(&threads[t], NULL, &threadfn, (void*)(intptr_t)t);
    }

    // Wait for threads to finish
    for (t = 0; t < THREADS; t++) {
        pthread_join(threads[t], NULL);
    }
    
    // Verify lock: should be available
    // Verify count: should be THREADS*COUNT
    err = objc_sync_enter(lock);
    testassert(err == OBJC_SYNC_SUCCESS);
    testassert(count == THREADS*COUNT);

    succeed(__FILE__);
}
