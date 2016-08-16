//
//  MRRBase.m
//  TestARRLayouts
//
//  Created by Patrick Beard on 3/8/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "MRRBase.h"

#if 1
@interface MRRBase () {
@private
    double number;
    id object;
    void *pointer;
    __weak id delegate;
}
@end
#endif

@implementation MRRBase
@synthesize number, object, pointer, delegate;
@end
