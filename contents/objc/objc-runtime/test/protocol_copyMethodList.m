// TEST_CFLAGS -framework Foundation
// need Foundation to get NSObject compatibility additions for class Protocol
// because ARC calls [protocol retain]


#include "test.h"
#include <malloc/malloc.h>
#include <objc/objc-runtime.h>

@protocol SuperMethods
+(void)SuperMethodClass;
+(void)SuperMethodClass2;
-(void)SuperMethodInstance;
-(void)SuperMethodInstance2;
@end

@protocol SubMethods
+(void)SubMethodClass;
+(void)SubMethodClass2;
-(void)SubMethodInstance;
-(void)SubMethodInstance2;
@end

@protocol SuperOptionalMethods
@optional
+(void)SuperOptMethodClass;
+(void)SuperOptMethodClass2;
-(void)SuperOptMethodInstance;
-(void)SuperOptMethodInstance2;
@end

@protocol SubOptionalMethods <SuperOptionalMethods>
@optional
+(void)SubOptMethodClass;
+(void)SubOptMethodClass2;
-(void)SubOptMethodInstance;
-(void)SubOptMethodInstance2; 
@end

@protocol NoMethods @end

static int isNamed(struct objc_method_description m, const char *name)
{
    return (m.name == sel_registerName(name));
}

int main()
{
    struct objc_method_description *methods;
    unsigned int count;
    Protocol *proto;

    proto = @protocol(SubMethods);
    testassert(proto);

    // Check required methods
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, YES, YES, &count);
    testassert(methods);
    testassert(count == 2);
    testassert((isNamed(methods[0], "SubMethodInstance")  &&  
                isNamed(methods[1], "SubMethodInstance2"))  
               ||
               (isNamed(methods[1], "SubMethodInstance")  &&  
                isNamed(methods[0], "SubMethodInstance2")));
    free(methods);

    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, YES, NO, &count);
    testassert(methods);
    testassert(count == 2);
    testassert((isNamed(methods[0], "SubMethodClass")  &&  
                isNamed(methods[1], "SubMethodClass2"))  
               ||
               (isNamed(methods[1], "SubMethodClass")  &&  
                isNamed(methods[0], "SubMethodClass2")));
    free(methods);

    // Check lack of optional methods
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, NO, YES, &count);
    testassert(!methods);
    testassert(count == 0);
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, NO, NO, &count);
    testassert(!methods);
    testassert(count == 0);


    proto = @protocol(SubOptionalMethods);
    testassert(proto);

    // Check optional methods
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, NO, YES, &count);
    testassert(methods);
    testassert(count == 2);
    testassert((isNamed(methods[0], "SubOptMethodInstance")  &&  
                isNamed(methods[1], "SubOptMethodInstance2"))  
               ||
               (isNamed(methods[1], "SubOptMethodInstance")  &&  
                isNamed(methods[0], "SubOptMethodInstance2")));
    free(methods);

    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, NO, NO, &count);
    testassert(methods);
    testassert(count == 2);
    testassert((isNamed(methods[0], "SubOptMethodClass")  &&  
                isNamed(methods[1], "SubOptMethodClass2"))  
               ||
               (isNamed(methods[1], "SubOptMethodClass")  &&  
                isNamed(methods[0], "SubOptMethodClass2")));
    free(methods);

    // Check lack of required methods
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, YES, YES, &count);
    testassert(!methods);
    testassert(count == 0);
    count = 999;
    methods = protocol_copyMethodDescriptionList(proto, YES, NO, &count);
    testassert(!methods);
    testassert(count == 0);


    // Check NULL protocol parameter
    count = 999;
    methods = protocol_copyMethodDescriptionList(NULL, YES, YES, &count);
    testassert(!methods);
    testassert(count == 0);
    count = 999;
    methods = protocol_copyMethodDescriptionList(NULL, YES, NO, &count);
    testassert(!methods);
    testassert(count == 0);
    count = 999;
    methods = protocol_copyMethodDescriptionList(NULL, NO, YES, &count);
    testassert(!methods);
    testassert(count == 0);
    count = 999;
    methods = protocol_copyMethodDescriptionList(NULL, NO, NO, &count);
    testassert(!methods);
    testassert(count == 0);

    succeed(__FILE__);
}
