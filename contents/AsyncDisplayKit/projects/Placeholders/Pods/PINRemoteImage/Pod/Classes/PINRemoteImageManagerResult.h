//
//  PINRemoteImageManagerResult.h
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import <Foundation/Foundation.h>

#if PIN_TARGET_IOS
#import <UIKit/UIKit.h>
#elif PIN_TARGET_MAC
#import <Cocoa/Cocoa.h>
#endif

#import "PINRemoteImageMacros.h"
#if USE_FLANIMATED_IMAGE
#import <FLAnimatedImage/FLAnimatedImage.h>
#endif

/** How the image was fetched. */
typedef NS_ENUM(NSUInteger, PINRemoteImageResultType) {
    /** Returned if no image is returned */
    PINRemoteImageResultTypeNone = 0,
    /** Image was fetched from the memory cache */
    PINRemoteImageResultTypeMemoryCache,
    /** Image was fetched from the disk cache */
    PINRemoteImageResultTypeCache,
    /** Image was downloaded */
    PINRemoteImageResultTypeDownload,
    /** Image is progress */
    PINRemoteImageResultTypeProgress,
};

@interface PINRemoteImageManagerResult : NSObject

@property (nonatomic, readonly, strong, nullable) PINImage *image;
@property (nonatomic, readonly, strong, nullable) id alternativeRepresentation;
@property (nonatomic, readonly, assign) NSTimeInterval requestDuration;
@property (nonatomic, readonly, strong, nullable) NSError *error;
@property (nonatomic, readonly, assign) PINRemoteImageResultType resultType;
@property (nonatomic, readonly, strong, nullable) NSUUID *UUID;
@property (nonatomic, readonly, assign) CGFloat renderedImageQuality;

+ (nonnull instancetype)imageResultWithImage:(nullable PINImage *)image
           alternativeRepresentation:(nullable id)alternativeRepresentation
                       requestLength:(NSTimeInterval)requestLength
                               error:(nullable NSError *)error
                          resultType:(PINRemoteImageResultType)resultType
                                UUID:(nullable NSUUID *)uuid;

+ (nonnull instancetype)imageResultWithImage:(nullable PINImage *)image
                   alternativeRepresentation:(nullable id)alternativeRepresentation
                               requestLength:(NSTimeInterval)requestLength
                                       error:(nullable NSError *)error
                                  resultType:(PINRemoteImageResultType)resultType
                                        UUID:(nullable NSUUID *)uuid
                        renderedImageQuality:(CGFloat)renderedImageQuality;

@end
