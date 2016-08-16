// TEST_CONFIG

#include "test.h"

// objc.h redefines these calls into bridge casts.
// This test verifies that the function implementations are exported.
__BEGIN_DECLS
extern void *retainedObject(void *arg) __asm__("_objc_retainedObject");
extern void *unretainedObject(void *arg) __asm__("_objc_unretainedObject");
extern void *unretainedPointer(void *arg) __asm__("_objc_unretainedPointer");
__END_DECLS

int main()
{
    void *p = (void*)&main;
    testassert(p == retainedObject(p));
    testassert(p == unretainedObject(p));
    testassert(p == unretainedPointer(p));
    succeed(__FILE__);
}
