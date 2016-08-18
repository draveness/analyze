//
//  PINProgressiveImage.m
//  Pods
//
//  Created by Garrett Moon on 2/9/15.
//
//

#import "PINProgressiveImage.h"

#import <ImageIO/ImageIO.h>
#import <Accelerate/Accelerate.h>

#import "PINRemoteImage.h"
#import "PINImage+DecodedImage.h"

@interface PINProgressiveImage ()

@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, assign) int64_t expectedNumberOfBytes;
@property (nonatomic, assign) CGImageSourceRef imageSource;
@property (nonatomic, assign) CGSize size;
@property (nonatomic, assign) BOOL isProgressiveJPEG;
@property (nonatomic, assign) NSUInteger currentThreshold;
@property (nonatomic, assign) float bytesPerSecond;
@property (nonatomic, assign) NSUInteger scannedByte;
@property (nonatomic, assign) NSInteger sosCount;
@property (nonatomic, strong) NSLock *lock;
#if DEBUG
@property (nonatomic, assign) CFTimeInterval scanTime;
#endif

@end

@implementation PINProgressiveImage

@synthesize progressThresholds = _progressThresholds;
@synthesize estimatedRemainingTimeThreshold = _estimatedRemainingTimeThreshold;
@synthesize startTime = _startTime;

- (instancetype)init
{
    if (self = [super init]) {
        self.lock = [[NSLock alloc] init];
        self.lock.name = @"PINProgressiveImage";
        
        _imageSource = CGImageSourceCreateIncremental(NULL);;
        self.size = CGSizeZero;
        self.isProgressiveJPEG = NO;
        self.currentThreshold = 0;
        self.progressThresholds = @[@0.00, @0.35, @0.65];
        self.startTime = CACurrentMediaTime();
        self.estimatedRemainingTimeThreshold = -1;
        self.sosCount = 0;
        self.scannedByte = 0;
#if DEBUG
        self.scanTime = 0;
#endif
    }
    return self;
}

- (void)dealloc
{
    [self.lock lock];
        if (self.imageSource) {
            CFRelease(_imageSource);
        }
    [self.lock unlock];
}

#pragma mark - public

- (void)setProgressThresholds:(NSArray *)progressThresholds
{
    [self.lock lock];
        _progressThresholds = [progressThresholds copy];
    [self.lock unlock];
}

- (NSArray *)progressThresholds
{
    [self.lock lock];
        NSArray *progressThresholds = _progressThresholds;
    [self.lock unlock];
    return progressThresholds;
}

- (void)setEstimatedRemainingTimeThreshold:(CFTimeInterval)estimatedRemainingTimeThreshold
{
    [self.lock lock];
        _estimatedRemainingTimeThreshold = estimatedRemainingTimeThreshold;
    [self.lock unlock];
}

- (CFTimeInterval)estimatedRemainingTimeThreshold
{
    [self.lock lock];
        CFTimeInterval estimatedRemainingTimeThreshold = _estimatedRemainingTimeThreshold;
    [self.lock unlock];
    return estimatedRemainingTimeThreshold;
}

- (void)setStartTime:(CFTimeInterval)startTime
{
    [self.lock lock];
        _startTime = startTime;
    [self.lock unlock];
}

- (CFTimeInterval)startTime
{
    [self.lock lock];
        CFTimeInterval startTime = _startTime;
    [self.lock unlock];
    return startTime;
}

- (void)updateProgressiveImageWithData:(NSData *)data expectedNumberOfBytes:(int64_t)expectedNumberOfBytes
{
    [self.lock lock];
        if (self.mutableData == nil) {
            NSUInteger bytesToAlloc = 0;
            if (expectedNumberOfBytes > 0) {
                bytesToAlloc = (NSUInteger)expectedNumberOfBytes;
            }
            self.mutableData = [[NSMutableData alloc] initWithCapacity:bytesToAlloc];
            self.expectedNumberOfBytes = expectedNumberOfBytes;
        }
        [self.mutableData appendData:data];
        
        while ([self hasCompletedFirstScan] == NO && self.scannedByte < self.mutableData.length) {
    #if DEBUG
            CFTimeInterval start = CACurrentMediaTime();
    #endif
            NSUInteger startByte = self.scannedByte;
            if (startByte > 0) {
                startByte--;
            }
            if ([self scanForSOSinData:self.mutableData startByte:startByte scannedByte:&_scannedByte]) {
                self.sosCount++;
            }
    #if DEBUG
            CFTimeInterval total = CACurrentMediaTime() - start;
            self.scanTime += total;
    #endif
        }
        
        if (self.imageSource) {
            CGImageSourceUpdateData(self.imageSource, (CFDataRef)self.mutableData, NO);
        }
    [self.lock unlock];
}

