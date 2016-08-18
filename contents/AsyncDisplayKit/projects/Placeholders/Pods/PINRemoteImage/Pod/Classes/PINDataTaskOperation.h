//
//  PINDataTaskOperation.h
//  Pods
//
//  Created by Garrett Moon on 3/12/15.
//
//

#import <Foundation/Foundation.h>

#import "PINURLSessionManager.h"

@interface PINDataTaskOperation : NSOperation

@property (nonatomic, readonly, nullable) NSURLSessionDataTask *dataTask;

+ (nonnull instancetype)dataTaskOperationWithSessionManager:(nonnull PINURLSessionManager *)sessionManager
                                                    request:(nonnull NSURLRequest *)request
                                          completionHandler:(nonnull void (^)(NSURLResponse * _Nonnull response, NSError * _Nullable error))completionHandler;

@end
