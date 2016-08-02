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
@end

@interface Sub : Super {
  @public 
    id subIvar;
}
@end

@implementation Super @end
@implementation Sub @end

 
int main()
{
    /* 
       Runtime layout of Sub:
         [0] isa
         [1] superIvar
         [2] subIvar
    */
    
    Ivar ivar;
    Sub *sub = [Sub new];
    sub->subIvar = [Sub class];
    testassert(((Class *)objc_unretainedPointer(sub))[2] == [Sub class]);

    ivar = class_getInstanceVariable([Sub class], "subIvar");
    testassert(ivar);
    testassert(2*sizeof(intptr_t) == (size_t)ivar_getOffset(ivar));
    testassert(0 == strcmp(ivar_getName(ivar), "subIvar"));
    testassert(0 == strcmp(ivar_getTypeEncoding(ivar), "@"));

    ivar = class_getInstanceVariable([Super class], "superIvar");
    testassert(ivar);
    testassert(sizeof(intptr_t) == (size_t)ivar_getOffset(ivar));
    testassert(0 == strcmp(ivar_getName(ivar), "superIvar"));
    testassert(0 == strcmp(ivar_getTypeEncoding(ivar), "c"));
    testassert(ivar == class_getInstanceVariable([Sub class], "superIvar"));

    ivar = class_getInstanceVariable([Super class], "subIvar");
    testassert(!ivar);

    ivar = class_getInstanceVariable(object_getClass([Sub class]), "subIvar");
    testassert(!ivar);

    ivar = class_getInstanceVariable([Sub class], "subIvar");
    object_setIvar(sub, ivar, sub);
    testassert(sub->subIvar == sub);
    testassert(sub == object_getIvar(sub, ivar));

    testassert(NULL == class_getInstanceVariable(NULL, "foo"));
    testassert(NULL == class_getInstanceVariable([Sub class], NULL));
    testassert(NULL == class_getInstanceVariable(NULL, NULL));

    testassert(NULL == object_getIvar(sub, NULL));
    testassert(NULL == object_getIvar(NULL, ivar));
    testassert(NULL == object_getIvar(NULL, NULL));

    object_setIvar(sub, NULL, NULL);
    object_setIvar(NULL, ivar, NULL);
    object_setIvar(NULL, NULL, NULL);

#if !__has_feature(objc_arc)

    uintptr_t value;

    sub->subIvar = (id)10;
    value = 0;
    object_getInstanceVariable(sub, "subIvar", (void **)&value);
    testassert(value == 10);

    object_setInstanceVariable(sub, "subIvar", (id)11);
    testassert(sub->subIvar == (id)11);

    ivar = class_getInstanceVariable([Sub class], "subIvar");
    testassert(ivar == object_getInstanceVariable(sub, "subIvar", NULL));

    testassert(NULL == object_getInstanceVariable(sub, NULL, NULL));
    testassert(NULL == object_getInstanceVariable(NULL, "foo", NULL));
    testassert(NULL == object_getInstanceVariable(NULL, NULL, NULL));
    value = 10;
    testassert(NULL == object_getInstanceVariable(sub, NULL, (void **)&value));
    testassert(value == 0);
    value = 10;
    testassert(NULL == object_getInstanceVariable(NULL, "foo", (void **)&value));
    testassert(value == 0);
    value = 10;
    testassert(NULL == object_getInstanceVariable(NULL, NULL, (void **)&value));
    testassert(value == 0);

    testassert(NULL == object_setInstanceVariable(sub, NULL, NULL));
    testassert(NULL == object_setInstanceVariable(NULL, "foo", NULL));
    testassert(NULL == object_setInstanceVariable(NULL, NULL, NULL));
#endif

    succeed(__FILE__);
    return 0;
}
