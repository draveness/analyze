// for OBJC2 mac only
/* TEST_CONFIG OS=macosx ARCH=x86_64
   TEST_CRASHES

TEST_RUN_OUTPUT
objc\[\d+\]: objc_removeExceptionHandler\(\) called with unknown alt handler; this is probably a bug in multithreaded AppKit use. Set environment variable OBJC_DEBUG_ALT_HANDLERS=YES or break in objc_alt_handler_error\(\) to debug.
CRASHED: SIGILL
END
*/

#include "test.h"

#include <objc/objc-exception.h>

/*
  rdar://6888838
  Mail installs an alt handler on one thread and deletes it on another.
  This confuses the alt handler machinery, which halts the process.
*/

uintptr_t Token;

void handler(id unused __unused, void *context __unused)
{
}

int main()
{
#if __clang__ && __cplusplus
    // alt handlers need the objc personality
    // catch (id) workaround forces the objc personality
    @try {
        testwarn("rdar://9183014 clang uses wrong exception personality");
    } @catch (id e __unused) {
    }
#endif

    @try {
        // Install 4 alt handlers
        uintptr_t t1, t2, t3, t4;
        t1 = objc_addExceptionHandler(&handler, NULL);
        t2 = objc_addExceptionHandler(&handler, NULL);
        t3 = objc_addExceptionHandler(&handler, NULL);
        t4 = objc_addExceptionHandler(&handler, NULL);

        // Remove 3 of them.
        objc_removeExceptionHandler(t1);
        objc_removeExceptionHandler(t2);
        objc_removeExceptionHandler(t3);
        
        // Create an alt handler on another thread 
        // that collides with one of the removed handlers
        testonthread(^{
            @try {
                Token = objc_addExceptionHandler(&handler, NULL);
            } @catch (...) {
            }
        });
        
        // Incorrectly remove the other thread's handler
        objc_removeExceptionHandler(Token);
        // Remove the 4th handler
        objc_removeExceptionHandler(t4);
        
        // Install 8 more handlers.
        // If the other thread's handler was not ignored, 
        // this will fail.
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
        objc_addExceptionHandler(&handler, NULL);
    } @catch (...) {
    }

    // This should have crashed earlier.
    fail(__FILE__);
}
