//
//  main.m
//  debug-objc
//
//  Created by Draveness on 2/24/16.
//
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "XXObject.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {

        XXObject *obj = [[XXObject alloc] init];
        obj.strongObject = @300;

        [obj class];
    }
    return 0;
}
