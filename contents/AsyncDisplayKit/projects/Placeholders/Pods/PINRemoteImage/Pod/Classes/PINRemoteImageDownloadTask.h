//
//  PINRemoteImageDownloadTask.h
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageTask.h"
#import "PINProgressiveImage.h"
#import "PINDataTaskOperation.h"

@interface PINRemoteImageDownloadTask : PINRemoteImageTask

@property (nonatomic, strong, nullable) PINDataTaskOperation *urlSessionTaskOperation;
@property (nonatomic, assign) CFTimeInterval sessionTaskStartTime;
@property (nonatomic, assign) CFTimeInterval sessionTaskEndTime;
@property (nonatomic, assign) BOOL hasProgressBlocks;
@property (nonatomic, strong, nullable) PINProgressiveImage *progressImage;

@property (nonatomic, assign) NSUInteger numberOfRetries;

- (void)callProgressDownloadWithQueue:(nonnull dispatch_queue_t)queue completedBytes:(int64_t)completedBytes totalBytes:(int64_t)totalBytes;
- (void)callProgressImageWithQueue:(nonnull dispatch_queue_t)queue withImage:(nonnull PINImage *)image renderedImageQuality:(CGFloat)renderedImageQuality;

@end
