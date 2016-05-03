// TEST_CFLAGS

#include <Foundation/NSObject.h>
#include <objc/runtime.h>
#include <objc/objc-internal.h>

#include "test.h"

int main()
{
    // rdar://8350188 External references (handles)

    id object = [NSObject new];
    testassert(object);
    
    // STRONG
    objc_xref_t xref = _object_addExternalReference(object, OBJC_XREF_STRONG);
    testassert(xref);
    testassert(_object_readExternalReference(xref) == object);
    _object_removeExternalReference(xref);
    // TODO: expect a crash if a stale xref is used.
    
    // WEAK
    xref = _object_addExternalReference(object, OBJC_XREF_WEAK);
    testassert(xref);
    testassert(_object_readExternalReference(xref) == object);
    _object_removeExternalReference(xref);
    
    RELEASE_VAR(object);

    succeed(__FILE__);
}
