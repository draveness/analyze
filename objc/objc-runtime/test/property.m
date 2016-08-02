// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <stdint.h>
#include <string.h>
#include <objc/objc-runtime.h>

@interface Super : TestRoot { 
  @public
    char superIvar;
}

@property(readonly) char superProp;
@end

@implementation Super 
@synthesize superProp = superIvar;
@end


@interface Sub : Super {
  @public 
    uintptr_t subIvar;
}
@property(readonly) uintptr_t subProp;
@end

@implementation Sub 
@synthesize subProp = subIvar;
@end

 
int main()
{
    /* 
       Runtime layout of Sub:
         [0] isa
         [1] superIvar
         [2] subIvar
    */
    
    objc_property_t prop;

    prop = class_getProperty([Sub class], "subProp");
    testassert(prop);

    prop = class_getProperty([Super class], "superProp");
    testassert(prop);
    testassert(prop == class_getProperty([Sub class], "superProp"));

    prop = class_getProperty([Super class], "subProp");
    testassert(!prop);

    prop = class_getProperty(object_getClass([Sub class]), "subProp");
    testassert(!prop);


    testassert(NULL == class_getProperty(NULL, "foo"));
    testassert(NULL == class_getProperty([Sub class], NULL));
    testassert(NULL == class_getProperty(NULL, NULL));

    succeed(__FILE__);
    return 0;
}
