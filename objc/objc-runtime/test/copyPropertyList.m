// TEST_CONFIG

#include "test.h"
#include <string.h>
#include <malloc/malloc.h>
#include <objc/objc-runtime.h>

OBJC_ROOT_CLASS
@interface SuperProps { id isa; int prop1; int prop2; } 
@property int prop1;
@property int prop2;
@end
@implementation SuperProps 
@synthesize prop1;
@synthesize prop2;
@end

@interface SubProps : SuperProps { int prop3; int prop4; }
@property int prop3;
@property int prop4;
@end
@implementation SubProps 
@synthesize prop3;
@synthesize prop4;
@end

OBJC_ROOT_CLASS
@interface FourProps { int prop1; int prop2; int prop3; int prop4; }
@property int prop1;
@property int prop2;
@property int prop3;
@property int prop4;
@end
@implementation FourProps 
@synthesize prop1;
@synthesize prop2;
@synthesize prop3;
@synthesize prop4;
@end

OBJC_ROOT_CLASS
@interface NoProps @end
@implementation NoProps @end

static int isNamed(objc_property_t p, const char *name)
{
    return (0 == strcmp(name, property_getName(p)));
}

int main()
{
    objc_property_t *props;
    unsigned int count;
    Class cls;

    cls = objc_getClass("SubProps");
    testassert(cls);

    count = 100;
    props = class_copyPropertyList(cls, &count);
    testassert(props);
    testassert(count == 2);
    testassert((isNamed(props[0], "prop3")  &&  isNamed(props[1], "prop4"))  ||
               (isNamed(props[1], "prop3")  &&  isNamed(props[0], "prop4")));
    // props[] should be null-terminated
    testassert(props[2] == NULL);
    free(props);

    cls = objc_getClass("SuperProps");
    testassert(cls);

    count = 100;
    props = class_copyPropertyList(cls, &count);
    testassert(props);
    testassert(count == 2);
    testassert((isNamed(props[0], "prop1")  &&  isNamed(props[1], "prop2"))  ||
               (isNamed(props[1], "prop1")  &&  isNamed(props[0], "prop2")));
    // props[] should be null-terminated
    testassert(props[2] == NULL);
    free(props);

    // Check null-termination - this property list block would be 16 bytes
    // if it weren't for the terminator
    cls = objc_getClass("FourProps");
    testassert(cls);

    count = 100;
    props = class_copyPropertyList(cls, &count);
    testassert(props);
    testassert(count == 4);
    testassert(malloc_size(props) >= 5 * sizeof(objc_property_t));
    testassert(props[3] != NULL);
    testassert(props[4] == NULL);
    free(props);

    // Check NULL count parameter
    props = class_copyPropertyList(cls, NULL);
    testassert(props);
    testassert(props[4] == NULL);
    testassert(props[3] != NULL);
    free(props);

    // Check NULL class parameter
    count = 100;
    props = class_copyPropertyList(NULL, &count);
    testassert(!props);
    testassert(count == 0);
    
    // Check NULL class and count
    props = class_copyPropertyList(NULL, NULL);
    testassert(!props);

    // Check class with no properties
    cls = objc_getClass("NoProps");
    testassert(cls);

    count = 100;
    props = class_copyPropertyList(cls, &count);
    testassert(!props);
    testassert(count == 0);

    succeed(__FILE__);
    return 0;
}
