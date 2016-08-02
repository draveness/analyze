// TEST_CONFIG

#include "test.h"

#include <Foundation/NSObject.h>
#include <mach/mach.h>
#include <pthread.h>
#include <sys/time.h>
#include <objc/runtime.h>
#include <objc/objc-sync.h>

// Basic @synchronized tests.


#define WAIT_SEC 3

static id obj;
static semaphore_t go;
static semaphore_t stop;

void *thread(void *arg __unused)
{
    int err;

    objc_registerThreadWithCollector();

    // non-blocking sync_enter
    err = objc_sync_enter(obj);
    testassert(err == OBJC_SYNC_SUCCESS);

    semaphore_signal(go);
    // main thread: sync_exit of object locked on some other thread
    semaphore_wait(stop);
    
    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_SUCCESS);
    err = objc_sync_enter(obj);
    testassert(err == OBJC_SYNC_SUCCESS);

    semaphore_signal(go);
    // main thread: blocking sync_enter 
    testassert(WAIT_SEC/3*3 == WAIT_SEC);
    sleep(WAIT_SEC/3);
    // recursive enter while someone waits
    err = objc_sync_enter(obj);
    testassert(err == OBJC_SYNC_SUCCESS);
    sleep(WAIT_SEC/3);
    // recursive exit while someone waits
    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_SUCCESS);
    sleep(WAIT_SEC/3);
    // sync_exit while someone waits
    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_SUCCESS);
    
    return NULL;
}

int main()
{
    pthread_t th;
    int err;
    struct timeval start, end;

    obj = [[NSObject alloc] init];

    // sync_exit of never-locked object
    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_NOT_OWNING_THREAD_ERROR);

    semaphore_create(mach_task_self(), &go, 0, 0);
    semaphore_create(mach_task_self(), &stop, 0, 0);
    pthread_create(&th, NULL, &thread, NULL);
    semaphore_wait(go);

    // sync_exit of object locked on some other thread
    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_NOT_OWNING_THREAD_ERROR);

    semaphore_signal(stop);
    semaphore_wait(go);

    // blocking sync_enter
    gettimeofday(&start, NULL);
    err = objc_sync_enter(obj);
    gettimeofday(&end, NULL);
    testassert(err == OBJC_SYNC_SUCCESS);
    // should have waited more than WAIT_SEC but less than WAIT_SEC+1
    // fixme hack: sleep(1) is ending 500 usec too early on x86_64 buildbot
    // (rdar://6456975)
    testassert(end.tv_sec*1000000LL+end.tv_usec >= 
               start.tv_sec*1000000LL+start.tv_usec + WAIT_SEC*1000000LL
               - 3*500 /*hack*/);
    testassert(end.tv_sec*1000000LL+end.tv_usec < 
               start.tv_sec*1000000LL+start.tv_usec + (1+WAIT_SEC)*1000000LL);

    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_SUCCESS);

    err = objc_sync_exit(obj);
    testassert(err == OBJC_SYNC_NOT_OWNING_THREAD_ERROR);

    succeed(__FILE__);
}
