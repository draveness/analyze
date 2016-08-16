// test.h 
// Common definitions for trivial test harness


#ifndef TEST_H
#define TEST_H

#include <stdio.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <libgen.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/param.h>
#include <malloc/malloc.h>
#include <mach/mach.h>
#include <mach/vm_param.h>
#include <mach/mach_time.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <objc/objc-abi.h>
#include <objc/objc-auto.h>
#include <objc/objc-internal.h>
#include <TargetConditionals.h>

#if TARGET_OS_EMBEDDED  ||  TARGET_IPHONE_SIMULATOR
static OBJC_INLINE malloc_zone_t *objc_collectableZone(void) { return nil; }
#endif


// Configuration macros

#if !__LP64__ || TARGET_OS_WIN32 || __OBJC_GC__ || TARGET_IPHONE_SIMULATOR
#   define SUPPORT_NONPOINTER_ISA 0
#elif __x86_64__
#   define SUPPORT_NONPOINTER_ISA 1
#elif __arm64__
#   define SUPPORT_NONPOINTER_ISA 1
#else
#   error unknown architecture
#endif


// Test output

static inline void succeed(const char *name)  __attribute__((noreturn));
static inline void succeed(const char *name)
{
    if (name) {
        char path[MAXPATHLEN+1];
        strcpy(path, name);        
        fprintf(stderr, "OK: %s\n", basename(path));
    } else {
        fprintf(stderr, "OK\n");
    }
    exit(0);
}

static inline void fail(const char *msg, ...)   __attribute__((noreturn));
static inline void fail(const char *msg, ...)
{
    if (msg) {
        char *msg2;
        asprintf(&msg2, "BAD: %s\n", msg);
        va_list v;
        va_start(v, msg);
        vfprintf(stderr, msg2, v);
        va_end(v);
        free(msg2);
    } else {
        fprintf(stderr, "BAD\n");
    }
    exit(1);
}

