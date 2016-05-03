// TEST_CONFIG

#include "test.h"
#include <objc/runtime.h>
#include <objc/objc-internal.h>
#include <objc/objc-gdb.h>
#include <dlfcn.h>
#import <Foundation/NSObject.h>

#if OBJC_HAVE_TAGGED_POINTERS

#if !__OBJC2__  ||  (!__x86_64__  &&  !__arm64__)
#error wrong architecture for tagged pointers
#endif

static BOOL didIt;

@interface WeakContainer : NSObject
{
  @public
    __weak id weaks[10000];
}
@end
@implementation WeakContainer
-(void) dealloc {
    for (unsigned int i = 0; i < sizeof(weaks)/sizeof(weaks[0]); i++) {
        testassert(weaks[i] == nil);
    }
    SUPER_DEALLOC();
}
-(void) finalize {
    for (unsigned int i = 0; i < sizeof(weaks)/sizeof(weaks[0]); i++) {
        testassert(weaks[i] == nil);
    }
    [super finalize];
}
@end

OBJC_ROOT_CLASS
@interface TaggedBaseClass
@end

@implementation TaggedBaseClass
-(id) self { return self; }

+ (void) initialize {
}

- (void) instanceMethod {
    didIt = YES;
}

- (uintptr_t) taggedValue {
    return _objc_getTaggedPointerValue(objc_unretainedPointer(self));
}

- (struct stret) stret: (struct stret) aStruct {
    return aStruct;
}

- (long double) fpret: (long double) aValue {
    return aValue;
}


-(void) dealloc {
    fail("TaggedBaseClass dealloc called!");
}

static void *
retain_fn(void *self, SEL _cmd __unused) {
    void * (*fn)(void *) = (typeof(fn))_objc_rootRetain;
    return fn(self); 
}

static void 
release_fn(void *self, SEL _cmd __unused) {
    void (*fn)(void *) = (typeof(fn))_objc_rootRelease;
    fn(self); 
}

static void *
autorelease_fn(void *self, SEL _cmd __unused) { 
    void * (*fn)(void *) = (typeof(fn))_objc_rootAutorelease;
    return fn(self); 
}

static unsigned long 
retaincount_fn(void *self, SEL _cmd __unused) { 
    unsigned long (*fn)(void *) = (typeof(fn))_objc_rootRetainCount;
    return fn(self); 
}

+(void) load {
    class_addMethod(self, sel_registerName("retain"), (IMP)retain_fn, "");
    class_addMethod(self, sel_registerName("release"), (IMP)release_fn, "");
    class_addMethod(self, sel_registerName("autorelease"), (IMP)autorelease_fn, "");
    class_addMethod(self, sel_registerName("retainCount"), (IMP)retaincount_fn, "");    
}

@end

@interface TaggedSubclass: TaggedBaseClass
@end

@implementation TaggedSubclass

- (void) instanceMethod {
    return [super instanceMethod];
}

- (uintptr_t) taggedValue {
    return [super taggedValue];
}

- (struct stret) stret: (struct stret) aStruct {
    return [super stret: aStruct];
}

- (long double) fpret: (long double) aValue {
    return [super fpret: aValue];
}
@end

@interface TaggedNSObjectSubclass : NSObject
@end

@implementation TaggedNSObjectSubclass

- (void) instanceMethod {
    didIt = YES;
}

- (uintptr_t) taggedValue {
    return _objc_getTaggedPointerValue(objc_unretainedPointer(self));
}

- (struct stret) stret: (struct stret) aStruct {
    return aStruct;
}

- (long double) fpret: (long double) aValue {
    return aValue;
}
@end

