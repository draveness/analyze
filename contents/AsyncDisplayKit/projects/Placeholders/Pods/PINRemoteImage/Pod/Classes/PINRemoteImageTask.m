//
//  PINRemoteImageTask.m
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageTask.h"

#import "PINRemoteImageCallbacks.h"

@implementation PINRemoteImageTask

- (instancetype)init
{
    if (self = [super init]) {
        self.callbackBlocks = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> completionBlocks: %lu", NSStringFromClass([self class]), self, (unsigned long)self.callbackBlocks.count];
}

- (void)addCallbacksWithCompletionBlock:(PINRemoteImageManagerImageCompletion)completionBlock
                     progressImageBlock:(PINRemoteImageManagerImageCompletion)progressImageBlock
                  progressDownloadBlock:(PINRemoteImageManagerProgressDownload)progressDownloadBlock
                               withUUID:(NSUUID *)UUID
{
    PINRemoteImageCallbacks *completion = [[PINRemoteImageCallbacks alloc] init];
    completion.completionBlock = completionBlock;
    completion.progressImageBlock = progressImageBlock;
    completion.progressDownloadBlock = progressDownloadBlock;
    
    [self.callbackBlocks setObject:completion forKey:UUID];
}

- (void)removeCallbackWithUUID:(NSUUID *)UUID
{
    [self.callbackBlocks removeObjectForKey:UUID];
}

- (void)callCompletionsWithQueue:(dispatch_queue_t)queue
                          remove:(BOOL)remove
                       withImage:(PINImage *)image
       alternativeRepresentation:(id)alternativeRepresentation
                          cached:(BOOL)cached
                           error:(NSError *)error
{
    __weak typeof(self) weakSelf = self;
    [self.callbackBlocks enumerateKeysAndObjectsUsingBlock:^(NSUUID *UUID, PINRemoteImageCallbacks *callback, BOOL *stop) {
        typeof(self) strongSelf = weakSelf;
        if (callback.completionBlock != nil) {
            PINLog(@"calling completion for UUID: %@ key: %@", UUID, strongSelf.key);
            PINRemoteImageManagerImageCompletion completionBlock = callback.completionBlock;
            CFTimeInterval requestTime = callback.requestTime;
            
            //The code run asynchronously below is *not* guaranteed to be run in the manager's lock!
            //All access to the callbacks and self should be done outside the block below!
            dispatch_async(queue, ^
            {
                PINRemoteImageResultType result;
                if (image || alternativeRepresentation) {
                    result = cached ? PINRemoteImageResultTypeCache : PINRemoteImageResultTypeDownload;
                } else {
                    result = PINRemoteImageResultTypeNone;
                }
                completionBlock([PINRemoteImageManagerResult imageResultWithImage:image
                                                        alternativeRepresentation:alternativeRepresentation
                                                                    requestLength:CACurrentMediaTime() - requestTime
                                                                            error:error
                                                                       resultType:result
                                                                             UUID:UUID]);
            });
        }
        if (remove) {
            [strongSelf removeCallbackWithUUID:UUID];
        }
    }];
}

- (BOOL)cancelWithUUID:(NSUUID *)UUID manager:(PINRemoteImageManager *)manager
{
    BOOL noMoreCompletions = NO;
    [self removeCallbackWithUUID:UUID];
    if ([self.callbackBlocks count] == 0) {
        noMoreCompletions = YES;
    }
    return noMoreCompletions;
}

- (void)setPriority:(PINRemoteImageManagerPriority)priority
{
    
}

@end
