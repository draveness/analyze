// TEST_CFLAGS -Wl,-no_objc_category_merging

#include "test.h"
#include "testroot.i"
#include <string.h>
#include <objc/runtime.h>

static int state = 0;

@interface Super : TestRoot @end
@implementation Super
-(void)instancemethod { fail("-instancemethod not overridden by category"); }
+(void)method { fail("+method not overridden by category"); } 
@end

@interface Super (Category) @end
@implementation Super (Category) 
+(void)method { 
    testprintf("in [Super(Category) method]\n"); 
    testassert(self == [Super class]);
    testassert(state == 0);
    state = 1;
}
-(void)instancemethod { 
    testprintf("in [Super(Category) instancemethod]\n"); 
    testassert(object_getClass(self) == [Super class]);
    testassert(state == 1);
    state = 2;
}
@end

@interface Super (PropertyCategory) 
@property int i;
@end
@implementation Super (PropertyCategory) 
- (int)i { return 0; }
- (void)setI:(int)value { (void)value; }
@end

// rdar://5086110  memory smasher in category with class method and property
@interface Super (r5086110) 
@property int property5086110;
@end
@implementation Super (r5086110) 
+(void)method5086110 { 
    fail("method method5086110 called!");
}
- (int)property5086110 { fail("property5086110 called!"); return 0; }
- (void)setProperty5086110:(int)value { fail("setProperty5086110 called!"); (void)value; }
@end


@interface PropertyClass : Super {
    int q;
}
@property(readonly) int q;
@end
@implementation PropertyClass
@synthesize q;
@end

@interface PropertyClass (PropertyCategory)
@property int q;
@end
@implementation PropertyClass (PropertyCategory)
@dynamic q;
@end


int main()
{
    // methods introduced by category
    state = 0;
    [Super method];
    [[Super new] instancemethod];
    testassert(state == 2);

    // property introduced by category
    objc_property_t p = class_getProperty([Super class], "i");
    testassert(p);
    testassert(0 == strcmp(property_getName(p), "i"));
    testassert(property_getAttributes(p));

    // methods introduced by category's property
    Method m;
    m = class_getInstanceMethod([Super class], @selector(i));
    testassert(m);
    m = class_getInstanceMethod([Super class], @selector(setI:));
    testassert(m);

    // class's property shadowed by category's property
    objc_property_t *plist = class_copyPropertyList([PropertyClass class], NULL);
    testassert(plist);
    testassert(plist[0]);
    testassert(0 == strcmp(property_getName(plist[0]), "q"));
    testassert(0 == strcmp(property_getAttributes(plist[0]), "Ti,D"));
    testassert(plist[1]);
    testassert(0 == strcmp(property_getName(plist[1]), "q"));
    testassert(0 == strcmp(property_getAttributes(plist[1]), "Ti,R,Vq"));
    testassert(!plist[2]);
    free(plist);
    
    succeed(__FILE__);
}

