// testroot.i
// Implementation of class TestRoot
// Include this file into your main test file to use it.

#include "test.h"
#include <dlfcn.h>
#include <objc/objc-internal.h>

int TestRootLoad = 0;
int TestRootInitialize = 0;
int TestRootAlloc = 0;
int TestRootAllocWithZone = 0;
int TestRootCopy = 0;
int TestRootCopyWithZone = 0;
int TestRootMutableCopy = 0;
int TestRootMutableCopyWithZone = 0;
int TestRootInit = 0;
int TestRootDealloc = 0;
int TestRootFinalize = 0;
int TestRootRetain = 0;
int TestRootRelease = 0;
int TestRootAutorelease = 0;
int TestRootRetainCount = 0;
int TestRootTryRetain = 0;
int TestRootIsDeallocating = 0;
int TestRootPlusRetain = 0;
int TestRootPlusRelease = 0;
int TestRootPlusAutorelease = 0;
int TestRootPlusRetainCount = 0;


@implementation TestRoot

// These all use void* pending rdar://9310005.

static void *
retain_fn(void *self, SEL _cmd __unused) {
    OSAtomicIncrement32(&TestRootRetain);
    void * (*fn)(void *) = (typeof(fn))_objc_rootRetain;
    return fn(self); 
}

static void 
release_fn(void *self, SEL _cmd __unused) {
    OSAtomicIncrement32(&TestRootRelease);
    void (*fn)(void *) = (typeof(fn))_objc_rootRelease;
    fn(self); 
}

static void *
autorelease_fn(void *self, SEL _cmd __unused) { 
    OSAtomicIncrement32(&TestRootAutorelease);
    void * (*fn)(void *) = (typeof(fn))_objc_rootAutorelease;
    return fn(self); 
}

static unsigned long 
retaincount_fn(void *self, SEL _cmd __unused) { 
    OSAtomicIncrement32(&TestRootRetainCount);
    unsigned long (*fn)(void *) = (typeof(fn))_objc_rootRetainCount;
    return fn(self); 
}

static void *
copywithzone_fn(void *self, SEL _cmd __unused, void *zone) { 
    OSAtomicIncrement32(&TestRootCopyWithZone);
    void * (*fn)(void *, void *) = (typeof(fn))dlsym(RTLD_DEFAULT, "object_copy");
    return fn(self, zone); 
}

static void *
plusretain_fn(void *self __unused, SEL _cmd __unused) {
    OSAtomicIncrement32(&TestRootPlusRetain);
    return self;
}

static void 
plusrelease_fn(void *self __unused, SEL _cmd __unused) {
    OSAtomicIncrement32(&TestRootPlusRelease);
}

static void * 
plusautorelease_fn(void *self, SEL _cmd __unused) { 
    OSAtomicIncrement32(&TestRootPlusAutorelease);
    return self;
}

static unsigned long 
plusretaincount_fn(void *self __unused, SEL _cmd __unused) { 
    OSAtomicIncrement32(&TestRootPlusRetainCount);
    return ULONG_MAX;
}

+(void) load {
    OSAtomicIncrement32(&TestRootLoad);
    
    // install methods that ARR refuses to compile
    class_addMethod(self, sel_registerName("retain"), (IMP)retain_fn, "");
    class_addMethod(self, sel_registerName("release"), (IMP)release_fn, "");
    class_addMethod(self, sel_registerName("autorelease"), (IMP)autorelease_fn, "");
    class_addMethod(self, sel_registerName("retainCount"), (IMP)retaincount_fn, "");
    class_addMethod(self, sel_registerName("copyWithZone:"), (IMP)copywithzone_fn, "");

    class_addMethod(object_getClass(self), sel_registerName("retain"), (IMP)plusretain_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("release"), (IMP)plusrelease_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("autorelease"), (IMP)plusautorelease_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("retainCount"), (IMP)plusretaincount_fn, "");
}


+(void) initialize {
    OSAtomicIncrement32(&TestRootInitialize);
}

-(id) self {
    return self;
}

+(Class) class {
    return self;
}

-(Class) class {
    return object_getClass(self);
}

+(Class) superclass {
    return class_getSuperclass(self);
}

-(Class) superclass {
    return class_getSuperclass([self class]);
}

+(id) new {
    return [[self alloc] init];
}

+(id) alloc {
    OSAtomicIncrement32(&TestRootAlloc);
    void * (*fn)(id __unsafe_unretained) = (typeof(fn))_objc_rootAlloc;
    return objc_retainedObject(fn(self));
}

+(id) allocWithZone:(void *)zone {
    OSAtomicIncrement32(&TestRootAllocWithZone);
    void * (*fn)(id __unsafe_unretained, void *) = (typeof(fn))_objc_rootAllocWithZone;
    return objc_retainedObject(fn(self, zone));
}

+(id) copy {
    return self;
}

+(id) copyWithZone:(void *) __unused zone {
    return self;
}

-(id) copy {
    OSAtomicIncrement32(&TestRootCopy);
    return [self copyWithZone:NULL];
}

+(id) mutableCopyWithZone:(void *) __unused zone {
    fail("+mutableCopyWithZone: called");
}

-(id) mutableCopy {
    OSAtomicIncrement32(&TestRootMutableCopy);
    return [self mutableCopyWithZone:NULL];
}

-(id) mutableCopyWithZone:(void *) __unused zone {
    OSAtomicIncrement32(&TestRootMutableCopyWithZone);
    void * (*fn)(id __unsafe_unretained) = (typeof(fn))_objc_rootAlloc;
    return objc_retainedObject(fn(object_getClass(self)));
}

-(id) init {
    OSAtomicIncrement32(&TestRootInit);
    return _objc_rootInit(self);
}

+(void) dealloc {
    fail("+dealloc called");
}

-(void) dealloc {
    OSAtomicIncrement32(&TestRootDealloc);
    _objc_rootDealloc(self);
}

+(void) finalize {
    fail("+finalize called");
}

-(void) finalize {
    OSAtomicIncrement32(&TestRootFinalize);
    _objc_rootFinalize(self);
}

+(BOOL) _tryRetain {
    return YES;
}

-(BOOL) _tryRetain {
    OSAtomicIncrement32(&TestRootTryRetain);
    return _objc_rootTryRetain(self);
}

+(BOOL) _isDeallocating {
    return NO;
}

-(BOOL) _isDeallocating {
    OSAtomicIncrement32(&TestRootIsDeallocating);
    return _objc_rootIsDeallocating(self);
}

-(BOOL) allowsWeakReference {
    return ! [self _isDeallocating]; 
}

-(BOOL) retainWeakReference { 
    return [self _tryRetain]; 
}


@end
