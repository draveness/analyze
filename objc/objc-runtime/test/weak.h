/*
  To test -weak-l or -weak-framework:
  * -DWEAK_IMPORT=
  * -DWEAK_FRAMEWORK=1
  * -UEMPTY  when building the weak-not-missing library
  * -DEMPTY= when building the weak-missing library

  To test attribute((weak_import)):
  * -DWEAK_IMPORT=__attribute__((weak_import))
  * -UWEAK_FRAMEWORK
  * -UEMPTY  when building the weak-not-missing library
  * -DEMPTY= when building the weak-missing library

*/
 
#include "test.h"
#include <objc/runtime.h>

extern int state;

WEAK_IMPORT OBJC_ROOT_CLASS
@interface MissingRoot {
    id isa;
}
+(void) initialize;
+(Class) class;
+(id) alloc;
-(id) init;
-(void) dealloc;
+(int) method;
@end

@interface MissingRoot (RR)
-(id) retain;
-(void) release;
@end

WEAK_IMPORT
@interface MissingSuper : MissingRoot {
  @public
    int ivar;
}
@end

OBJC_ROOT_CLASS
@interface NotMissingRoot {
    id isa;
}
+(void) initialize;
+(Class) class;
+(id) alloc;
-(id) init;
-(void) dealloc;
+(int) method;
@end

@interface NotMissingRoot (RR)
-(id) retain;
-(void) release;
@end

@interface NotMissingSuper : NotMissingRoot {
  @public
    int unused[100];
    int ivar;
}
@end