- (PINImage *)currentImageBlurred:(BOOL)blurred maxProgressiveRenderSize:(CGSize)maxProgressiveRenderSize renderedImageQuality:(out CGFloat *)renderedImageQuality
{
    [self.lock lock];
        if (self.imageSource == nil) {
            [self.lock unlock];
            return nil;
        }
        
        if (self.currentThreshold == _progressThresholds.count) {
            [self.lock unlock];
            return nil;
        }
        
        if (_estimatedRemainingTimeThreshold > 0 && self.estimatedRemainingTime < _estimatedRemainingTimeThreshold) {
            [self.lock unlock];
            return nil;
        }
        
        if ([self hasCompletedFirstScan] == NO) {
            [self.lock unlock];
            return nil;
        }
        
    #if DEBUG
        if (self.scanTime > 0) {
            PINLog(@"scan time: %f", self.scanTime);
            self.scanTime = 0;
        }
    #endif
        
        PINImage *currentImage = nil;
        
        //Size information comes after JFIF so jpeg properties should be available at or before size?
        if (self.size.width <= 0 || self.size.height <= 0) {
            //attempt to get size info
            NSDictionary *imageProperties = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(self.imageSource, 0, NULL));
            CGSize size = self.size;
            if (size.width <= 0 && imageProperties[(NSString *)kCGImagePropertyPixelWidth]) {
                size.width = [imageProperties[(NSString *)kCGImagePropertyPixelWidth] floatValue];
            }
            
            if (size.height <= 0 && imageProperties[(NSString *)kCGImagePropertyPixelHeight]) {
                size.height = [imageProperties[(NSString *)kCGImagePropertyPixelHeight] floatValue];
            }
            
            self.size = size;
            
            NSDictionary *jpegProperties = imageProperties[(NSString *)kCGImagePropertyJFIFDictionary];
            NSNumber *isProgressive = jpegProperties[(NSString *)kCGImagePropertyJFIFIsProgressive];
            self.isProgressiveJPEG = jpegProperties && [isProgressive boolValue];
        }
    
        if (self.size.width > maxProgressiveRenderSize.width || self.size.height > maxProgressiveRenderSize.height) {
            [self.lock unlock];
            return nil;
        }
        
        float progress = 0;
        if (self.expectedNumberOfBytes > 0) {
            progress = (float)self.mutableData.length / (float)self.expectedNumberOfBytes;
        }
        
        //Don't bother if we're basically done
        if (progress >= 0.99) {
            [self.lock unlock];
            return nil;
        }
    
        if (self.isProgressiveJPEG && self.size.width > 0 && self.size.height > 0 && progress > [_progressThresholds[self.currentThreshold] floatValue]) {
            while (self.currentThreshold < _progressThresholds.count && progress > [_progressThresholds[self.currentThreshold] floatValue]) {
                self.currentThreshold++;
            }
            PINLog(@"Generating preview image");
            CGImageRef image = CGImageSourceCreateImageAtIndex(self.imageSource, 0, NULL);
            if (image) {
                if (blurred) {
                    currentImage = [self postProcessImage:[PINImage imageWithCGImage:image] withProgress:progress];
                } else {
                    currentImage = [PINImage imageWithCGImage:image];
                }
                CGImageRelease(image);
                if (renderedImageQuality) {
                    *renderedImageQuality = progress;
                }
            }
        }
    
    [self.lock unlock];
    return currentImage;
}

- (NSData *)data
{
    [self.lock lock];
    NSData *data = [self.mutableData copy];
    [self.lock unlock];
    return data;
}

#pragma mark - private

