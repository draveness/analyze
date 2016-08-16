// TEST_CONFIG MEM=mrc,gc
// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <objc/objc-auto.h>

static int state = 0;

OBJC_ROOT_CLASS
@interface Super { id isa; } @end
@implementation Super 
+(id)class { return self; }
+(void)initialize { } 

+(id)ordinary { state = 1; return self; } 
+(id)ordinary2 { testassert(0); } 
+(id)retain { state = 2; return self; } 
+(void)release { state = 3; } 
+(id)autorelease { state = 4; return self; } 
+(void)dealloc { state = 5; } 
+(uintptr_t)retainCount { state = 6; return 6; } 
@end

@interface Sub : Super @end
@implementation Sub @end

@interface Sub2 : Super @end
@implementation Sub2 @end

OBJC_ROOT_CLASS
@interface Empty { id isa; } @end
@implementation Empty
+(id)class { return self; }
+(void)initialize { }
@end

void *forward_handler(id obj, SEL _cmd) {
    testassert(obj == [Empty class]);
    testassert(_cmd == @selector(ordinary));
    state = 1;
    return nil;
}

@interface Empty (Unimplemented)
+(id)ordinary;
+(id)retain;
+(void)release;
+(id)autorelease;
+(void)dealloc;
+(uintptr_t)retainCount;
@end


