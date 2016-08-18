//
//  NSData+ImageDetectors.h
//  Pods
//
//  Created by Garrett Moon on 11/19/14.
//
//

#import <Foundation/Foundation.h>

@interface NSData (PINImageDetectors)

- (BOOL)pin_isGIF;
#ifdef PIN_WEBP
- (BOOL)pin_isWebP;
#endif

@end
