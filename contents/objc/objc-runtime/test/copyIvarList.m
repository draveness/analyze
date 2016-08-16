// TEST_CONFIG

#include "test.h"
#include <string.h>
#include <malloc/malloc.h>
#include <objc/objc-runtime.h>

OBJC_ROOT_CLASS
@interface SuperIvars { 
    id isa;
    int ivar1;
    int ivar2;
} @end
@implementation SuperIvars @end

@interface SubIvars : SuperIvars { 
    int ivar3;
    int ivar4;
} @end
@implementation SubIvars @end

OBJC_ROOT_CLASS
@interface FourIvars {
    int ivar1;
    int ivar2;
    int ivar3;
    int ivar4;
} @end
@implementation FourIvars @end

OBJC_ROOT_CLASS
@interface NoIvars { } @end
@implementation NoIvars @end

static int isNamed(Ivar iv, const char *name)
{
    return (0 == strcmp(name, ivar_getName(iv)));
}

int main()
{
    Ivar *ivars;
    unsigned int count;
    Class cls;

    cls = objc_getClass("SubIvars");
    testassert(cls);

    count = 100;
    ivars = class_copyIvarList(cls, &count);
    testassert(ivars);
    testassert(count == 2);
    testassert(isNamed(ivars[0], "ivar3"));
    testassert(isNamed(ivars[1], "ivar4"));
    // ivars[] should be null-terminated
    testassert(ivars[2] == NULL);
    free(ivars);

    cls = objc_getClass("SuperIvars");
    testassert(cls);

    count = 100;
    ivars = class_copyIvarList(cls, &count);
    testassert(ivars);
    testassert(count == 3);
    testassert(isNamed(ivars[0], "isa"));
    testassert(isNamed(ivars[1], "ivar1"));
    testassert(isNamed(ivars[2], "ivar2"));
    // ivars[] should be null-terminated
    testassert(ivars[3] == NULL);
    free(ivars);

    // Check null-termination - this ivar list block would be 16 bytes
    // if it weren't for the terminator
    cls = objc_getClass("FourIvars");
    testassert(cls);

    count = 100;
    ivars = class_copyIvarList(cls, &count);
    testassert(ivars);
    testassert(count == 4);
    testassert(malloc_size(ivars) >= 5 * sizeof(Ivar));
    testassert(ivars[3] != NULL);
    testassert(ivars[4] == NULL);
    free(ivars);

    // Check NULL count parameter
    ivars = class_copyIvarList(cls, NULL);
    testassert(ivars);
    testassert(ivars[4] == NULL);
    testassert(ivars[3] != NULL);
    free(ivars);

    // Check NULL class parameter
    count = 100;
    ivars = class_copyIvarList(NULL, &count);
    testassert(!ivars);
    testassert(count == 0);
    
    // Check NULL class and count
    ivars = class_copyIvarList(NULL, NULL);
    testassert(!ivars);

    // Check class with no ivars
    cls = objc_getClass("NoIvars");
    testassert(cls);

    count = 100;
    ivars = class_copyIvarList(cls, &count);
    testassert(!ivars);
    testassert(count == 0);

    succeed(__FILE__);
    return 0;
}
