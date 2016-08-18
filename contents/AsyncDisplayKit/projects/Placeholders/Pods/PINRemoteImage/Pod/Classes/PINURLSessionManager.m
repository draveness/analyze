//
//  PINURLSessionManager.m
//  Pods
//
//  Created by Garrett Moon on 6/26/15.
//
//

#import "PINURLSessionManager.h"

NSString * const PINURLErrorDomain = @"PINURLErrorDomain";

@interface PINURLSessionManager () <NSURLSessionDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSLock *sessionManagerLock;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, dispatch_queue_t> *delegateQueues;
@property (nonatomic, strong) NSMutableDictionary *completions;

@end

@implementation PINURLSessionManager

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    if (self = [super init]) {
        self.sessionManagerLock = [[NSLock alloc] init];
        self.sessionManagerLock.name = @"PINURLSessionManager";
        self.operationQueue = [[NSOperationQueue alloc] init];
        self.operationQueue.name = @"PINURLSessionManager Operation Queue";
        
        //queue must be serial to ensure proper ordering
        [self.operationQueue setMaxConcurrentOperationCount:1];
        self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:self.operationQueue];
        self.completions = [[NSMutableDictionary alloc] init];
        self.delegateQueues = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)invalidateSessionAndCancelTasks
{
    [self lock];
        [self.session invalidateAndCancel];
    [self unlock];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLResponse *response, NSError *error))completionHandler
{
    [self lock];
        NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request];
        if (completionHandler) {
            [self.completions setObject:completionHandler forKey:@(dataTask.taskIdentifier)];
        }
        NSString *queueName = [NSString stringWithFormat:@"PINURLSessionManager delegate queue - %ld", (unsigned long)dataTask.taskIdentifier];
        dispatch_queue_t delegateQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        [self.delegateQueues setObject:delegateQueue forKey:@(dataTask.taskIdentifier)];
    [self unlock];
    return dataTask;
}

- (void)lock
{
    [self.sessionManagerLock lock];
}

- (void)unlock
{
    [self.sessionManagerLock unlock];
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler 
{
    if ([self.delegate respondsToSelector:@selector(didReceiveAuthenticationChallenge:forTask:completionHandler:)]) {
        [self.delegate didReceiveAuthenticationChallenge:challenge forTask:nil completionHandler:completionHandler];
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler 
{
    [self lock];
        dispatch_queue_t delegateQueue = self.delegateQueues[@(task.taskIdentifier)];
    [self unlock];

    __weak typeof(self) weakSelf = self;
    dispatch_async(delegateQueue, ^{
        typeof(self) strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(didReceiveAuthenticationChallenge:forTask:completionHandler:)]) {
            [strongSelf.delegate didReceiveAuthenticationChallenge:challenge forTask:task completionHandler:completionHandler];
        } else {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    });
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    [self lock];
        dispatch_queue_t delegateQueue = self.delegateQueues[@(dataTask.taskIdentifier)];
    [self unlock];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(delegateQueue, ^{
        typeof(self) strongSelf = weakSelf;
        [strongSelf.delegate didReceiveData:data forTask:dataTask];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    [self lock];
        dispatch_queue_t delegateQueue = self.delegateQueues[@(task.taskIdentifier)];
    [self unlock];
    if (!error && [task.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)task.response statusCode];
        if (statusCode >= 400) {
            error = [NSError errorWithDomain:PINURLErrorDomain
                                        code:statusCode
                                    userInfo:@{NSLocalizedDescriptionKey : @"HTTP Error Response."}];
        }
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(delegateQueue, ^{
        typeof(self) strongSelf = weakSelf;
        [strongSelf.delegate didCompleteTask:task withError:error];
        
        [strongSelf lock];
            void (^completionHandler)(NSURLResponse *, NSError *) = strongSelf.completions[@(task.taskIdentifier)];
            [strongSelf.completions removeObjectForKey:@(task.taskIdentifier)];
            [strongSelf.delegateQueues removeObjectForKey:@(task.taskIdentifier)];
        [strongSelf unlock];
        
        if (completionHandler) {
            completionHandler(task.response, error);
        }
    });
}

@end
