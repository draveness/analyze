//
//  PINRemoteImageTask.h
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import <Foundation/Foundation.h>

#import "PINRemoteImageManager.h"
#import "PINRemoteImageMacros.h"

@interface PINRemoteImageTask : NSObject

@property (nonatomic, strong, nonnull) NSMutableDictionary *callbackBlocks;
#if PINRemoteImageLogging
@property (nonatomic, copy, nullable) NSString *key;
#endif

- (void)addCallbacksWithCompletionBlock:(nonnull PINRemoteImageManagerImageCompletion)completionBlock
                     progressImageBlock:(nullable PINRemoteImageManagerImageCompletion)progressImageBlock
                  progressDownloadBlock:(nullable PINRemoteImageManagerProgressDownload)progressDownloadBlock
                               withUUID:(nonnull NSUUID *)UUID;

- (void)removeCallbackWithUUID:(nonnull NSUUID *)UUID;

- (void)callCompletionsWithQueue:(nonnull dispatch_queue_t)queue
                          remove:(BOOL)remove
                       withImage:(nullable PINImage *)image
       alternativeRepresentation:(nullable id)alternativeRepresentation
                          cached:(BOOL)cached
                           error:(nullable NSError *)error;

//returns YES if no more attached completionBlocks
- (BOOL)cancelWithUUID:(nonnull NSUUID *)UUID manager:(nullable PINRemoteImageManager *)manager;

- (void)setPriority:(PINRemoteImageManagerPriority)priority;

@end
