//
//  PINAlternateRepresentationProvider.h
//  Pods
//
//  Created by Garrett Moon on 3/17/16.
//
//

#import <Foundation/Foundation.h>

#import "PINRemoteImageManager.h"

@protocol PINRemoteImageManagerAlternateRepresentationProvider <NSObject>
@required

/**
 @discussion This method will be called with data off the wire or stored in the cache. Return an object to have it returned as the alternativeRepresentation object in the PINRemoteImageManagerResult. @warning this method can be called on the main thread, be careful of doing expensive work.
 */
- (id)alternateRepresentationWithData:(NSData *)data options:(PINRemoteImageManagerDownloadOptions)options;

@end

@interface PINAlternateRepresentationProvider : NSObject <PINRemoteImageManagerAlternateRepresentationProvider>

@end
