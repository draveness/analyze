//
//  UIImage+DecodedImage.h
//  Pods
//
//  Created by Garrett Moon on 11/19/14.
//
//

#import <Foundation/Foundation.h>

#if PIN_TARGET_IOS
#import <UIKit/UIKit.h>
#elif PIN_TARGET_MAC
#import <Cocoa/Cocoa.h>
#endif

#import "PINRemoteImageMacros.h"

#if !PIN_TARGET_IOS
@interface NSImage (PINiOSMapping)

@property(nonatomic, readonly, nullable) CGImageRef CGImage;

+ (nullable NSImage *)imageWithData:(nonnull NSData *)imageData;
+ (nullable NSImage *)imageWithContentsOfFile:(nonnull NSString *)path;
+ (nonnull NSImage *)imageWithCGImage:(nonnull CGImageRef)imageRef;

@end
#endif

NSData * __nullable PINImageJPEGRepresentation(PINImage * __nonnull image, CGFloat compressionQuality);
NSData * __nullable PINImagePNGRepresentation(PINImage * __nonnull image);

@interface PINImage (PINDecodedImage)

+ (nullable PINImage *)pin_decodedImageWithData:(nonnull NSData *)data;
+ (nullable PINImage *)pin_decodedImageWithData:(nonnull NSData *)data skipDecodeIfPossible:(BOOL)skipDecodeIfPossible;
+ (nullable PINImage *)pin_decodedImageWithCGImageRef:(nonnull CGImageRef)imageRef;
#if PIN_TARGET_IOS
+ (nullable PINImage *)pin_decodedImageWithCGImageRef:(nonnull CGImageRef)imageRef orientation:(UIImageOrientation) orientation;
#endif

@end
