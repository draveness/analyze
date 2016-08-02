// TEST_CONFIG

#include "test.h"

#include <stdlib.h>
#include <pthread.h>
#include <objc/runtime.h>
#include <objc/objc-sync.h>
#include <Foundation/NSObject.h>

// synchronized stress test
// 2-D grid of counters and locks. 
// Each thread increments all counters some number of times.
// To increment:
// * thread picks a target [row][col]
// * thread locks all locks [row][0] to [row][col], possibly recursively
// * thread increments counter [row][col]
// * thread unlocks all of the locks

#if defined(__arm__)
// 16 / 4 / 3 / 1024*8 test takes about 30s on 2nd gen iPod touch
#define THREADS 16
#define ROWS 4
#define COLS 3
#define COUNT 1024*8
#else
// 64 / 4 / 3 / 1024*8 test takes about 20s on 4x2.6GHz Mac Pro
#define THREADS 64
#define ROWS 4
#define COLS 3
#define COUNT 1024*8
#endif

static id locks[ROWS][COLS];
static int counts[ROWS][COLS];


static void *threadfn(void *arg)
{
    int n, d;
    int depth = 1 + (int)(intptr_t)arg % 4;

    objc_registerThreadWithCollector();

    for (n = 0; n < COUNT; n++) {
        int rrr = rand() % ROWS;
        int ccc = rand() % COLS;
        int rr, cc;
        for (rr = 0; rr < ROWS; rr++) {
            int r = (rrr+rr) % ROWS;
            for (cc = 0; cc < COLS; cc++) {
                int c = (ccc+cc) % COLS;
                int l;

                // Lock [r][0..c]
                // ... in that order to prevent deadlock
                for (l = 0; l <= c; l++) {
                    for (d = 0; d < depth; d++) {
                        int err = objc_sync_enter(locks[r][l]);
                        testassert(err == OBJC_SYNC_SUCCESS);
                    }
                }
                
                // Increment count [r][c]
                counts[r][c]++;
                
                // Unlock [r][0..c]
                // ... in that order to increase contention
                for (l = 0; l <= c; l++) {
                    for (d = 0; d < depth; d++) {
                        int err = objc_sync_exit(locks[r][l]);
                        testassert(err == OBJC_SYNC_SUCCESS);
                    }
                }
            }
        }
    }
    
    return NULL;
}

int main()
{
    pthread_t threads[THREADS];
    int r, c, t;

    for (r = 0; r < ROWS; r++) {
        for (c = 0; c < COLS; c++) {
            locks[r][c] = [[NSObject alloc] init];
        }
    }

    // Start the threads
    for (t = 0; t < THREADS; t++) {
        pthread_create(&threads[t], NULL, &threadfn, (void*)(intptr_t)t);
    }

    // Wait for threads to finish
    for (t = 0; t < THREADS; t++) {
        pthread_join(threads[t], NULL);
    }
    
    // Verify locks: all should be available
    // Verify counts: all should be THREADS*COUNT
    for (r = 0; r < ROWS; r++) {
        for (c = 0; c < COLS; c++) {
            int err = objc_sync_enter(locks[r][c]);
            testassert(err == OBJC_SYNC_SUCCESS);
            testassert(counts[r][c] == THREADS*COUNT);
        }
    }

    succeed(__FILE__);
}
