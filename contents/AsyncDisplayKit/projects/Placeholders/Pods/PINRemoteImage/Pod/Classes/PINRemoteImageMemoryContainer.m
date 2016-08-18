//
//  PINRemoteImageMemoryContainer.m
//  Pods
//
//  Created by Garrett Moon on 3/17/16.
//
//

#import "PINRemoteImageMemoryContainer.h"

@implementation PINRemoteImageMemoryContainer

- (instancetype)init
{
    if (self = [super init]) {
        _lock = [[PINRemoteLock alloc] initWithName:@"PINRemoteImageMemoryContainer" lockType:PINRemoteLockTypeNonRecursive];
    }
    return self;
}

@end
