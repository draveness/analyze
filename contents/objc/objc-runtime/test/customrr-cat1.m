@interface InheritingSubCat @end

@interface InheritingSubCat (NonClobberingCategory) @end

@implementation InheritingSubCat (NonClobberingCategory) 
-(id) unrelatedMethod { return self; }
@end
