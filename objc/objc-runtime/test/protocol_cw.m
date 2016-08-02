// TEST_CFLAGS -Wno-deprecated-declarations

#include "test.h"

#if __OBJC2__

int main()
{
    succeed(__FILE__);
}

#else

// rdar://4951638

#include <string.h>
#include <objc/Protocol.h>

char Protocol_name[] __attribute__((section("__OBJC,__class_names"))) = "Protocol";

struct st {
    void *isa; 
    const char *protocol_name;
    void *protocol_list;
    void *instance_methods;
    void *class_methods;
};

struct st Foo_protocol __attribute__((section("__OBJC,__protocol"))) = { Protocol_name, "Foo", 0, 0, 0 };

int main()
{
    Protocol *foo = objc_getProtocol("Foo");

    testassert(foo == (Protocol *)&Foo_protocol);
    testassert(0 == strcmp("Foo", [foo name]));
    succeed(__FILE__);
}

#endif
