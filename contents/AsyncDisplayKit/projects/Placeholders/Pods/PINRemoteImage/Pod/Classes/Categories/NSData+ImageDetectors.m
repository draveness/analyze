//
//  NSData+ImageDetectors.m
//  Pods
//
//  Created by Garrett Moon on 11/19/14.
//
//

#import "NSData+ImageDetectors.h"

@implementation NSData (PINImageDetectors)

- (BOOL)pin_isGIF
{
    const NSInteger length = 3;
    Byte firstBytes[length];
    if ([self length] >= length) {
        [self getBytes:&firstBytes length:length];
        //G, I, F
        if (firstBytes[0] == 0x47 && firstBytes[1] == 0x49 && firstBytes[2] == 0x46) {
            return YES;
        }
    }
    return NO;
}

#ifdef PIN_WEBP
- (BOOL)pin_isWebP
{
    const NSInteger length = 12;
    Byte firstBytes[length];
    if ([self length] >= length) {
        [self getBytes:&firstBytes length:length];
        //R, I, F, F, -, -, -, -, W, E, B, P
        if (firstBytes[0] == 0x52 && firstBytes[1] == 0x49 && firstBytes[2] == 0x46 && firstBytes[3] == 0x46 && firstBytes[8] == 0x57 && firstBytes[9] == 0x45 && firstBytes[10] == 0x42 && firstBytes[11] == 0x50) {
            return YES;
        }
    }
    return NO;
}
#endif

@end
