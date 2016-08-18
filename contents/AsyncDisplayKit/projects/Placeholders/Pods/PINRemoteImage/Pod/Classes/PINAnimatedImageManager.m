//
//  PINAnimatedImageManager.m
//  Pods
//
//  Created by Garrett Moon on 4/5/16.
//
//

#import "PINAnimatedImageManager.h"

#import <ImageIO/ImageIO.h>
#if PIN_TARGET_IOS
#import <MobileCoreServices/UTCoreTypes.h>
#elif PIN_TARGET_MAC
#import <CoreServices/CoreServices.h>
#endif

#import "PINRemoteLock.h"

static const NSUInteger maxFileSize = 50000000; //max file size in bytes
static const Float32 maxFileDuration = 1; //max duration of a file in seconds

typedef void(^PINAnimatedImageInfoProcessed)(PINImage *coverImage, NSUUID *UUID, Float32 *durations, CFTimeInterval totalDuration, size_t loopCount, size_t frameCount, size_t width, size_t height, size_t bitsPerPixel, UInt32 bitmapInfo);

BOOL PINStatusCoverImageCompleted(PINAnimatedImageStatus status);
BOOL PINStatusCoverImageCompleted(PINAnimatedImageStatus status) {
  return status == PINAnimatedImageStatusInfoProcessed || status == PINAnimatedImageStatusFirstFileProcessed || status == PINAnimatedImageStatusProcessed;
}

@interface PINAnimatedImageManager ()
{
  PINRemoteLock *_lock;
}

+ (instancetype)sharedManager;

@property (nonatomic, strong, readonly) NSMapTable <NSData *, PINSharedAnimatedImage *> *animatedImages;
@property (nonatomic, strong, readonly) dispatch_queue_t serialProcessingQueue;

@end

static dispatch_once_t startupCleanupOnce;

@implementation PINAnimatedImageManager

+ (void)load
{
  if (self == [PINAnimatedImageManager class]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      dispatch_once(&startupCleanupOnce, ^{
        [self cleanupFiles];
      });
    });
  }
}

+ (instancetype)sharedManager
{
  static dispatch_once_t onceToken;
  static PINAnimatedImageManager *sharedManager;
  dispatch_once(&onceToken, ^{
    sharedManager = [[PINAnimatedImageManager alloc] init];
  });
  return sharedManager;
}

+ (NSString *)temporaryDirectory
{
  static dispatch_once_t onceToken;
  static NSString *temporaryDirectory;
  dispatch_once(&onceToken, ^{
    //On iOS temp directories are not shared between apps. This may not be safe on OS X or other systems
    temporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ASAnimatedImageCache"];
  });
  return temporaryDirectory;
}

- (instancetype)init
{
  if (self = [super init]) {
    dispatch_once(&startupCleanupOnce, ^{
      [PINAnimatedImageManager cleanupFiles];
    });
    
    _lock = [[PINRemoteLock alloc] initWithName:@"PINAnimatedImageManager lock"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[PINAnimatedImageManager temporaryDirectory]] == NO) {
      [[NSFileManager defaultManager] createDirectoryAtPath:[PINAnimatedImageManager temporaryDirectory] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    _animatedImages = [[NSMapTable alloc] initWithKeyOptions:NSMapTableWeakMemory valueOptions:NSMapTableWeakMemory capacity:1];
    _serialProcessingQueue = dispatch_queue_create("Serial animated image processing queue.", DISPATCH_QUEUE_SERIAL);
    
#if PIN_TARGET_IOS
    NSString * const notificationName = UIApplicationWillTerminateNotification;
#elif PIN_TARGET_MAC
    NSString * const notificationName = NSApplicationWillTerminateNotification;
#endif
    [[NSNotificationCenter defaultCenter] addObserverForName:notificationName
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
                                                    [PINAnimatedImageManager cleanupFiles];
                                                  }];
  }
  return self;
}

