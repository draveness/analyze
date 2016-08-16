extern int state;
extern int cstate;

OBJC_ROOT_CLASS
@interface Super { id isa; } 
+(void) method;
+(void) method0;
@end

@interface Super (cat1)
+(void) method1;
@end

@interface Super (cat2)
+(void) method2;
@end

@interface Super (cat3)
+(void) method3;
@end