void testTaggedPointerValue(Class cls, objc_tag_index_t tag, uintptr_t value)
{
    void *taggedAddress = _objc_makeTaggedPointer(tag, value);
    testprintf("obj %p, tag %p, value %p\n", 
               taggedAddress, (void*)tag, (void*)value);

    // _objc_makeTaggedPointer must quietly mask out of range values for now
    value = (value << 4) >> 4;

    testassert(_objc_isTaggedPointer(taggedAddress));
    testassert(_objc_getTaggedPointerTag(taggedAddress) == tag);
    testassert(_objc_getTaggedPointerValue(taggedAddress) == value);

    testassert((uintptr_t)taggedAddress & objc_debug_taggedpointer_mask);
    uintptr_t slot = ((uintptr_t)taggedAddress >> objc_debug_taggedpointer_slot_shift) & objc_debug_taggedpointer_slot_mask;
    testassert(objc_debug_taggedpointer_classes[slot] == cls);
    testassert((((uintptr_t)taggedAddress << objc_debug_taggedpointer_payload_lshift) >> objc_debug_taggedpointer_payload_rshift) == value);

    id taggedPointer = objc_unretainedObject(taggedAddress);
    testassert(!object_isClass(taggedPointer));
    testassert(object_getClass(taggedPointer) == cls);
    testassert([taggedPointer taggedValue] == value);

    didIt = NO;
    [taggedPointer instanceMethod];
    testassert(didIt);
    
    struct stret orig = STRET_RESULT;
    testassert(stret_equal(orig, [taggedPointer stret: orig]));
    
    long double dblvalue = 3.14156789;
    testassert(dblvalue == [taggedPointer fpret: dblvalue]);

    objc_setAssociatedObject(taggedPointer, (__bridge void *)taggedPointer, taggedPointer, OBJC_ASSOCIATION_RETAIN);
    testassert(objc_getAssociatedObject(taggedPointer, (__bridge void *)taggedPointer) == taggedPointer);
    objc_setAssociatedObject(taggedPointer, (__bridge void *)taggedPointer, nil, OBJC_ASSOCIATION_RETAIN);
    testassert(objc_getAssociatedObject(taggedPointer, (__bridge void *)taggedPointer) == nil);
}