+ (void)cleanupFiles
{
  [[NSFileManager defaultManager] removeItemAtPath:[PINAnimatedImageManager temporaryDirectory] error:nil];
}

- (void)animatedPathForImageData:(NSData *)animatedImageData infoCompletion:(PINAnimatedImageSharedReady)infoCompletion completion:(PINAnimatedImageDecodedPath)completion
{
  __block BOOL startProcessing = NO;
  __block PINSharedAnimatedImage *sharedAnimatedImage = nil;
  {
    [_lock lockWithBlock:^{
      sharedAnimatedImage = [self.animatedImages objectForKey:animatedImageData];
      if (sharedAnimatedImage == nil) {
        sharedAnimatedImage = [[PINSharedAnimatedImage alloc] init];
        [self.animatedImages setObject:sharedAnimatedImage forKey:animatedImageData];
        startProcessing = YES;
      }
      
      if (PINStatusCoverImageCompleted(sharedAnimatedImage.status)) {
        //Info is already processed, call infoCompletion immediately
        if (infoCompletion) {
          infoCompletion(sharedAnimatedImage.coverImage, sharedAnimatedImage);
        }
      } else {
        //Add infoCompletion to sharedAnimatedImage
        if (infoCompletion) {
          //Since ASSharedAnimatedImages are stored weakly in our map, we need a strong reference in completions
          PINAnimatedImageSharedReady capturingInfoCompletion = ^(PINImage *coverImage, PINSharedAnimatedImage *newShared) {
            __unused PINSharedAnimatedImage *strongShared = sharedAnimatedImage;
            infoCompletion(coverImage, newShared);
          };
          sharedAnimatedImage.infoCompletions = [sharedAnimatedImage.infoCompletions arrayByAddingObject:capturingInfoCompletion];
        }
      }
      
      if (sharedAnimatedImage.status == PINAnimatedImageStatusProcessed) {
        //Animated image is already fully processed, call completion immediately
        if (completion) {
          completion(YES, nil, nil);
        }
      } else if (sharedAnimatedImage.status == PINAnimatedImageStatusError) {
        if (completion) {
          completion(NO, nil, sharedAnimatedImage.error);
        }
      } else {
        //Add completion to sharedAnimatedImage
        if (completion) {
          //Since PINSharedAnimatedImages are stored weakly in our map, we need a strong reference in completions
          PINAnimatedImageDecodedPath capturingCompletion = ^(BOOL finished, NSString *path, NSError *error) {
            __unused PINSharedAnimatedImage *strongShared = sharedAnimatedImage;
            completion(finished, path, error);
          };
          sharedAnimatedImage.completions = [sharedAnimatedImage.completions arrayByAddingObject:capturingCompletion];
        }
      }
    }];
  }
  
  if (startProcessing) {
    dispatch_async(self.serialProcessingQueue, ^{
      [[self class] processAnimatedImage:animatedImageData temporaryDirectory:[PINAnimatedImageManager temporaryDirectory] infoCompletion:^(PINImage *coverImage, NSUUID *UUID, Float32 *durations, CFTimeInterval totalDuration, size_t loopCount, size_t frameCount, size_t width, size_t height, size_t bitsPerPixel, UInt32 bitmapInfo) {
        __block NSArray *infoCompletions = nil;
        __block PINSharedAnimatedImage *sharedAnimatedImage = nil;
        [_lock lockWithBlock:^{
          sharedAnimatedImage = [self.animatedImages objectForKey:animatedImageData];
          [sharedAnimatedImage setInfoProcessedWithCoverImage:coverImage UUID:UUID durations:durations totalDuration:totalDuration loopCount:loopCount frameCount:frameCount width:width height:height bitsPerPixel:bitsPerPixel bitmapInfo:bitmapInfo];
          infoCompletions = sharedAnimatedImage.infoCompletions;
          sharedAnimatedImage.infoCompletions = @[];
        }];
        
        for (PINAnimatedImageSharedReady infoCompletion in infoCompletions) {
          infoCompletion(coverImage, sharedAnimatedImage);
        }
      } decodedPath:^(BOOL finished, NSString *path, NSError *error) {
        __block NSArray *completions = nil;
        {
          [_lock lockWithBlock:^{
            PINSharedAnimatedImage *sharedAnimatedImage = [self.animatedImages objectForKey:animatedImageData];
            
            if (path && error == nil) {
              sharedAnimatedImage.maps = [sharedAnimatedImage.maps arrayByAddingObject:[[PINSharedAnimatedImageFile alloc] initWithPath:path]];
            }
            sharedAnimatedImage.error = error;
            if (error) {
              sharedAnimatedImage.status = PINAnimatedImageStatusError;
            }
            
            completions = sharedAnimatedImage.completions;
            if (finished || error) {
              sharedAnimatedImage.completions = @[];
            }
            
            if (error == nil) {
              if (finished) {
                sharedAnimatedImage.status = PINAnimatedImageStatusProcessed;
              } else {
                sharedAnimatedImage.status = PINAnimatedImageStatusFirstFileProcessed;
              }
            }
          }];
        }
        
        for (PINAnimatedImageDecodedPath completion in completions) {
          completion(finished, path, error);
        }
      }];
    });
  }
}

