// TEST_CONFIG OS=iphoneos ARCH=arm64

#include "test.h"

#ifndef __arm64__
#error wrong architecture for TBI hardware feature
#endif

volatile int x = 123456;

int main(void) {
	testassert(*(int *)((unsigned long)&x | 0xFF00000000000000ul) == 123456);
	succeed(__FILE__);
}