void testGenericTaggedPointer(objc_tag_index_t tag, Class cls)
{
    testassert(cls);
    testprintf("%s\n", class_getName(cls));

    testTaggedPointerValue(cls, tag, 0);
    testTaggedPointerValue(cls, tag, 1UL << 0);
    testTaggedPointerValue(cls, tag, 1UL << 1);
    testTaggedPointerValue(cls, tag, 1UL << 58);
    testTaggedPointerValue(cls, tag, 1UL << 59);
    testTaggedPointerValue(cls, tag, ~0UL >> 4);
    testTaggedPointerValue(cls, tag, ~0UL);

    // Tagged pointers should bypass refcount tables and autorelease pools
    // and weak reference tables
    WeakContainer *w = [WeakContainer new];
#if !__has_feature(objc_arc)
    // prime method caches before leak checking
    id taggedPointer = (id)_objc_makeTaggedPointer(tag, 1234);
    [taggedPointer retain];
    [taggedPointer release];
    [taggedPointer autorelease];
#endif
    leak_mark();
    for (uintptr_t i = 0; i < sizeof(w->weaks)/sizeof(w->weaks[0]); i++) {
        id o = objc_unretainedObject(_objc_makeTaggedPointer(tag, i));
        testassert(object_getClass(o) == cls);
        
        id result = WEAK_STORE(w->weaks[i], o);
        testassert(result == o);
        testassert(w->weaks[i] == o);
        
        result = WEAK_LOAD(w->weaks[i]);
        testassert(result == o);
        
        if (!objc_collectingEnabled()) {
            uintptr_t rc = _objc_rootRetainCount(o);
            testassert(rc != 0);
            _objc_rootRelease(o);  testassert(_objc_rootRetainCount(o) == rc);
            _objc_rootRelease(o);  testassert(_objc_rootRetainCount(o) == rc);
            _objc_rootRetain(o);   testassert(_objc_rootRetainCount(o) == rc);
            _objc_rootRetain(o);   testassert(_objc_rootRetainCount(o) == rc);
            _objc_rootRetain(o);   testassert(_objc_rootRetainCount(o) == rc);
#if !__has_feature(objc_arc)
            [o release];  testassert(_objc_rootRetainCount(o) == rc);
            [o release];  testassert(_objc_rootRetainCount(o) == rc);
            [o retain];   testassert(_objc_rootRetainCount(o) == rc);
            [o retain];   testassert(_objc_rootRetainCount(o) == rc);
            [o retain];   testassert(_objc_rootRetainCount(o) == rc);
            objc_release(o);  testassert(_objc_rootRetainCount(o) == rc);
            objc_release(o);  testassert(_objc_rootRetainCount(o) == rc);
            objc_retain(o);   testassert(_objc_rootRetainCount(o) == rc);
            objc_retain(o);   testassert(_objc_rootRetainCount(o) == rc);
            objc_retain(o);   testassert(_objc_rootRetainCount(o) == rc);
#endif
            PUSH_POOL {
                testassert(_objc_rootRetainCount(o) == rc);
                _objc_rootAutorelease(o);
                testassert(_objc_rootRetainCount(o) == rc);
#if !__has_feature(objc_arc)
                [o autorelease];
                testassert(_objc_rootRetainCount(o) == rc);
                objc_autorelease(o);
                testassert(_objc_rootRetainCount(o) == rc);
                objc_retainAutorelease(o);
                testassert(_objc_rootRetainCount(o) == rc);
                objc_autoreleaseReturnValue(o);
                testassert(_objc_rootRetainCount(o) == rc);
                objc_retainAutoreleaseReturnValue(o);
                testassert(_objc_rootRetainCount(o) == rc);
                objc_retainAutoreleasedReturnValue(o);
                testassert(_objc_rootRetainCount(o) == rc);
#endif
            } POP_POOL;
            testassert(_objc_rootRetainCount(o) == rc);
        }
    }
    leak_check(0);
    for (uintptr_t i = 0; i < 10000; i++) {
        testassert(w->weaks[i] != NULL);
        WEAK_STORE(w->weaks[i], NULL);
        testassert(w->weaks[i] == NULL);
        testassert(WEAK_LOAD(w->weaks[i]) == NULL);
    }
    RELEASE_VAR(w);
}

int main()
{
    if (objc_collecting_enabled()) {
        // GC's block objects crash without this
        dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
    }

    testassert(objc_debug_taggedpointer_mask != 0);
    testassert(_objc_taggedPointersEnabled());

    PUSH_POOL {
        // Avoid CF's tagged pointer tags because of rdar://11368528

        _objc_registerTaggedPointerClass(OBJC_TAG_1, 
                                         objc_getClass("TaggedBaseClass"));
        testGenericTaggedPointer(OBJC_TAG_1, 
                                 objc_getClass("TaggedBaseClass"));
        
        _objc_registerTaggedPointerClass(OBJC_TAG_7, 
                                         objc_getClass("TaggedSubclass"));
        testGenericTaggedPointer(OBJC_TAG_7, 
                                 objc_getClass("TaggedSubclass"));
        
        _objc_registerTaggedPointerClass(OBJC_TAG_NSManagedObjectID, 
                                         objc_getClass("TaggedNSObjectSubclass"));
        testGenericTaggedPointer(OBJC_TAG_NSManagedObjectID, 
                                 objc_getClass("TaggedNSObjectSubclass"));
    } POP_POOL;

    succeed(__FILE__);
}

// OBJC_HAVE_TAGGED_POINTERS
#else
// not OBJC_HAVE_TAGGED_POINTERS

// Tagged pointers not supported.

int main() 
{
#if __OBJC2__
    testassert(objc_debug_taggedpointer_mask == 0);
#else
    testassert(!dlsym(RTLD_DEFAULT, "objc_debug_taggedpointer_mask"));
#endif

    succeed(__FILE__);
}

#endif
