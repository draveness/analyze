// TEST_CONFIG

#include "test.h"
#include <Foundation/NSObject.h>
#include <objc/runtime.h>

#undef SUPPORT_NONPOINTER_ISA  // remove test.h's definition
#include "../runtime/objc-config.h"

int main() {
  unsigned i;
  Class c = [NSObject class];
  unsigned numMethods;
  Method *methods = class_copyMethodList(c, &numMethods);

  for (i=0; i<numMethods; ++i) {
      // <rdar://problem/6190950> method_getName crash on NSObject method when GC is enabled
      SEL aMethod;
      aMethod = method_getName(methods[i]);
#if defined(kIgnore)
      if (aMethod == (SEL)kIgnore)
	  fail(__FILE__);
#endif
  }

  succeed(__FILE__);
}