#define HANDLE_PROCESSING_ERROR(ERROR) \
{ \
if (ERROR != nil) { \
  [errorLock lockWithBlock:^{ \
    if (processingError == nil) { \
      processingError = ERROR; \
    } \
  }]; \
\
[fileHandle closeFile]; \
[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil]; \
} \
}

#define PROCESSING_ERROR \
({__block NSError *ERROR; \
[errorLock lockWithBlock:^{ \
  ERROR = processingError; \
}]; \
ERROR;}) \

+ (void)processAnimatedImage:(NSData *)animatedImageData
          temporaryDirectory:(NSString *)temporaryDirectory
              infoCompletion:(PINAnimatedImageInfoProcessed)infoCompletion
                 decodedPath:(PINAnimatedImageDecodedPath)completion
{
  NSUUID *UUID = [NSUUID UUID];
  __block NSError *processingError = nil;
  PINRemoteLock *errorLock = [[PINRemoteLock alloc] initWithName:@"animatedImage processing lock"];
  NSString *filePath = nil;
  //TODO Must handle file handle errors! Documentation says it throws exceptions on any errors :(
  NSError *fileHandleError = nil;
  NSFileHandle *fileHandle = [self fileHandle:&fileHandleError filePath:&filePath temporaryDirectory:temporaryDirectory UUID:UUID count:0];
  HANDLE_PROCESSING_ERROR(fileHandleError);
  UInt32 width;
  UInt32 height;
  UInt32 bitsPerPixel;
  UInt32 bitmapInfo;
  NSUInteger fileCount = 0;
  UInt32 frameCountForFile = 0;
  Float32 *durations = NULL;
  
#if PINAnimatedImageDebug
  CFTimeInterval start = CACurrentMediaTime();
#endif
  
  if (fileHandle && PROCESSING_ERROR == nil) {
    dispatch_queue_t diskWriteQueue = dispatch_queue_create("PINAnimatedImage disk write queue", DISPATCH_QUEUE_SERIAL);
    dispatch_group_t diskGroup = dispatch_group_create();
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)animatedImageData,
                                                               (CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceTypeIdentifierHint : (__bridge NSString *)kUTTypeGIF,
                                                                                  (__bridge NSString *)kCGImageSourceShouldCache : (__bridge NSNumber *)kCFBooleanFalse});
    
    if (imageSource) {
      UInt32 frameCount = (UInt32)CGImageSourceGetCount(imageSource);
      NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(imageSource, nil);
      UInt32 loopCount = (UInt32)[[[imageProperties objectForKey:(__bridge NSString *)kCGImagePropertyGIFDictionary]
                                   objectForKey:(__bridge NSString *)kCGImagePropertyGIFLoopCount] unsignedLongValue];
      
      Float32 fileDuration = 0;
      NSUInteger fileSize = 0;
      durations = (Float32 *)malloc(sizeof(Float32) * frameCount);
      CFTimeInterval totalDuration = 0;
      PINImage *coverImage = nil;
      
      //Gather header file info
      for (NSUInteger frameIdx = 0; frameIdx < frameCount; frameIdx++) {
        if (frameIdx == 0) {
          CGImageRef frameImage = CGImageSourceCreateImageAtIndex(imageSource, frameIdx, (CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache : (__bridge NSNumber *)kCFBooleanFalse});
          if (frameImage == nil) {
            NSError *frameError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorImageFrameError userInfo:nil];
            HANDLE_PROCESSING_ERROR(frameError);
            break;
          }
          
          bitmapInfo = CGImageGetBitmapInfo(frameImage);
          
          width = (UInt32)CGImageGetWidth(frameImage);
          height = (UInt32)CGImageGetHeight(frameImage);
          bitsPerPixel = (UInt32)CGImageGetBitsPerPixel(frameImage);
          
#if PIN_TARGET_IOS
          coverImage = [UIImage imageWithCGImage:frameImage];
#elif PIN_TARGET_MAC
          coverImage = [[NSImage alloc] initWithCGImage:frameImage size:CGSizeMake(width, height)];
#endif
          CGImageRelease(frameImage);
        }
        
        Float32 duration = [[self class] frameDurationAtIndex:frameIdx source:imageSource];
        durations[frameIdx] = duration;
        totalDuration += duration;
      }
      
      if (PROCESSING_ERROR == nil) {
        //Get size, write file header get coverImage
        dispatch_group_async(diskGroup, diskWriteQueue, ^{
          NSError *fileHeaderError = [self writeFileHeader:fileHandle width:width height:height bitsPerPixel:bitsPerPixel loopCount:loopCount frameCount:frameCount bitmapInfo:bitmapInfo durations:durations];
          HANDLE_PROCESSING_ERROR(fileHeaderError);
          if (fileHeaderError == nil) {
            [fileHandle closeFile];
            
            PINLog(@"notifying info");
            infoCompletion(coverImage, UUID, durations, totalDuration, loopCount, frameCount, width, height, bitsPerPixel, bitmapInfo);
          }
        });
        fileCount = 1;
        NSError *fileHandleError = nil;
        fileHandle = [self fileHandle:&fileHandleError filePath:&filePath temporaryDirectory:temporaryDirectory UUID:UUID count:fileCount];
        HANDLE_PROCESSING_ERROR(fileHandleError);
        
        dispatch_group_async(diskGroup, diskWriteQueue, ^{
          //write empty frame count
          @try {
            [fileHandle writeData:[NSData dataWithBytes:&frameCountForFile length:sizeof(frameCountForFile)]];
          } @catch (NSException *exception) {
            NSError *frameCountError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
            HANDLE_PROCESSING_ERROR(frameCountError);
          } @finally {}
        });
        
        //Process frames
        for (NSUInteger frameIdx = 0; frameIdx < frameCount; frameIdx++) {
          if (PROCESSING_ERROR != nil) {
            break;
          }
          @autoreleasepool {
            if (fileDuration > maxFileDuration || fileSize > maxFileSize) {
              //create a new file
              dispatch_group_async(diskGroup, diskWriteQueue, ^{
                //prepend file with frameCount
                @try {
                  [fileHandle seekToFileOffset:0];
                  [fileHandle writeData:[NSData dataWithBytes:&frameCountForFile length:sizeof(frameCountForFile)]];
                  [fileHandle closeFile];
                } @catch (NSException *exception) {
                  NSError *frameCountError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
                  HANDLE_PROCESSING_ERROR(frameCountError);
                } @finally {}
              });
              
              dispatch_group_async(diskGroup, diskWriteQueue, ^{
                PINLog(@"notifying file: %@", filePath);
                completion(NO, filePath, PROCESSING_ERROR);
              });
              
              diskGroup = dispatch_group_create();
              fileCount++;
              NSError *fileHandleError = nil;
              fileHandle = [self fileHandle:&fileHandleError filePath:&filePath temporaryDirectory:temporaryDirectory UUID:UUID count:fileCount];
              HANDLE_PROCESSING_ERROR(fileHandleError);
              frameCountForFile = 0;
              fileDuration = 0;
              fileSize = 0;
              //write empty frame count
              dispatch_group_async(diskGroup, diskWriteQueue, ^{
                @try {
                  [fileHandle writeData:[NSData dataWithBytes:&frameCountForFile length:sizeof(frameCountForFile)]];
                } @catch (NSException *exception) {
                  NSError *frameCountError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
                  HANDLE_PROCESSING_ERROR(frameCountError);
                } @finally {}
              });
            }
            
            Float32 duration = durations[frameIdx];
            fileDuration += duration;
            
            dispatch_group_async(diskGroup, diskWriteQueue, ^{
              if (PROCESSING_ERROR) {
                return;
              }
              
              CGImageRef frameImage = CGImageSourceCreateImageAtIndex(imageSource, frameIdx, (CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache : (__bridge NSNumber *)kCFBooleanFalse});
              if (frameImage == nil) {
                NSError *frameImageError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorImageFrameError userInfo:nil];
                HANDLE_PROCESSING_ERROR(frameImageError);
                return;
              }
              
              NSData *frameData = (__bridge_transfer NSData *)CGDataProviderCopyData(CGImageGetDataProvider(frameImage));
              NSAssert(frameData.length == width * height * bitsPerPixel / 8, @"data should be width * height * bytes per pixel");
              NSError *frameWriteError = [self writeFrameToFile:fileHandle duration:duration frameData:frameData];
              HANDLE_PROCESSING_ERROR(frameWriteError);
              
              CGImageRelease(frameImage);
            });
            
            frameCountForFile++;
          }
        }
      } else {
        completion(NO, nil, PROCESSING_ERROR);
      }
    }
    
    dispatch_group_wait(diskGroup, DISPATCH_TIME_FOREVER);
    if (imageSource) {
      CFRelease(imageSource);
    }
    
    //close the file handle
    PINLog(@"closing last file: %@", fileHandle);
    @try {
      [fileHandle seekToFileOffset:0];
      [fileHandle writeData:[NSData dataWithBytes:&frameCountForFile length:sizeof(frameCountForFile)]];
      [fileHandle closeFile];
    } @catch (NSException *exception) {
      NSError *frameCountError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
      HANDLE_PROCESSING_ERROR(frameCountError);
    } @finally {}
  }
  
