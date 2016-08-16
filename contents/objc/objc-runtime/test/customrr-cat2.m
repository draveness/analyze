@interface InheritingSubCat @end

@interface InheritingSubCat (ClobberingCategory) @end

@implementation InheritingSubCat (ClobberingCategory) 
-(int) retainCount { return 1; }
@end
