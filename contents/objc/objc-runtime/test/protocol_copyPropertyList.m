// TEST_CFLAGS -framework Foundation
// need Foundation to get NSObject compatibility additions for class Protocol
// because ARC calls [protocol retain]

#include "test.h"
#include <string.h>
#include <malloc/malloc.h>
#include <objc/runtime.h>

@protocol SuperProps
@property int prop1;
@property int prop2;
@end

@protocol SubProps <SuperProps>
@property int prop3;
@property int prop4;
@end


@protocol FourProps
@property int prop1;
@property int prop2;
@property int prop3;
@property int prop4;
@end

@protocol NoProps @end

static int isNamed(objc_property_t p, const char *name)
{
    return (0 == strcmp(name, property_getName(p)));
}

int main()
{
    objc_property_t *props;
    unsigned int count;
    Protocol *proto;

    proto = @protocol(SubProps);
    testassert(proto);

    count = 100;
    props = protocol_copyPropertyList(proto, &count);
    testassert(props);
    testassert(count == 2);
    testassert((isNamed(props[0], "prop4") && isNamed(props[1], "prop3"))  ||  
               (isNamed(props[0], "prop3") && isNamed(props[1], "prop4")));
    // props[] should be null-terminated
    testassert(props[2] == NULL);
    free(props);

    proto = @protocol(SuperProps);
    testassert(proto);

    count = 100;
    props = protocol_copyPropertyList(proto, &count);
    testassert(props);
    testassert(count == 2);
    testassert((isNamed(props[0], "prop1") && isNamed(props[1], "prop2"))  ||  
               (isNamed(props[0], "prop2") && isNamed(props[1], "prop1")));
    // props[] should be null-terminated
    testassert(props[2] == NULL);
    free(props);

    // Check null-termination - this property list block would be 16 bytes
    // if it weren't for the terminator
    proto = @protocol(FourProps);
    testassert(proto);

    count = 100;
    props = protocol_copyPropertyList(proto, &count);
    testassert(props);
    testassert(count == 4);
    testassert(malloc_size(props) >= 5 * sizeof(objc_property_t));
    testassert(props[3] != NULL);
    testassert(props[4] == NULL);
    free(props);

    // Check NULL count parameter
    props = protocol_copyPropertyList(proto, NULL);
    testassert(props);
    testassert(props[4] == NULL);
    testassert(props[3] != NULL);
    free(props);

    // Check NULL protocol parameter
    count = 100;
    props = protocol_copyPropertyList(NULL, &count);
    testassert(!props);
    testassert(count == 0);
    
    // Check NULL protocol and count
    props = protocol_copyPropertyList(NULL, NULL);
    testassert(!props);

    // Check protocol with no properties
    proto = @protocol(NoProps);
    testassert(proto);

    count = 100;
    props = protocol_copyPropertyList(proto, &count);
    testassert(!props);
    testassert(count == 0);

    succeed(__FILE__);
    return 0;
}
