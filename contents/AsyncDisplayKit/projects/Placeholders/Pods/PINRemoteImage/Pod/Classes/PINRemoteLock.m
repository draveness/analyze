//
//  PINRemoteLock.m
//  Pods
//
//  Created by Garrett Moon on 3/17/16.
//
//

#import "PINRemoteLock.h"

#import <pthread.h>

#if !defined(PINREMOTELOCK_DEBUG) && defined(DEBUG)
#define PINREMOTELOCK_DEBUG DEBUG
#endif

@interface PINRemoteLock ()
{
#if PINREMOTELOCK_DEBUG
    NSLock *_lock;
    NSRecursiveLock *_recursiveLock;
#else
    pthread_mutex_t _lock;
#endif
}

@end

@implementation PINRemoteLock

- (instancetype)init
{
    return [self initWithName:nil];
}

- (instancetype)initWithName:(NSString *)lockName lockType:(PINRemoteLockType)lockType
{
    if (self = [super init]) {
#if PINREMOTELOCK_DEBUG
        if (lockType == PINRemoteLockTypeNonRecursive) {
            _lock = [[NSLock alloc] init];
        } else {
            _recursiveLock = [[NSRecursiveLock alloc] init];
        }
        
        if (lockName) {
            [_lock setName:lockName];
            [_recursiveLock setName:lockName];
        }
#else
        pthread_mutexattr_t attr;
        
        pthread_mutexattr_init(&attr);
        if (lockType == PINRemoteLockTypeRecursive) {
            pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        }
        pthread_mutex_init(&_lock, &attr);
#endif
    }
    return self;
}

- (instancetype)initWithName:(NSString *)lockName
{
    return [self initWithName:lockName lockType:PINRemoteLockTypeNonRecursive];
}

#if ! PINREMOTELOCK_DEBUG
- (void)dealloc
{
    pthread_mutex_destroy(&_lock);
}
#endif

- (void)lockWithBlock:(dispatch_block_t)block
{
#if PINREMOTELOCK_DEBUG
    [_lock lock];
    [_recursiveLock lock];
#else
    pthread_mutex_lock(&_lock);
#endif
    block();
#if PINREMOTELOCK_DEBUG
    [_lock unlock];
    [_recursiveLock unlock];
#else
    pthread_mutex_unlock(&_lock);
#endif
}

- (void)lock
{
#if PINREMOTELOCK_DEBUG
    [_lock lock];
    [_recursiveLock lock];
#else
    pthread_mutex_lock(&_lock);
#endif
}

- (void)unlock
{
#if PINREMOTELOCK_DEBUG
    [_lock unlock];
    [_recursiveLock unlock];
#else
    pthread_mutex_unlock(&_lock);
#endif
}

@end
