/*
TEST_BUILD
    $C{COMPILE} $DIR/concurrentcat.m -o concurrentcat.out -framework Foundation

    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc1 -o cc1.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc2 -o cc2.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc3 -o cc3.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc4 -o cc4.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc5 -o cc5.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc6 -o cc6.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc7 -o cc7.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc8 -o cc8.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc9 -o cc9.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc10 -o cc10.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc11 -o cc11.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc12 -o cc12.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc13 -o cc13.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc14 -o cc14.dylib
    $C{COMPILE} -undefined dynamic_lookup -dynamiclib $DIR/concurrentcat_category.m -DTN=cc15 -o cc15.dylib
END
*/

#include "test.h"
#include <objc/runtime.h>
#include <objc/objc-auto.h>
#include <dlfcn.h>
#include <unistd.h>
#include <pthread.h>
#include <Foundation/Foundation.h>

@interface TargetClass : NSObject
@end

@interface TargetClass(LoadedMethods)
- (void) m0;
- (void) m1;
- (void) m2;
- (void) m3;
- (void) m4;
- (void) m5;
- (void) m6;
- (void) m7;
- (void) m8;
- (void) m9;
- (void) m10;
- (void) m11;
- (void) m12;
- (void) m13;
- (void) m14;
- (void) m15;
@end

@implementation TargetClass
- (void) m0 { fail("shoulda been loaded!"); }
- (void) m1 { fail("shoulda been loaded!"); }
- (void) m2 { fail("shoulda been loaded!"); }
- (void) m3 { fail("shoulda been loaded!"); }
- (void) m4 { fail("shoulda been loaded!"); }
- (void) m5 { fail("shoulda been loaded!"); }
- (void) m6 { fail("shoulda been loaded!"); }
@end

void *threadFun(void *aTargetClassName) {
    const char *className = (const char *)aTargetClassName;

    objc_registerThreadWithCollector();

    PUSH_POOL {
        
        Class targetSubclass = objc_getClass(className);
        testassert(targetSubclass);
        
        id target = [targetSubclass new];
        testassert(target);
        
        while(1) {
            [target m0];
            RETAIN(target);
            [target addObserver: target forKeyPath: @"m3" options: 0 context: NULL];
            [target addObserver: target forKeyPath: @"m4" options: 0 context: NULL];
            [target m1];
            RELEASE_VALUE(target);
            [target m2];
            AUTORELEASE(target);
            [target m3];
            RETAIN(target);
            [target removeObserver: target forKeyPath: @"m4"];
            [target addObserver: target forKeyPath: @"m5" options: 0 context: NULL];
            [target m4];
            RETAIN(target);
            [target m5];
            AUTORELEASE(target);
            [target m6];
            [target m7];
            [target m8];
            [target m9];
            [target m10];
            [target m11];
            [target m12];
            [target m13];
            [target m14];
            [target m15];
            [target removeObserver: target forKeyPath: @"m3"];
            [target removeObserver: target forKeyPath: @"m5"];
        }
    } POP_POOL;
    return NULL;
}

int main()
{
    int i;

    void *dylib;

    for(i=1; i<16; i++) {
	pthread_t t;
	char dlName[100];
	sprintf(dlName, "cc%d.dylib", i);
	dylib = dlopen(dlName, RTLD_LAZY);
	char className[100];
	sprintf(className, "cc%d", i);
	pthread_create(&t, NULL, threadFun, strdup(className));
	testassert(dylib);
    }
    sleep(1);

    succeed(__FILE__);
}
