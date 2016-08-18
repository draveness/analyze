//
//  UIImage+WebP.m
//  Pods
//
//  Created by Garrett Moon on 11/18/14.
//
//

#import "PINImage+WebP.h"

#ifdef PIN_WEBP
#if !COCOAPODS
#import "webp/decode.h"
#else
#import "libwebp/webp/decode.h"
#endif

static void releaseData(void *info, const void *data, size_t size)
{
    free((void *)data);
}

@implementation PINImage (PINWebP)

+ (PINImage *)pin_imageWithWebPData:(NSData *)webPData
{
    WebPBitstreamFeatures features;
    if (WebPGetFeatures([webPData bytes], [webPData length], &features) == VP8_STATUS_OK) {
        // Decode the WebP image data into a RGBA value array
        int height, width;
        uint8_t *data = NULL;
        int pixelLength = 0;
        
        if (features.has_alpha) {
            data = WebPDecodeRGBA([webPData bytes], [webPData length], &width, &height);
            pixelLength = 4;
        } else {
            data = WebPDecodeRGB([webPData bytes], [webPData length], &width, &height);
            pixelLength = 3;
        }
        
        if (data) {
            CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, width * height * pixelLength, releaseData);
            
            CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
            CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
            
            if (features.has_alpha) {
                bitmapInfo |= kCGImageAlphaLast;
            } else {
                bitmapInfo |= kCGImageAlphaNone;
            }
            
            CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
            CGImageRef imageRef = CGImageCreate(width,
                                                height,
                                                8,
                                                8 * pixelLength,
                                                pixelLength * width,
                                                colorSpaceRef,
                                                bitmapInfo,
                                                provider,
                                                NULL,
                                                NO,
                                                renderingIntent);
            
            PINImage *image = nil;
#if PIN_TARGET_IOS
            image = [UIImage imageWithCGImage:imageRef];
#elif PIN_TARGET_MAC
            image = [[self alloc] initWithCGImage:imageRef size:CGSizeZero];
#endif
            
            CGImageRelease(imageRef);
            CGColorSpaceRelease(colorSpaceRef);
            CGDataProviderRelease(provider);
            
            return image;
        }
    }
    return nil;
}

@end

#endif
