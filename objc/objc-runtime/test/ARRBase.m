//
//  ARRBase.m
//  TestARRLayouts
//
//  Created by Patrick Beard on 3/8/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ARRBase.h"

#if 1
@interface ARRBase () {
@private
    long number;
    id object;
    void *pointer;
    __weak id delegate;
}
@end
#endif

@implementation ARRBase
@synthesize number, object, pointer, delegate;
@end
