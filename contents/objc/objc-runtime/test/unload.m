// xpc leaks memory in dlopen(). Disable it.
// TEST_ENV XPC_SERVICES_UNAVAILABLE=1
/*
TEST_BUILD
    $C{COMPILE}   $DIR/unload4.m -o unload4.dylib -dynamiclib
    $C{COMPILE_C} $DIR/unload3.c -o unload3.dylib -dynamiclib
    $C{COMPILE}   $DIR/unload2.m -o unload2.bundle -bundle
    $C{COMPILE}   $DIR/unload.m -o unload.out
END
 */

#include "test.h"
#include <objc/runtime.h>
#include <dlfcn.h>
#include <unistd.h>

#include "unload.h"

#if __has_feature(objc_arc)

int main()
{
    testwarn("rdar://11368528 confused by Foundation");
    succeed(__FILE__);
}

#else

static id forward_handler(void)
{
    return 0;
}

static BOOL hasName(const char * const *names, const char *query)
{
    const char *name;
    while ((name = *names++)) {
        if (strstr(name, query)) return YES;
    }

    return NO;
}

void cycle(void)
{
    int i;
    char buf[100];
    unsigned int imageCount, imageCount0;
    const char **names;
    const char *name;

    names = objc_copyImageNames(&imageCount0);
    testassert(names);
    free(names);

    void *bundle = dlopen("unload2.bundle", RTLD_LAZY);
    testassert(bundle);

    names = objc_copyImageNames(&imageCount);
    testassert(names);
    testassert(imageCount == imageCount0 + 1);
    testassert(hasName(names, "unload2.bundle"));
    free(names);

    Class small = objc_getClass("SmallClass");
    Class big = objc_getClass("BigClass");
    testassert(small);
    testassert(big);

    name = class_getImageName(small);
    testassert(name);
    testassert(strstr(name, "unload2.bundle"));
    name = class_getImageName(big);
    testassert(name);
    testassert(strstr(name, "unload2.bundle"));

    id o1 = [small new];
    id o2 = [big new];
    testassert(o1);
    testassert(o2);
    
    // give BigClass and BigClass->isa large method caches (4692641)
    // Flush caches part way through to test large empty caches.
    for (i = 0; i < 3000; i++) {
        sprintf(buf, "method_%d", i);
        SEL sel = sel_registerName(buf);
        ((void(*)(id, SEL))objc_msgSend)(o2, sel);
        ((void(*)(id, SEL))objc_msgSend)(object_getClass(o2), sel);
    }
    _objc_flush_caches(object_getClass(o2));
    for (i = 0; i < 17000; i++) {
        sprintf(buf, "method_%d", i);
        SEL sel = sel_registerName(buf);
        ((void(*)(id, SEL))objc_msgSend)(o2, sel);
        ((void(*)(id, SEL))objc_msgSend)(object_getClass(o2), sel);
    }

    RELEASE_VAR(o1);
    RELEASE_VAR(o2);

    testcollect();

    int err = dlclose(bundle);
    testassert(err == 0);
    err = dlclose(bundle);
    testassert(err == -1);  // already closed
    
    testassert(objc_getClass("SmallClass") == NULL);
    testassert(objc_getClass("BigClass") == NULL);

    names = objc_copyImageNames(&imageCount);
    testassert(names);
    testassert(imageCount == imageCount0);
    testassert(! hasName(names, "unload2.bundle"));
    free(names);

    // these selectors came from the bundle
    testassert(0 == strcmp("unload2_instance_method", sel_getName(sel_registerName("unload2_instance_method"))));
    testassert(0 == strcmp("unload2_category_method", sel_getName(sel_registerName("unload2_category_method"))));

    // This protocol came from the bundle.
    // It isn't unloaded cleanly (rdar://20664713), but neither 
    // may it cause the protocol table to crash after unloading.
    testassert(objc_getProtocol("SmallProtocol"));
}


int main()
{
    // fixme object_dispose() not aggressive enough?
    if (objc_collectingEnabled()) succeed(__FILE__);

    objc_setForwardHandler((void*)&forward_handler, (void*)&forward_handler);

#if defined(__arm__)  ||  defined(__arm64__)
    int count = 10;
#else
    int count = is_guardmalloc() ? 10 : 100;
#endif
    
    cycle();
#if __LP64__
    // fixme heap use goes up 512 bytes after the 2nd cycle only - bad or not?
    cycle();
#endif

    leak_mark();
    while (count--) {
        cycle();
    }
    leak_check(0);

    // 5359412 Make sure dylibs with nothing other than image_info can close
    void *dylib = dlopen("unload3.dylib", RTLD_LAZY);
    testassert(dylib);
    int err = dlclose(dylib);
    testassert(err == 0);
    err = dlclose(dylib);
    testassert(err == -1);  // already closed

    // Make sure dylibs with real objc content cannot close
    dylib = dlopen("unload4.dylib", RTLD_LAZY);
    testassert(dylib);
    err = dlclose(dylib);
    testassert(err == 0);
    err = dlclose(dylib);
    testassert(err == 0);   // dlopen from libobjc itself
    err = dlclose(dylib);
    testassert(err == -1);  // already closed

    succeed(__FILE__);
}

#endif