#if PINAnimatedImageDebug
  CFTimeInterval interval = CACurrentMediaTime() - start;
  NSLog(@"Encoding and write time: %f", interval);
#endif
  
  if (durations) {
    free(durations);
  }
  
  completion(YES, filePath, PROCESSING_ERROR);
}

//http://stackoverflow.com/questions/16964366/delaytime-or-unclampeddelaytime-for-gifs
+ (Float32)frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source
{
  Float32 frameDuration = kPINAnimatedImageDefaultDuration;
  NSDictionary *frameProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, index, nil);
  // use unclamped delay time before delay time before default
  NSNumber *unclamedDelayTime = frameProperties[(__bridge NSString *)kCGImagePropertyGIFDictionary][(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime];
  if (unclamedDelayTime) {
    frameDuration = [unclamedDelayTime floatValue];
  } else {
    NSNumber *delayTime = frameProperties[(__bridge NSString *)kCGImagePropertyGIFDictionary][(__bridge NSString *)kCGImagePropertyGIFDelayTime];
    if (delayTime) {
      frameDuration = [delayTime floatValue];
    }
  }
  
  if (frameDuration < kPINAnimatedImageMinimumDuration) {
    frameDuration = kPINAnimatedImageDefaultDuration;
  }
  
  return frameDuration;
}

