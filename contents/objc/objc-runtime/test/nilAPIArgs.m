// TEST_CONFIG

#include "test.h"

#import <objc/runtime.h>

int main() {
    // ensure various bits of API don't crash when tossed nil parameters
    class_conformsToProtocol(nil, nil);
    method_setImplementation(nil, NULL);
  
    succeed(__FILE__);
}
