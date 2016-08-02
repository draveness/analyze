// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"
#include "testroot.i"
#include <string.h>
#include <objc/objc-runtime.h>

@interface Super : TestRoot @end
@implementation Super 
+(id)method:(int)__unused arg :(void(^)(void)) __unused arg2 { 
    return 0;
}
@end


int main()
{
    char buf[128];
    char *arg;
    struct objc_method_description *desc;
    Method m = class_getClassMethod([Super class], sel_registerName("method::"));
    testassert(m);

    testassert(method_getNumberOfArguments(m) == 4);
#if !__OBJC2__
    testassert(method_getSizeOfArguments(m) == 16);
#endif

    arg = method_copyArgumentType(m, 0);
    testassert(arg);
    testassert(0 == strcmp(arg, "@"));
    memset(buf, 1, 128);
    method_getArgumentType(m, 0, buf, 1+strlen(arg));
    testassert(0 == strcmp(arg, buf));
    testassert(buf[1+strlen(arg)] == 1);
    memset(buf, 1, 128);
    method_getArgumentType(m, 0, buf, 2);
    testassert(0 == strncmp(arg, buf, 2));
    testassert(buf[2] == 1);
    free(arg);

    arg = method_copyArgumentType(m, 1);
    testassert(arg);
    testassert(0 == strcmp(arg, ":"));
    memset(buf, 1, 128);
    method_getArgumentType(m, 1, buf, 1+strlen(arg));
    testassert(0 == strcmp(arg, buf));
    testassert(buf[1+strlen(arg)] == 1);
    memset(buf, 1, 128);
    method_getArgumentType(m, 1, buf, 2);
    testassert(0 == strncmp(arg, buf, 2));
    testassert(buf[2] == 1);
    free(arg);

    arg = method_copyArgumentType(m, 2);
    testassert(arg);
    testassert(0 == strcmp(arg, "i"));
    memset(buf, 1, 128);
    method_getArgumentType(m, 2, buf, 1+strlen(arg));
    testassert(0 == strcmp(arg, buf));
    testassert(buf[1+strlen(arg)] == 1);
    memset(buf, 1, 128);
    method_getArgumentType(m, 2, buf, 2);
    testassert(0 == strncmp(arg, buf, 2));
    testassert(buf[2] == 1);
    free(arg);

    arg = method_copyArgumentType(m, 3);
    testassert(arg);
    testassert(0 == strcmp(arg, "@?"));
    memset(buf, 1, 128);
    method_getArgumentType(m, 3, buf, 1+strlen(arg));
    testassert(0 == strcmp(arg, buf));
    testassert(buf[1+strlen(arg)] == 1);
    memset(buf, 1, 128);
    method_getArgumentType(m, 3, buf, 2);
    testassert(0 == strncmp(arg, buf, 2));
    testassert(buf[2] == 1);
    memset(buf, 1, 128);
    method_getArgumentType(m, 3, buf, 3);
    testassert(0 == strncmp(arg, buf, 3));
    testassert(buf[3] == 1);
    free(arg);

    arg = method_copyArgumentType(m, 4);
    testassert(!arg);

    arg = method_copyArgumentType(m, -1);
    testassert(!arg);

    memset(buf, 1, 128);
    method_getArgumentType(m, 4, buf, 127);
    testassert(buf[0] == 0);
    testassert(buf[1] == 0);
    testassert(buf[127] == 1);

    memset(buf, 1, 128);
    method_getArgumentType(m, -1, buf, 127);
    testassert(buf[0] == 0);
    testassert(buf[1] == 0);
    testassert(buf[127] == 1);

    arg = method_copyReturnType(m);
    testassert(arg);
    testassert(0 == strcmp(arg, "@"));
    memset(buf, 1, 128);
    method_getReturnType(m, buf, 1+strlen(arg));
    testassert(0 == strcmp(arg, buf));
    testassert(buf[1+strlen(arg)] == 1);
    memset(buf, 1, 128);
    method_getReturnType(m, buf, 2);
    testassert(0 == strncmp(arg, buf, 2));
    testassert(buf[2] == 1);
    free(arg);

    desc = method_getDescription(m);
    testassert(desc);
    testassert(desc->name == sel_registerName("method::"));
#if __LP64__
    testassert(0 == strcmp(desc->types, "@28@0:8i16@?20"));
#else
    testassert(0 == strcmp(desc->types, "@16@0:4i8@?12"));
#endif

    testassert(0 == method_getNumberOfArguments(NULL));
#if !__OBJC2__
    testassert(0 == method_getSizeOfArguments(NULL));
#endif
    testassert(NULL == method_copyArgumentType(NULL, 10));
    testassert(NULL == method_copyReturnType(NULL));
    testassert(NULL == method_getDescription(NULL));

    memset(buf, 1, 128);
    method_getArgumentType(NULL, 1, buf, 127);
    testassert(buf[0] == 0);
    testassert(buf[1] == 0);
    testassert(buf[127] == 1);
    
    memset(buf, 1, 128);
    method_getArgumentType(NULL, 1, buf, 0);
    testassert(buf[0] == 1);
    testassert(buf[1] == 1);
    
    method_getArgumentType(m, 1, NULL, 128);
    method_getArgumentType(m, 1, NULL, 0);
    method_getArgumentType(NULL, 1, NULL, 128);
    method_getArgumentType(NULL, 1, NULL, 0);

    memset(buf, 1, 128);
    method_getReturnType(NULL, buf, 127);
    testassert(buf[0] == 0);
    testassert(buf[1] == 0);
    testassert(buf[127] == 1);
    
    memset(buf, 1, 128);
    method_getReturnType(NULL, buf, 0);
    testassert(buf[0] == 1);
    testassert(buf[1] == 1);
    
    method_getReturnType(m, NULL, 128);
    method_getReturnType(m, NULL, 0);
    method_getReturnType(NULL, NULL, 128);
    method_getReturnType(NULL, NULL, 0);

    succeed(__FILE__);
}