//Must be called within lock
- (BOOL)scanForSOSinData:(NSData *)data startByte:(NSUInteger)startByte scannedByte:(NSUInteger *)scannedByte
{
    //check if we have a complete scan
    Byte scanMarker[2];
    //SOS marker
    scanMarker[0] = 0xFF;
    scanMarker[1] = 0xDA;
    
    //scan one byte back in case we only got half the SOS on the last data append
    NSRange scanRange;
    scanRange.location = startByte;
    scanRange.length = data.length - scanRange.location;
    NSRange sosRange = [data rangeOfData:[NSData dataWithBytes:scanMarker length:2] options:0 range:scanRange];
    if (sosRange.location != NSNotFound) {
        if (scannedByte) {
            *scannedByte = NSMaxRange(sosRange);
        }
        return YES;
    }
    if (scannedByte) {
        *scannedByte = NSMaxRange(scanRange);
    }
    return NO;
}

//Must be called within lock
- (BOOL)hasCompletedFirstScan
{
    return self.sosCount >= 2;
}

//Must be called within lock
- (float)bytesPerSecond
{
    CFTimeInterval length = CACurrentMediaTime() - _startTime;
    return self.mutableData.length / length;
}

//Must be called within lock
- (CFTimeInterval)estimatedRemainingTime
{
    if (self.expectedNumberOfBytes < 0) {
        return MAXFLOAT;
    }
    
    NSUInteger remainingBytes = (NSUInteger)self.expectedNumberOfBytes - self.mutableData.length;
    if (remainingBytes == 0) {
        return 0;
    }
    
    float bytesPerSecond = self.bytesPerSecond;
    if (bytesPerSecond == 0) {
        return MAXFLOAT;
    }
    return remainingBytes / self.bytesPerSecond;
}

