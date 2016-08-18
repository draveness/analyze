//
//  PINAnimatedImageManager.h
//  Pods
//
//  Created by Garrett Moon on 4/5/16.
//
//

#import <Foundation/Foundation.h>

#import "PINAnimatedImage.h"
#import "PINRemoteImageMacros.h"

@class PINRemoteLock;
@class PINSharedAnimatedImage;
@class PINSharedAnimatedImageFile;

typedef void(^PINAnimatedImageSharedReady)(PINImage *coverImage, PINSharedAnimatedImage *shared);
typedef void(^PINAnimatedImageDecodedPath)(BOOL finished, NSString *path, NSError *error);

@interface PINAnimatedImageManager : NSObject

+ (instancetype)sharedManager;
+ (NSString *)temporaryDirectory;
+ (NSString *)filePathWithTemporaryDirectory:(NSString *)temporaryDirectory UUID:(NSUUID *)UUID count:(NSUInteger)count;

- (void)animatedPathForImageData:(NSData *)animatedImageData infoCompletion:(PINAnimatedImageSharedReady)infoCompletion completion:(PINAnimatedImageDecodedPath)completion;

@end

@interface PINSharedAnimatedImage : NSObject
{
  PINRemoteLock *_coverImageLock;
}

//This is intentionally atomic. PINAnimatedImageManager must be able to add entries
//and clients must be able to read them concurrently.
@property (atomic, strong, readwrite) NSArray <PINSharedAnimatedImageFile *> *maps;

@property (nonatomic, strong, readwrite) NSArray <PINAnimatedImageDecodedPath> *completions;
@property (nonatomic, strong, readwrite) NSArray <PINAnimatedImageSharedReady> *infoCompletions;
@property (nonatomic, weak, readwrite) PINImage *coverImage;

//intentionally atomic
@property (atomic, strong, readwrite) NSError *error;
@property (atomic, assign, readwrite) PINAnimatedImageStatus status;

- (void)setInfoProcessedWithCoverImage:(PINImage *)coverImage
                                  UUID:(NSUUID *)UUID
                             durations:(Float32 *)durations
                         totalDuration:(CFTimeInterval)totalDuration
                             loopCount:(size_t)loopCount
                            frameCount:(size_t)frameCount
                                 width:(size_t)width
                                height:(size_t)height
                          bitsPerPixel:(size_t)bitsPerPixel
                            bitmapInfo:(CGBitmapInfo)bitmapInfo;

@property (nonatomic, readonly) NSUUID *UUID;
@property (nonatomic, readonly) Float32 *durations;
@property (nonatomic, readonly) CFTimeInterval totalDuration;
@property (nonatomic, readonly) size_t loopCount;
@property (nonatomic, readonly) size_t frameCount;
@property (nonatomic, readonly) size_t width;
@property (nonatomic, readonly) size_t height;
@property (nonatomic, readonly) size_t bitsPerPixel;
@property (nonatomic, readonly) CGBitmapInfo bitmapInfo;

@end

@interface PINSharedAnimatedImageFile : NSObject
{
  PINRemoteLock *_lock;
}

@property (nonatomic, strong, readonly) NSString *path;
@property (nonatomic, assign, readonly) UInt32 frameCount;
@property (nonatomic, weak, readonly) NSData *memoryMappedData;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

@end
