//
//  PINAlternateRepresentationProvider.m
//  Pods
//
//  Created by Garrett Moon on 3/17/16.
//
//

#import "PINAlternateRepresentationProvider.h"

#import "NSData+ImageDetectors.h"
#if USE_FLANIMATED_IMAGE
#import <FLAnimatedImage/FLAnimatedImage.h>
#endif

@implementation PINAlternateRepresentationProvider

- (id)alternateRepresentationWithData:(NSData *)data options:(PINRemoteImageManagerDownloadOptions)options
{
#if USE_FLANIMATED_IMAGE
    if ([data pin_isGIF]) {
        return [FLAnimatedImage animatedImageWithGIFData:data];
    }
#endif
    return nil;
}

@end