//Must be called within lock
//Heavily cribbed from https://developer.apple.com/library/ios/samplecode/UIImageEffects/Listings/UIImageEffects_UIImageEffects_m.html#//apple_ref/doc/uid/DTS40013396-UIImageEffects_UIImageEffects_m-DontLinkElementID_9
- (PINImage *)postProcessImage:(PINImage *)inputImage withProgress:(float)progress
{
    PINImage *outputImage = nil;
    CGImageRef inputImageRef = CGImageRetain(inputImage.CGImage);
    if (inputImageRef == nil) {
        return nil;
    }
    
    CGSize inputSize = inputImage.size;
    if (inputSize.width < 1 ||
        inputSize.height < 1) {
        CGImageRelease(inputImageRef);
        return nil;
    }

#if PIN_TARGET_IOS
    CGFloat imageScale = inputImage.scale;
#elif PIN_TARGET_MAC
    // TODO: What scale factor should be used here?
    CGFloat imageScale = [[NSScreen mainScreen] backingScaleFactor];
#endif
    
    CGFloat radius = (inputImage.size.width / 25.0) * MAX(0, 1.0 - progress);
    radius *= imageScale;
    
    //we'll round the radius to a whole number below anyway,
    if (radius < FLT_EPSILON) {
        CGImageRelease(inputImageRef);
        return inputImage;
    }
    
    CGContextRef ctx;
#if PIN_TARGET_IOS
    UIGraphicsBeginImageContextWithOptions(inputSize, YES, imageScale);
    ctx = UIGraphicsGetCurrentContext();
#elif PIN_TARGET_MAC
    ctx = CGBitmapContextCreate(0, inputSize.width, inputSize.height, 8, 0, [NSColorSpace genericRGBColorSpace].CGColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
#endif
    
    if (ctx) {
#if PIN_TARGET_IOS
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextTranslateCTM(ctx, 0, -inputSize.height);
#endif
        
        vImage_Buffer effectInBuffer;
        vImage_Buffer scratchBuffer;
        
        vImage_Buffer *inputBuffer;
        vImage_Buffer *outputBuffer;
        
        vImage_CGImageFormat format = {
            .bitsPerComponent = 8,
            .bitsPerPixel = 32,
            .colorSpace = NULL,
            // (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)
            // requests a BGRA buffer.
            .bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
            .version = 0,
            .decode = NULL,
            .renderingIntent = kCGRenderingIntentDefault
        };
        
        vImage_Error e = vImageBuffer_InitWithCGImage(&effectInBuffer, &format, NULL, inputImage.CGImage, kvImagePrintDiagnosticsToConsole);
        if (e == kvImageNoError)
        {
            e = vImageBuffer_Init(&scratchBuffer, effectInBuffer.height, effectInBuffer.width, format.bitsPerPixel, kvImageNoFlags);
            if (e == kvImageNoError) {
                inputBuffer = &effectInBuffer;
                outputBuffer = &scratchBuffer;
                
                // A description of how to compute the box kernel width from the Gaussian
                // radius (aka standard deviation) appears in the SVG spec:
                // http://www.w3.org/TR/SVG/filters.html#feGaussianBlurElement
                //
                // For larger values of 's' (s >= 2.0), an approximation can be used: Three
                // successive box-blurs build a piece-wise quadratic convolution kernel, which
                // approximates the Gaussian kernel to within roughly 3%.
                //
                // let d = floor(s * 3*sqrt(2*pi)/4 + 0.5)
                //
                // ... if d is odd, use three box-blurs of size 'd', centered on the output pixel.
                //
                if (radius - 2. < __FLT_EPSILON__)
                    radius = 2.;
                uint32_t wholeRadius = floor((radius * 3. * sqrt(2 * M_PI) / 4 + 0.5) / 2);
                
                wholeRadius |= 1; // force wholeRadius to be odd so that the three box-blur methodology works.
                
                //calculate the size necessary for vImageBoxConvolve_ARGB8888, this does not actually do any operations.
                NSInteger tempBufferSize = vImageBoxConvolve_ARGB8888(inputBuffer, outputBuffer, NULL, 0, 0, wholeRadius, wholeRadius, NULL, kvImageGetTempBufferSize | kvImageEdgeExtend);
                void *tempBuffer = malloc(tempBufferSize);
                
                if (tempBuffer) {
                    //errors can be ignored because we've passed in allocated memory
                    vImageBoxConvolve_ARGB8888(inputBuffer, outputBuffer, tempBuffer, 0, 0, wholeRadius, wholeRadius, NULL, kvImageEdgeExtend);
                    vImageBoxConvolve_ARGB8888(outputBuffer, inputBuffer, tempBuffer, 0, 0, wholeRadius, wholeRadius, NULL, kvImageEdgeExtend);
                    vImageBoxConvolve_ARGB8888(inputBuffer, outputBuffer, tempBuffer, 0, 0, wholeRadius, wholeRadius, NULL, kvImageEdgeExtend);
                    
                    free(tempBuffer);
                    
                    //switch input and output
                    vImage_Buffer *temp = inputBuffer;
                    inputBuffer = outputBuffer;
                    outputBuffer = temp;
                    
                    CGImageRef effectCGImage = vImageCreateCGImageFromBuffer(inputBuffer, &format, &cleanupBuffer, NULL, kvImageNoAllocate, NULL);
                    if (effectCGImage == NULL) {
                        //if creating the cgimage failed, the cleanup buffer on input buffer will not be called, we must dealloc ourselves
                        free(inputBuffer->data);
                    } else {
                        // draw effect image
                        CGContextSaveGState(ctx);
                        CGContextDrawImage(ctx, CGRectMake(0, 0, inputSize.width, inputSize.height), effectCGImage);
                        CGContextRestoreGState(ctx);
                        CGImageRelease(effectCGImage);
                    }
                    
                    // Cleanup
                    free(outputBuffer->data);
#if PIN_TARGET_IOS
                    outputImage = UIGraphicsGetImageFromCurrentImageContext();
#elif PIN_TARGET_MAC
                    CGImageRef outputImageRef = CGBitmapContextCreateImage(ctx);
                    outputImage = [[NSImage alloc] initWithCGImage:outputImageRef size:inputSize];
                    CFRelease(outputImageRef);
#endif
                    
                }
            } else {
                if (scratchBuffer.data) {
                    free(scratchBuffer.data);
                }
                free(effectInBuffer.data);
            }
        } else {
            if (effectInBuffer.data) {
                free(effectInBuffer.data);
            }
        }
    }
    
#if PIN_TARGET_IOS
    UIGraphicsEndImageContext();
#endif

    CGImageRelease(inputImageRef);
    
    return outputImage;
}

//  Helper function to handle deferred cleanup of a buffer.
static void cleanupBuffer(void *userData, void *buf_data)
{
    free(buf_data);
}

@end