#define getImp(sel)  \
    do { \
        sel##Method = class_getClassMethod(cls, @selector(sel)); \
        testassert(sel##Method); \
        testassert(@selector(sel) == method_getName(sel##Method)); \
        sel = method_getImplementation(sel##Method); \
    } while (0)


static IMP ordinary, ordinary2, retain, release, autorelease, dealloc, retainCount;
static Method ordinaryMethod, ordinary2Method, retainMethod, releaseMethod, autoreleaseMethod, deallocMethod, retainCountMethod;

void cycle(Class cls)
{
    id idVal;
    uintptr_t intVal;

#if defined(__i386__)
    if (objc_collectingEnabled()) {
        // i386 GC: all ignored selectors are identical
        testassert(@selector(retain) == @selector(release)      &&  
                   @selector(retain) == @selector(autorelease)  &&  
                   @selector(retain) == @selector(dealloc)      &&  
                   @selector(retain) == @selector(retainCount)  );
    }
    else 
#endif
    {
        // x86_64 GC or no GC: all ignored selectors are distinct
        testassert(@selector(retain) != @selector(release)      &&  
                   @selector(retain) != @selector(autorelease)  &&  
                   @selector(retain) != @selector(dealloc)      &&  
                   @selector(retain) != @selector(retainCount)  );
    }

    // no ignored selector matches a real selector
    testassert(@selector(ordinary) != @selector(retain)       &&  
               @selector(ordinary) != @selector(release)      &&  
               @selector(ordinary) != @selector(autorelease)  &&  
               @selector(ordinary) != @selector(dealloc)      &&  
               @selector(ordinary) != @selector(retainCount)  );

    getImp(ordinary);
    getImp(ordinary2);
    getImp(retain);
    getImp(release);
    getImp(autorelease);
    getImp(dealloc);
    getImp(retainCount);

    if (objc_collectingEnabled()) {
        // GC: all ignored selector IMPs are identical
        testassert(retain == release      &&  
                   retain == autorelease  &&  
                   retain == dealloc      &&  
                   retain == retainCount  );
    }
    else {
        // no GC: all ignored selector IMPs are distinct
        testassert(retain != release      &&  
                   retain != autorelease  &&  
                   retain != dealloc      &&  
                   retain != retainCount  );
    }

    // no ignored selector IMP matches a real selector IMP
    testassert(ordinary != retain       &&  
               ordinary != release      &&  
               ordinary != autorelease  &&  
               ordinary != dealloc      &&  
               ordinary != retainCount  );
    
    // Test calls via method_invoke

    idVal =         ((id(*)(id, Method))method_invoke)(cls, ordinaryMethod);
    testassert(state == 1);
    testassert(idVal == cls);

    state = 0;
    idVal =         ((id(*)(id, Method))method_invoke)(cls, retainMethod);
    testassert(state == (objc_collectingEnabled() ? 0 : 2));
    testassert(idVal == cls);

    (void)        ((void(*)(id, Method))method_invoke)(cls, releaseMethod);
    testassert(state == (objc_collectingEnabled() ? 0 : 3));

    idVal =         ((id(*)(id, Method))method_invoke)(cls, autoreleaseMethod);
    testassert(state == (objc_collectingEnabled() ? 0 : 4));
    testassert(idVal == cls);

    (void)        ((void(*)(id, Method))method_invoke)(cls, deallocMethod);
    testassert(state == (objc_collectingEnabled() ? 0 : 5));

    intVal = ((uintptr_t(*)(id, Method))method_invoke)(cls, retainCountMethod);
    testassert(state == (objc_collectingEnabled() ? 0 : 6));
    testassert(intVal == (objc_collectingEnabled() ? (uintptr_t)cls : 6));


    // Test calls via compiled objc_msgSend

    state = 0;
    idVal  = [cls ordinary];
    testassert(state == 1);
    testassert(idVal == cls);

    state = 0;
    idVal  = [cls retain];
    testassert(state == (objc_collectingEnabled() ? 0 : 2));
    testassert(idVal == cls);

    (void)   [cls release];
    testassert(state == (objc_collectingEnabled() ? 0 : 3));

    idVal  = [cls autorelease];
    testassert(state == (objc_collectingEnabled() ? 0 : 4));
    testassert(idVal == cls);

    (void)   [cls dealloc];
    testassert(state == (objc_collectingEnabled() ? 0 : 5));

    intVal = [cls retainCount];
    testassert(state == (objc_collectingEnabled() ? 0 : 6));
    testassert(intVal == (objc_collectingEnabled() ? (uintptr_t)cls : 6));

    // Test calls via handwritten objc_msgSend

    state = 0;
    idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(ordinary));
    testassert(state == 1);
    testassert(idVal == cls);

    state = 0;
    idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(retain));
    testassert(state == (objc_collectingEnabled() ? 0 : 2));
    testassert(idVal == cls);

    (void) ((void(*)(id,SEL))objc_msgSend)(cls, @selector(release));
    testassert(state == (objc_collectingEnabled() ? 0 : 3));

    idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(autorelease));
    testassert(state == (objc_collectingEnabled() ? 0 : 4));
    testassert(idVal == cls);

    (void) ((void(*)(id,SEL))objc_msgSend)(cls, @selector(dealloc));
    testassert(state == (objc_collectingEnabled() ? 0 : 5));

    intVal = ((uintptr_t(*)(id,SEL))objc_msgSend)(cls, @selector(retainCount));
    testassert(state == (objc_collectingEnabled() ? 0 : 6));
    testassert(intVal == (objc_collectingEnabled() ? (uintptr_t)cls : 6));
}

int main()
{
    Class cls;

    objc_setForwardHandler((void*)&forward_handler, nil);

    // Test selector API

    testassert(sel_registerName("retain") == @selector(retain));
    testassert(sel_getUid("retain") == @selector(retain));
#if defined(__i386__)
    if (objc_collectingEnabled()) {
        // only i386's GC currently remaps these
        testassert(0 == strcmp(sel_getName(@selector(retain)), "<ignored selector>"));
    } else 
#endif
    {
        testassert(0 == strcmp(sel_getName(@selector(retain)), "retain"));
    }
#if !__OBJC2__
    testassert(sel_isMapped(@selector(retain)));
#endif
    
    cls = [Sub class];
    testassert(cls);
    cycle(cls);

    cls = [Super class];
    testassert(cls);
    cycle(cls);

    if (objc_collectingEnabled()) {
        // rdar://6200570 Method manipulation shouldn't affect ignored methods.

        cls = [Super class];
        testassert(cls);
        cycle(cls);

        method_setImplementation(retainMethod, (IMP)1);
        method_setImplementation(releaseMethod, (IMP)1);
        method_setImplementation(autoreleaseMethod, (IMP)1);
        method_setImplementation(deallocMethod, (IMP)1);
        method_setImplementation(retainCountMethod, (IMP)1);
        cycle(cls);

        testassert(ordinary2 != retainCount);
        method_exchangeImplementations(retainMethod, autoreleaseMethod);
        method_exchangeImplementations(deallocMethod, releaseMethod);
        method_exchangeImplementations(retainCountMethod, ordinary2Method);
        cycle(cls);
        // ordinary2 exchanged with ignored method is now ignored too
        testassert(ordinary2 == retainCount);

        // replace == replace existing
        class_replaceMethod(cls, @selector(retain), (IMP)1, "");
        class_replaceMethod(cls, @selector(release), (IMP)1, "");
        class_replaceMethod(cls, @selector(autorelease), (IMP)1, "");
        class_replaceMethod(cls, @selector(dealloc), (IMP)1, "");
        class_replaceMethod(cls, @selector(retainCount), (IMP)1, "");
        cycle(cls);

        cls = [Sub class];
        testassert(cls);
        cycle(cls);

        // replace == add override
        class_replaceMethod(cls, @selector(retain), (IMP)1, "");
        class_replaceMethod(cls, @selector(release), (IMP)1, "");
        class_replaceMethod(cls, @selector(autorelease), (IMP)1, "");
        class_replaceMethod(cls, @selector(dealloc), (IMP)1, "");
        class_replaceMethod(cls, @selector(retainCount), (IMP)1, "");
        cycle(cls);

        cls = [Sub2 class];
        testassert(cls);
        cycle(cls);

        class_addMethod(cls, @selector(retain), (IMP)1, "");
        class_addMethod(cls, @selector(release), (IMP)1, "");
        class_addMethod(cls, @selector(autorelease), (IMP)1, "");
        class_addMethod(cls, @selector(dealloc), (IMP)1, "");
        class_addMethod(cls, @selector(retainCount), (IMP)1, "");
        cycle(cls);
    }

    // Test calls via objc_msgSend - ignored selectors are ignored 
    // under GC even if the class provides no implementation for them
    if (objc_collectingEnabled()) {
        Class cls;
        id idVal;
        uintptr_t intVal;

        cls = [Empty class];
        state = 0;

        idVal  = [Empty retain];
        testassert(state == 0);
        testassert(idVal == cls);

        (void)   [Empty release];
        testassert(state == 0);

        idVal  = [Empty autorelease];
        testassert(state == 0);
        testassert(idVal == cls);

        (void)   [Empty dealloc];
        testassert(state == 0);

        intVal = [Empty retainCount];
        testassert(state == 0);
        testassert(intVal == (uintptr_t)cls);

        idVal  = [Empty ordinary];
        testassert(state == 1);
        testassert(idVal == nil);

        state = 0;

        idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(retain));
        testassert(state == 0);
        testassert(idVal == cls);

        (void) ((void(*)(id,SEL))objc_msgSend)(cls, @selector(release));
        testassert(state == 0);

        idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(autorelease));
        testassert(state == 0);
        testassert(idVal == cls);

        (void) ((void(*)(id,SEL))objc_msgSend)(cls, @selector(dealloc));
        testassert(state == 0);

        intVal = ((uintptr_t(*)(id,SEL))objc_msgSend)(cls, @selector(retainCount));
        testassert(state == 0);
        testassert(intVal == (uintptr_t)cls);

        idVal  = ((id(*)(id,SEL))objc_msgSend)(cls, @selector(ordinary));
        testassert(state == 1);
        testassert(idVal == nil);
    }    

    succeed(__FILE__);
}
