//
//  PINDataTaskOperation.m
//  Pods
//
//  Created by Garrett Moon on 3/12/15.
//
//

#import "PINDataTaskOperation.h"

#import "PINURLSessionManager.h"

typedef NS_ENUM(NSUInteger, PIDataTaskOperationState) {
    PIDataTaskOperationStateReady,
    PIDataTaskOperationStateExecuting,
    PIDataTaskOperationStateFinished,
};

@interface PINDataTaskOperation () <NSURLSessionDelegate>
{
    NSRecursiveLock *_lock;;
}

@property (nonatomic, strong, readwrite) NSURLSessionDataTask *dataTask;
@property (nonatomic, assign, readwrite) PIDataTaskOperationState state;

@end

static inline NSString * PIKeyPathFromOperationState(PIDataTaskOperationState state) {
    switch (state) {
        case PIDataTaskOperationStateReady:
            return @"isReady";
        case PIDataTaskOperationStateExecuting:
            return @"isExecuting";
        case PIDataTaskOperationStateFinished:
            return @"isFinished";
    }
}

@implementation PINDataTaskOperation

- (instancetype)init
{
    if (self = [super init]) {
        _state = PIDataTaskOperationStateReady;
        _lock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

+ (instancetype)dataTaskOperationWithSessionManager:(PINURLSessionManager *)sessionManager
                                            request:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSURLResponse *response, NSError *error))completionHandler
{
    PINDataTaskOperation *operation = [[self alloc] init];
    operation.dataTask = [sessionManager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, NSError *error) {
        completionHandler(response, error);
        if (operation.isCancelled == NO) {
            [operation finish];
        }
    }];
    
    return operation;
}

- (void)start
{
    [self lock];
    if ([self isCancelled]) {
        [self cancelTask];
    } else if ([self isReady]) {
        self.state = PIDataTaskOperationStateExecuting;
        
        [self.dataTask resume];
    }
    [self unlock];
}

- (void)cancel
{
    [self lock];
    if (![self isFinished] && ![self isCancelled]) {
        [super cancel];
        
        if ([self isExecuting]) {
            [self cancelTask];
        }
    }
    [self unlock];
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    return self.state == PIDataTaskOperationStateExecuting;
}

- (BOOL)isFinished
{
    return self.state == PIDataTaskOperationStateFinished;
}

- (void)finish
{
    self.state = PIDataTaskOperationStateFinished;
}

- (void)cancelTask
{
    [self lock];
    if (![self isFinished]) {
        if (self.dataTask) {
            [self.dataTask cancel];
        }
        [self finish];
    }
    [self unlock];
}

- (void)setState:(PIDataTaskOperationState)state
{
    [self lock];
    NSString *oldStateKey = PIKeyPathFromOperationState(self.state);
    NSString *newStateKey = PIKeyPathFromOperationState(state);
    
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _state = state;
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self unlock];
}

- (void)lock
{
    [_lock lock];
}

- (void)unlock
{
    [_lock unlock];
}

@end
