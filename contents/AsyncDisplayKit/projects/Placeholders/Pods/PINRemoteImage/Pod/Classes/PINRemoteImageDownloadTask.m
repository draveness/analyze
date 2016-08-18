//
//  PINRemoteImageDownloadTask.m
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageDownloadTask.h"

#import "PINRemoteImage.h"
#import "PINRemoteImageCallbacks.h"

@interface PINRemoteImageDownloadTask () {
    BOOL _canSetDataTaskPriority;
}

@end

@implementation PINRemoteImageDownloadTask

- (instancetype)init
{
    if (self = [super init]) {
        _canSetDataTaskPriority = [NSURLSessionTask instancesRespondToSelector:@selector(setPriority:)];
        _numberOfRetries = 0;
    }
    return self;
}

- (BOOL)hasProgressBlocks
{
    __block BOOL hasProgressBlocks = NO;
    [self.callbackBlocks enumerateKeysAndObjectsUsingBlock:^(NSUUID *UUID, PINRemoteImageCallbacks *callback, BOOL *stop) {
        if (callback.progressImageBlock) {
            hasProgressBlocks = YES;
            *stop = YES;
        }
    }];
    return hasProgressBlocks;
}

- (void)callProgressDownloadWithQueue:(nonnull dispatch_queue_t)queue completedBytes:(int64_t)completedBytes totalBytes:(int64_t)totalBytes
{
    [self.callbackBlocks enumerateKeysAndObjectsUsingBlock:^(NSUUID *UUID, PINRemoteImageCallbacks *callback, BOOL *stop) {
        if (callback.progressDownloadBlock != nil) {
            PINLog(@"calling progress for UUID: %@ key: %@", UUID, self.key);
            PINRemoteImageManagerProgressDownload progressDownloadBlock = callback.progressDownloadBlock;
            //The code run asynchronously below is *not* guaranteed to be run in the manager's lock!
            //All access to the callbacks and self should be done outside the block below!
            dispatch_async(queue, ^
            {
                progressDownloadBlock(completedBytes, totalBytes);
            });
        }
    }];
}

- (void)callProgressImageWithQueue:(nonnull dispatch_queue_t)queue withImage:(nonnull PINImage *)image renderedImageQuality:(CGFloat)renderedImageQuality
{
    [self.callbackBlocks enumerateKeysAndObjectsUsingBlock:^(NSUUID *UUID, PINRemoteImageCallbacks *callback, BOOL *stop) {
        if (callback.progressImageBlock != nil) {
            PINLog(@"calling progress for UUID: %@ key: %@", UUID, self.key);
            PINRemoteImageManagerImageCompletion progressImageBlock = callback.progressImageBlock;
            CFTimeInterval requestTime = callback.requestTime;
            //The code run asynchronously below is *not* guaranteed to be run in the manager's lock!
            //All access to the callbacks and self should be done outside the block below!
            dispatch_async(queue, ^
            {
                progressImageBlock([PINRemoteImageManagerResult imageResultWithImage:image
                                                           alternativeRepresentation:nil
                                                                       requestLength:CACurrentMediaTime() - requestTime
                                                                               error:nil
                                                                          resultType:PINRemoteImageResultTypeProgress
                                                                                UUID:UUID
                                                                renderedImageQuality:renderedImageQuality]);
           });
        }
    }];
}

- (BOOL)cancelWithUUID:(NSUUID *)UUID manager:(PINRemoteImageManager *)manager
{
    BOOL noMoreCompletions = [super cancelWithUUID:UUID manager:manager];
    if (noMoreCompletions) {
        [self.urlSessionTaskOperation cancel];
        PINLog(@"Canceling download of URL: %@, UUID: %@", self.urlSessionTaskOperation.dataTask.originalRequest.URL, UUID);
    } else {
        PINLog(@"Decrementing download of URL: %@, UUID: %@", self.urlSessionTaskOperation.dataTask.originalRequest.URL, UUID);
    }
    return noMoreCompletions;
}

- (void)setPriority:(PINRemoteImageManagerPriority)priority
{
    [super setPriority:priority];
    if (_canSetDataTaskPriority) {
        self.urlSessionTaskOperation.dataTask.priority = dataTaskPriorityWithImageManagerPriority(priority);
    }
    self.urlSessionTaskOperation.queuePriority = operationPriorityWithImageManagerPriority(priority);
}

@end
