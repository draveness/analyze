//
//  PINRemoteImageProcessorTask.m
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageProcessorTask.h"

@implementation PINRemoteImageProcessorTask

- (BOOL)cancelWithUUID:(NSUUID *)UUID manager:(PINRemoteImageManager *)manager
{
    BOOL noMoreCompletions = [super cancelWithUUID:UUID manager:manager];
    if (noMoreCompletions && self.downloadTaskUUID) {
        [manager cancelTaskWithUUID:self.downloadTaskUUID];
        _downloadTaskUUID = nil;
    }
    return noMoreCompletions;
}

- (void)setDownloadTaskUUID:(NSUUID *)downloadTaskUUID
{
    NSAssert(_downloadTaskUUID == nil, @"downloadTaskUUID should be nil");
    _downloadTaskUUID = downloadTaskUUID;
}

@end
