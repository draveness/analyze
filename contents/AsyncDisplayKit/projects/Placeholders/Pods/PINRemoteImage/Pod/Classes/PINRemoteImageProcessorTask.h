//
//  PINRemoteImageProcessorTask.h
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageTask.h"

@interface PINRemoteImageProcessorTask : PINRemoteImageTask

@property (nonatomic, strong, nullable) NSUUID *downloadTaskUUID;

@end