#define testassert(cond) \
    ((void) (((cond) != 0) ? (void)0 : __testassert(#cond, __FILE__, __LINE__)))
#define __testassert(cond, file, line) \
    (fail("failed assertion '%s' at %s:%u", cond, __FILE__, __LINE__))

/* time-sensitive assertion, disabled under valgrind */
#define timecheck(name, time, fast, slow)                                    \
    if (getenv("VALGRIND") && 0 != strcmp(getenv("VALGRIND"), "NO")) {  \
        /* valgrind; do nothing */                                      \
    } else if (time > slow) {                                           \
        fprintf(stderr, "SLOW: %s %llu, expected %llu..%llu\n",         \
                name, (uint64_t)(time), (uint64_t)(fast), (uint64_t)(slow)); \
    } else if (time < fast) {                                           \
        fprintf(stderr, "FAST: %s %llu, expected %llu..%llu\n",         \
                name, (uint64_t)(time), (uint64_t)(fast), (uint64_t)(slow)); \
    } else {                                                            \
        testprintf("time: %s %llu, expected %llu..%llu\n",              \
                   name, (uint64_t)(time), (uint64_t)(fast), (uint64_t)(slow)); \
    }


static inline void testprintf(const char *msg, ...)
{
    static int verbose = -1;
    if (verbose < 0) verbose = atoi(getenv("VERBOSE") ?: "0");

    // VERBOSE=1 prints test harness info only
    if (msg  &&  verbose >= 2) {
        char *msg2;
        asprintf(&msg2, "VERBOSE: %s", msg);
        va_list v;
        va_start(v, msg);
        vfprintf(stderr, msg2, v);
        va_end(v);
        free(msg2);
    }
}

// complain to output, but don't fail the test
// Use when warning that some test is being temporarily skipped 
// because of something like a compiler bug.
static inline void testwarn(const char *msg, ...)
{
    if (msg) {
        char *msg2;
        asprintf(&msg2, "WARN: %s\n", msg);
        va_list v;
        va_start(v, msg);
        vfprintf(stderr, msg2, v);
        va_end(v);
        free(msg2);
    }
}

static inline void testnoop() { }

// Run GC. This is a macro to reach as high in the stack as possible.
#ifndef OBJC_NO_GC

#   if __OBJC2__
#       define testexc() 
#   else
#       include <objc/objc-exception.h>
#       define testexc()                                                \
            do {                                                        \
                objc_exception_functions_t table = {0,0,0,0,0,0};       \
                objc_exception_get_functions(&table);                   \
                if (!table.throw_exc) {                                 \
                    table.throw_exc = (typeof(table.throw_exc))abort;   \
                    table.try_enter = (typeof(table.try_enter))testnoop; \
                    table.try_exit  = (typeof(table.try_exit))testnoop; \
                    table.extract   = (typeof(table.extract))abort;     \
                    table.match     = (typeof(table.match))abort;       \
                    objc_exception_set_functions(&table);               \
                }                                                       \
            } while (0)
#   endif

#   define testcollect()                                                \
        do {                                                            \
            if (objc_collectingEnabled()) {                             \
                testexc();                                              \
                objc_clear_stack(0);                                    \
                objc_collect(OBJC_COLLECT_IF_NEEDED|OBJC_WAIT_UNTIL_DONE); \
                objc_collect(OBJC_EXHAUSTIVE_COLLECTION|OBJC_WAIT_UNTIL_DONE);\
                objc_collect(OBJC_EXHAUSTIVE_COLLECTION|OBJC_WAIT_UNTIL_DONE);\
            }                                                           \
            _objc_flush_caches(NULL);                                   \
        } while (0)

#else

#   define testcollect()                        \
    do {                                        \
        _objc_flush_caches(NULL);               \
    } while (0)

#endif


// Synchronously run test code on another thread.
// This can help force GC to kill objects promptly, which some tests depend on.

// The block object is unsafe_unretained because we must not allow 
// ARC to retain them in non-Foundation tests
typedef void(^testblock_t)(void);
static __unsafe_unretained testblock_t testcodehack;
static inline void *_testthread(void *arg __unused)
{
    objc_registerThreadWithCollector();
    testcodehack();
    return NULL;
}
static inline void testonthread(__unsafe_unretained testblock_t code) 
{
    // GC crashes without Foundation because the block object classes 
    // are insufficiently initialized.
    if (objc_collectingEnabled()) {
        static bool foundationified = false;
        if (!foundationified) {
            dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
            foundationified = true;
        }
    }

    pthread_t th;
    testcodehack = code;  // force GC not-thread-local, avoid ARC void* casts
    pthread_create(&th, NULL, _testthread, NULL);
    pthread_join(th, NULL);
}

/* Make sure libobjc does not call global operator new. 
   Any test that DOES need to call global operator new must 
   `#define TEST_CALLS_OPERATOR_NEW` before including test.h.
 */
#if __cplusplus  &&  !defined(TEST_CALLS_OPERATOR_NEW)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winline-new-delete"
#import <new>
inline void* operator new(std::size_t) throw (std::bad_alloc) { fail("called global operator new"); }
inline void* operator new[](std::size_t) throw (std::bad_alloc) { fail("called global operator new[]"); }
inline void* operator new(std::size_t, const std::nothrow_t&) throw() { fail("called global operator new(nothrow)"); }
inline void* operator new[](std::size_t, const std::nothrow_t&) throw() { fail("called global operator new[](nothrow)"); }
inline void operator delete(void*) throw() { fail("called global operator delete"); }
inline void operator delete[](void*) throw() { fail("called global operator delete[]"); }
inline void operator delete(void*, const std::nothrow_t&) throw() { fail("called global operator delete(nothrow)"); }
inline void operator delete[](void*, const std::nothrow_t&) throw() { fail("called global operator delete[](nothrow)"); }
#pragma clang diagnostic pop
#endif


/* Leak checking
   Fails if total malloc memory in use at leak_check(n) 
   is more than n bytes above that at leak_mark().
*/

static inline void leak_recorder(task_t task __unused, void *ctx, unsigned type __unused, vm_range_t *ranges, unsigned count)
{
    size_t *inuse = (size_t *)ctx;
    while (count--) {
        *inuse += ranges[count].size;
    }
}

static inline size_t leak_inuse(void)
{
    size_t total = 0;
    vm_address_t *zones;
    unsigned count;
    malloc_get_all_zones(mach_task_self(), NULL, &zones, &count);
    for (unsigned i = 0; i < count; i++) {
        size_t inuse = 0;
        malloc_zone_t *zone = (malloc_zone_t *)zones[i];
        if (!zone->introspect || !zone->introspect->enumerator) continue;

        // skip DispatchContinuations because it sometimes claims to be 
        // using lots of memory that then goes away later
        if (0 == strcmp(zone->zone_name, "DispatchContinuations")) continue;

        zone->introspect->enumerator(mach_task_self(), &inuse, MALLOC_PTR_IN_USE_RANGE_TYPE, (vm_address_t)zone, NULL, leak_recorder);
        // fprintf(stderr, "%zu in use for zone %s\n", inuse, zone->zone_name);
        total += inuse;
    }

    return total;
}


static inline void leak_dump_heap(const char *msg)
{
    fprintf(stderr, "%s\n", msg);

    // Make `heap` write to stderr
    int outfd = dup(STDOUT_FILENO);
    dup2(STDERR_FILENO, STDOUT_FILENO);
    pid_t pid = getpid();
    char cmd[256];
    // environment variables reset for iOS simulator use
    sprintf(cmd, "DYLD_LIBRARY_PATH= DYLD_ROOT_PATH= /usr/bin/heap -addresses all %d", (int)pid);
 
    system(cmd);

    dup2(outfd, STDOUT_FILENO);
    close(outfd);
}

static size_t _leak_start;
static inline void leak_mark(void)
{
    testcollect();
    if (getenv("LEAK_HEAP")) {
        leak_dump_heap("HEAP AT leak_mark");
    }
    _leak_start = leak_inuse();
}

#define leak_check(n)                                                   \
    do {                                                                \
        const char *_check = getenv("LEAK_CHECK");                      \
        size_t inuse;                                                   \
        if (_check && 0 == strcmp(_check, "NO")) break;                 \
        testcollect();                                                  \
        if (getenv("LEAK_HEAP")) {                                      \
            leak_dump_heap("HEAP AT leak_check");                       \
        }                                                               \
        inuse = leak_inuse();                                           \
        if (inuse > _leak_start + n) {                                  \
            if (getenv("HANG_ON_LEAK")) {                               \
                printf("leaks %d\n", getpid());                         \
                while (1) sleep(1);                                     \
            }                                                           \
            fprintf(stderr, "BAD: %zu bytes leaked at %s:%u\n",         \
                 inuse - _leak_start, __FILE__, __LINE__);              \
        }                                                               \
    } while (0)

static inline bool is_guardmalloc(void)
{
    const char *env = getenv("GUARDMALLOC");
    return (env  &&  0 == strcmp(env, "YES"));
}


/* Memory management compatibility macros */

static id self_fn(id x) __attribute__((used));
static id self_fn(id x) { return x; }

#if __has_feature(objc_arc)
    // ARC
#   define RELEASE_VAR(x)            x = nil
#   define WEAK_STORE(dst, val)      (dst = (val))
#   define WEAK_LOAD(src)            (src)
#   define SUPER_DEALLOC() 
#   define RETAIN(x)                 (self_fn(x))
#   define RELEASE_VALUE(x)          ((void)self_fn(x))
#   define AUTORELEASE(x)            (self_fn(x))

#elif defined(__OBJC_GC__)
    // GC
#   define RELEASE_VAR(x)            x = nil
#   define WEAK_STORE(dst, val)      (dst = (val))
#   define WEAK_LOAD(src)            (src)
#   define SUPER_DEALLOC()           [super dealloc]
#   define RETAIN(x)                 [x self]
#   define RELEASE_VALUE(x)          (void)[x self]
#   define AUTORELEASE(x)            [x self]

#else
    // MRC
#   define RELEASE_VAR(x)            do { [x release]; x = nil; } while (0)
#   define WEAK_STORE(dst, val)      objc_storeWeak((id *)&dst, val)
#   define WEAK_LOAD(src)            objc_loadWeak((id *)&src)
#   define SUPER_DEALLOC()           [super dealloc]
#   define RETAIN(x)                 [x retain]
#   define RELEASE_VALUE(x)          [x release]
#   define AUTORELEASE(x)            [x autorelease]
#endif

/* gcc compatibility macros */
/* <rdar://problem/9412038> @autoreleasepool should generate objc_autoreleasePoolPush/Pop on 10.7/5.0 */
//#if !defined(__clang__)
#   define PUSH_POOL { void *pool = objc_autoreleasePoolPush();
#   define POP_POOL objc_autoreleasePoolPop(pool); }
//#else
//#   define PUSH_POOL @autoreleasepool
//#   define POP_POOL
//#endif

#if __OBJC__

/* General purpose root class */

OBJC_ROOT_CLASS
@interface TestRoot {
 @public
    Class isa;
}

+(void) load;
+(void) initialize;

-(id) self;
-(Class) class;
-(Class) superclass;

+(id) new;
+(id) alloc;
+(id) allocWithZone:(void*)zone;
-(id) copy;
-(id) mutableCopy;
-(id) init;
-(void) dealloc;
-(void) finalize;
@end
@interface TestRoot (RR)
-(id) retain;
-(oneway void) release;
-(id) autorelease;
-(unsigned long) retainCount;
-(id) copyWithZone:(void *)zone;
-(id) mutableCopyWithZone:(void*)zone;
@end

// incremented for each call of TestRoot's methods
extern int TestRootLoad;
extern int TestRootInitialize;
extern int TestRootAlloc;
extern int TestRootAllocWithZone;
extern int TestRootCopy;
extern int TestRootCopyWithZone;
extern int TestRootMutableCopy;
extern int TestRootMutableCopyWithZone;
extern int TestRootInit;
extern int TestRootDealloc;
extern int TestRootFinalize;
extern int TestRootRetain;
extern int TestRootRelease;
extern int TestRootAutorelease;
extern int TestRootRetainCount;
extern int TestRootTryRetain;
extern int TestRootIsDeallocating;
extern int TestRootPlusRetain;
extern int TestRootPlusRelease;
extern int TestRootPlusAutorelease;
extern int TestRootPlusRetainCount;

#endif


// Struct that does not return in registers on any architecture

struct stret {
    int a;
    int b;
    int c;
    int d;
    int e;
    int f;
    int g;
    int h;
    int i;
    int j;
};

static inline BOOL stret_equal(struct stret a, struct stret b)
{
    return (a.a == b.a  &&  
            a.b == b.b  &&  
            a.c == b.c  &&  
            a.d == b.d  &&  
            a.e == b.e  &&  
            a.f == b.f  &&  
            a.g == b.g  &&  
            a.h == b.h  &&  
            a.i == b.i  &&  
            a.j == b.j);
}

static struct stret STRET_RESULT __attribute__((used)) = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};


#if TARGET_IPHONE_SIMULATOR
// Force cwd to executable's directory during launch.
// sim used to do this but simctl does not.
#include <crt_externs.h>
 __attribute__((constructor)) 
static void hack_cwd(void)
{
    if (!getenv("HACKED_CWD")) {
        chdir(dirname((*_NSGetArgv())[0]));
        setenv("HACKED_CWD", "1", 1);
    }
}
#endif

#endif
