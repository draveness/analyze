//
//  PINAnimatedImage.h
//  Pods
//
//  Created by Garrett Moon on 3/18/16.
//
//

#import <Foundation/Foundation.h>

#import "PINRemoteImageMacros.h"

#define PINAnimatedImageDebug  0

extern NSString *kPINAnimatedImageErrorDomain;

/**
 PINAnimatedImage decoding and processing errors.
 */
typedef NS_ENUM(NSUInteger, PINAnimatedImageError) {
  /** No error, yay! */
  PINAnimatedImageErrorNoError = 0,
  /** Could not create a necessary file. */
  PINAnimatedImageErrorFileCreationError,
  /** Could not get a file handle to the necessary file. */
  PINAnimatedImageErrorFileHandleError,
  /** Could not decode the image. */
  PINAnimatedImageErrorImageFrameError,
  /** Could not memory map the file. */
  PINAnimatedImageErrorMappingError,
  /** File write error */
  PINAnimatedImageErrorFileWrite,
};

/**
 The processing status of the animated image.
 */
typedef NS_ENUM(NSUInteger, PINAnimatedImageStatus) {
  /** No work has been done. */
  PINAnimatedImageStatusUnprocessed = 0,
  /** Info about the animated image and the cover image are available. */
  PINAnimatedImageStatusInfoProcessed,
  /** At least one set of frames has been decoded to a file. It's safe to start playback. */
  PINAnimatedImageStatusFirstFileProcessed,
  /** The entire animated image has been processed. */
  PINAnimatedImageStatusProcessed,
  /** Processing was canceled. */
  PINAnimatedImageStatusCanceled,
  /** There was an error in processing. */
  PINAnimatedImageStatusError,
};

extern const Float32 kPINAnimatedImageDefaultDuration;
extern const Float32 kPINAnimatedImageMinimumDuration;
extern const NSTimeInterval kPINAnimatedImageDisplayRefreshRate;

/**
 Called when the cover image of an animatedImage is ready.
 */
typedef void(^PINAnimatedImageInfoReady)(PINImage *coverImage);


/**
 PINAnimatedImage is a class which decodes GIFs to memory mapped files on disk. Like PINRemoteImageManager,
 it will only decode a GIF one time, regardless of the number of the number of PINAnimatedImages created with
 the same NSData.
 
 PINAnimatedImage's are also decoded chunks at a time, writing each chunk to a separate file. This allows callback
 and playback to start before the GIF is completely decoded. If a frame is requested beyond what has been processed,
 nil will be returned. Because a fileReady is called on each chunk completion, you can pause playback if you hit a nil
 frame until you receive another fileReady call.
 
 Internally, PINAnimatedImage attempts to keep only the files it needs open – the last file associated with the requested
 frame and the one after (to prime).
 
 It's important to note that until infoCompletion is called, it is unsafe to access many of the methods on PINAnimatedImage.
 */
@interface PINAnimatedImage : NSObject

- (instancetype)initWithAnimatedImageData:(NSData *)animatedImageData NS_DESIGNATED_INITIALIZER;

/**
 A block to be called on when GIF info has been processed. Status will == PINAnimatedImageStatusInfoProcessed
 */
@property (nonatomic, strong, readwrite) PINAnimatedImageInfoReady infoCompletion;
/**
 A block to be called whenever a new file is done being processed. You can start (or resume) playback when you
 get this callback, though it's possible for playback to catch up to the decoding and you'll need to pause.
 */
@property (nonatomic, strong, readwrite) dispatch_block_t fileReady;
/**
 A block to be called when the animated image is fully decoded and written to disk.
 */
@property (nonatomic, strong, readwrite) dispatch_block_t animatedImageReady;

/**
 The current status of the animated image.
 */
@property (nonatomic, assign, readwrite) PINAnimatedImageStatus status;

/**
 A helper function which references status to check if the coverImage is ready.
 */
@property (nonatomic, readonly) BOOL coverImageReady;
/**
 A helper function which references status to check if playback is ready.
 */
@property (nonatomic, readonly) BOOL playbackReady;
/**
 The first frame / cover image of the animated image.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined. You can check coverImageReady too.
 */
@property (nonatomic, readonly) PINImage *coverImage;
/**
 The total duration of one loop of playback.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
@property (nonatomic, readonly) CFTimeInterval totalDuration;
/**
 The number of frames to play per second * display refresh rate (defined as 60 which appears to be true on iOS). You probably want to 
 set this value on a displayLink.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
@property (nonatomic, readonly) NSUInteger frameInterval;
/**
 The number of times to loop the animated image. Returns 0 if looping should occur infinitely.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
@property (nonatomic, readonly) size_t loopCount;
/**
 The total number of frames in the animated image.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
@property (nonatomic, readonly) size_t frameCount;
/**
 Any processing error that may have occured.
 */
@property (nonatomic, readonly) NSError *error;

/**
 The image at the frame index passed in.
 @param index The index of the frame to retrieve.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
- (CGImageRef)imageAtIndex:(NSUInteger)index;
/**
 The duration of the frame of the passed in index.
 @param index The index of the frame to retrieve the duration it should be shown for.
 @warning Access to this property before status == PINAnimatedImageStatusInfoProcessed is undefined.
 */
- (CFTimeInterval)durationAtIndex:(NSUInteger)index;
/**
 Clears out the strong references to any memory maps that are being held.
 */
- (void)clearAnimatedImageCache;

@end
