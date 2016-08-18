//
//  PINRemoteImageCallbacks.m
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageCallbacks.h"

@implementation PINRemoteImageCallbacks

- (void)setCompletionBlock:(PINRemoteImageManagerImageCompletion)completionBlock
{
    _completionBlock = [completionBlock copy];
    self.requestTime = CACurrentMediaTime();
}

@end
