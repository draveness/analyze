// See instructions in weak.h

#include "test.h"
#include "weak.h"
#include <objc/objc-internal.h>

int state = 0;

static void *noop_fn(void *self, SEL _cmd __unused) {
    return self;
}
static void *retain_fn(void *self, SEL _cmd __unused) { 
    void * (*fn)(void *) = (typeof(fn))_objc_rootRetain;
    return fn(self); 
}
static void release_fn(void *self, SEL _cmd __unused) { 
    void (*fn)(void *) = (typeof(fn))_objc_rootRelease;
    fn(self); 
}
static void *autorelease_fn(void *self, SEL _cmd __unused) { 
    void * (*fn)(void *) = (typeof(fn))_objc_rootAutorelease;
    return fn(self); 
}

#if !defined(EMPTY)

@implementation MissingRoot
+(void) initialize { } 
+(Class) class { return self; }
+(id) alloc { return _objc_rootAlloc(self); }
+(id) allocWithZone:(void*)zone { return _objc_rootAllocWithZone(self, (malloc_zone_t *)zone); }
-(id) init { return self; }
-(void) dealloc { _objc_rootDealloc(self); }
+(int) method { return 10; }
+(void) load { 
    class_addMethod(self, sel_registerName("retain"), (IMP)retain_fn, "");
    class_addMethod(self, sel_registerName("release"), (IMP)release_fn, "");
    class_addMethod(self, sel_registerName("autorelease"), (IMP)autorelease_fn, "");

    class_addMethod(object_getClass(self), sel_registerName("retain"), (IMP)noop_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("release"), (IMP)noop_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("autorelease"), (IMP)noop_fn, "");

    state++; 
}
@end

@implementation MissingSuper
+(int) method { return 1+[super method]; }
-(id) init { self = [super init]; ivar = 100; return self; }
+(void) load { state++; }
@end

#endif

@implementation NotMissingRoot
+(void) initialize { } 
+(Class) class { return self; }
+(id) alloc { return _objc_rootAlloc(self); }
+(id) allocWithZone:(void*)zone { return _objc_rootAllocWithZone(self, (malloc_zone_t *)zone); }
-(id) init { return self; }
-(void) dealloc { _objc_rootDealloc(self); }
+(int) method { return 20; }
+(void) load { 
    class_addMethod(self, sel_registerName("retain"), (IMP)retain_fn, "");
    class_addMethod(self, sel_registerName("release"), (IMP)release_fn, "");
    class_addMethod(self, sel_registerName("autorelease"), (IMP)autorelease_fn, "");

    class_addMethod(object_getClass(self), sel_registerName("retain"), (IMP)noop_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("release"), (IMP)noop_fn, "");
    class_addMethod(object_getClass(self), sel_registerName("autorelease"), (IMP)noop_fn, "");

    state++; 
}
@end

@implementation NotMissingSuper
+(int) method { return 1+[super method]; }
-(id) init { self = [super init]; ivar = 200; return self; }
+(void) load { state++; }
@end