+ (NSString *)filePathWithTemporaryDirectory:(NSString *)temporaryDirectory UUID:(NSUUID *)UUID count:(NSUInteger)count
{
  NSString *filePath = [temporaryDirectory stringByAppendingPathComponent:[UUID UUIDString]];
  if (count > 0) {
    filePath = [filePath stringByAppendingString:[@(count) stringValue]];
  }
  return filePath;
}

+ (NSFileHandle *)fileHandle:(NSError **)error filePath:(NSString **)filePath temporaryDirectory:(NSString *)temporaryDirectory UUID:(NSUUID *)UUID count:(NSUInteger)count;
{
  NSString *outFilePath = [self filePathWithTemporaryDirectory:temporaryDirectory UUID:UUID count:count];
  NSError *outError = nil;
  NSFileHandle *fileHandle = nil;
  
  if (outError == nil) {
    BOOL success = [[NSFileManager defaultManager] createFileAtPath:outFilePath contents:nil attributes:nil];
    if (success == NO) {
      outError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileCreationError userInfo:nil];
    }
  }
  
  if (outError == nil) {
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:outFilePath];
    if (fileHandle == nil) {
      outError = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileHandleError userInfo:nil];
    }
  }
  
  if (error) {
    *error = outError;
  }
  
  if (filePath) {
    *filePath = outFilePath;
  }
  
  return fileHandle;
}

