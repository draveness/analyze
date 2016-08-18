//
//  PINRemoteLock.h
//  Pods
//
//  Created by Garrett Moon on 3/17/16.
//
//

#import <Foundation/Foundation.h>

/** The type of lock, either recursive or non-recursive */
typedef NS_ENUM(NSUInteger, PINRemoteLockType) {
    /** A non-recursive version of the lock. The default. */
    PINRemoteLockTypeNonRecursive = 0,
    /** A recursive version of the lock. More expensive. */
    PINRemoteLockTypeRecursive,
};

@interface PINRemoteLock : NSObject

- (instancetype)initWithName:(NSString *)lockName lockType:(PINRemoteLockType)lockType NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithName:(NSString *)lockName;
- (void)lockWithBlock:(dispatch_block_t)block;

- (void)lock;
- (void)unlock;

@end
