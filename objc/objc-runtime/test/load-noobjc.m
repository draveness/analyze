/*
TEST_BUILD
    $C{COMPILE} $DIR/load-noobjc.m -o load-noobjc.out
    $C{COMPILE} $DIR/load-noobjc2.m -o libload-noobjc2.dylib -bundle -bundle_loader load-noobjc.out
    $C{COMPILE} $DIR/load-noobjc3.m -o libload-noobjc3.dylib -bundle -bundle_loader load-noobjc.out
END
*/

#include "test.h"

#if !__OBJC2__
// old runtime can't fix this deadlock

int main()
{
    succeed(__FILE__);
}

#else

#include <dlfcn.h>

int state = 0;
semaphore_t go;

void *thread(void *arg __unused)
{
    objc_registerThreadWithCollector();
    dlopen("libload-noobjc2.dylib", RTLD_LAZY);
    fail("dlopen should not have returned");
}

int main()
{
    semaphore_create(mach_task_self(), &go, SYNC_POLICY_FIFO, 0);

    pthread_t th;
    pthread_create(&th, nil, &thread, nil);

    // Wait for thread to stop in libload-noobjc2's +load method.
    semaphore_wait(go);

    // run nooobjc3's constructor function.
    // There's no objc code here so it shouldn't require the +load lock.
    void *dlh = dlopen("libload-noobjc3.dylib", RTLD_LAZY);
    testassert(dlh);
    testassert(state == 1);

    succeed(__FILE__);
}

#endif