/**
 PINAnimatedImage file header
 
 Header:
 [version] 2 bytes
 [width] 4 bytes
 [height] 4 bytes
 [loop count] 4 bytes
 [frame count] 4 bytes
 [bitmap info] 4 bytes
 [durations] 4 bytes * frame count
 
 */

+ (NSError *)writeFileHeader:(NSFileHandle *)fileHandle width:(UInt32)width height:(UInt32)height bitsPerPixel:(UInt32)bitsPerPixel loopCount:(UInt32)loopCount frameCount:(UInt32)frameCount bitmapInfo:(UInt32)bitmapInfo durations:(Float32*)durations
{
  NSError *error = nil;
  @try {
    UInt16 version = 2;
    [fileHandle writeData:[NSData dataWithBytes:&version length:sizeof(version)]];
    [fileHandle writeData:[NSData dataWithBytes:&width length:sizeof(width)]];
    [fileHandle writeData:[NSData dataWithBytes:&height length:sizeof(height)]];
    [fileHandle writeData:[NSData dataWithBytes:&bitsPerPixel length:sizeof(bitsPerPixel)]];
    [fileHandle writeData:[NSData dataWithBytes:&loopCount length:sizeof(loopCount)]];
    [fileHandle writeData:[NSData dataWithBytes:&frameCount length:sizeof(frameCount)]];
    [fileHandle writeData:[NSData dataWithBytes:&bitmapInfo length:sizeof(bitmapInfo)]];
    //Since we can't get the length of the durations array from the pointer, we'll just calculate it based on the frameCount.
    [fileHandle writeData:[NSData dataWithBytes:durations length:sizeof(Float32) * frameCount]];
  } @catch (NSException *exception) {
    error = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
  } @finally {}
  return error;
}

/**
 PINAnimatedImage frame file
 [frame count(in file)] 4 bytes
 [frame(s)]
 
 Each frame:
 [duration] 4 bytes
 [frame data] width * height * 4 bytes
 */

+ (NSError *)writeFrameToFile:(NSFileHandle *)fileHandle duration:(Float32)duration frameData:(NSData *)frameData
{
  NSError *error = nil;
  @try {
    [fileHandle writeData:[NSData dataWithBytes:&duration length:sizeof(duration)]];
    [fileHandle writeData:frameData];
  } @catch (NSException *exception) {
    error = [NSError errorWithDomain:kPINAnimatedImageErrorDomain code:PINAnimatedImageErrorFileWrite userInfo:@{@"NSException" : exception}];
  } @finally {}
  return error;
}

@end
