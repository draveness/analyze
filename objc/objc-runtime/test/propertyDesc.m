// TEST_CONFIG

#include "test.h"
#include "testroot.i"
#include <stdint.h>
#include <string.h>
#include <objc/runtime.h>

struct objc_property {
    const char *name;
    const char *attr;
};

#define checkattrlist(attrs, attrcount, target)                         \
    do {                                                                \
        if (target > 0) {                                               \
            testassert(attrs);                                          \
            testassert(attrcount == target);                            \
            testassert(malloc_size(attrs) >=                            \
                       (1+target) * sizeof(objc_property_attribute_t)); \
            testassert(attrs[target].name == NULL);                     \
            testassert(attrs[target].value == NULL);                    \
        } else {                                                        \
            testassert(!attrs);                                         \
            testassert(attrcount == 0);                                 \
        }                                                               \
    } while (0)

#define checkattr(attrs, i, n, v)                                       \
    do {                                                                \
        char *attrsstart = (char *)attrs;                               \
        char *attrsend = (char *)attrs + malloc_size(attrs);            \
        testassert((char*)(attrs+i+1) <= attrsend);                     \
        testassert(attrs[i].name >= attrsstart);                        \
        testassert(attrs[i].value >= attrsstart);                       \
        testassert(attrs[i].name + strlen(attrs[i].name) + 1 <= attrsend); \
        testassert(attrs[i].value + strlen(attrs[i].value) + 1 <= attrsend); \
        if (n) testassert(0 == strcmp(attrs[i].name, n));               \
        else testassert(attrs[i].name == NULL);                         \
        if (v) testassert(0 == strcmp(attrs[i].value, v));              \
        else testassert(attrs[i].value == NULL);                        \
    } while (0)

int main()
{
    char *value;
    objc_property_attribute_t *attrs;
    unsigned int attrcount;

    // STRING TO ATTRIBUTE LIST (property_copyAttributeList)

    struct objc_property prop;
    prop.name = "test";

    // null property
    attrcount = 42;
    attrs = property_copyAttributeList(NULL, &attrcount);
    testassert(!attrs);
    testassert(attrcount == 0);
    attrs = property_copyAttributeList(NULL, NULL);
    testassert(!attrs);

    // null attributes
    attrcount = 42;
    prop.attr = NULL;
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 0);
    attrs = property_copyAttributeList(&prop, NULL);
    testassert(!attrs);

    // empty attributes
    attrcount = 42;
    prop.attr = "";
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 0);
    attrs = property_copyAttributeList(&prop, NULL);
    testassert(!attrs);

    // commas only
    attrcount = 42;
    prop.attr = ",,,";
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 0);
    attrs = property_copyAttributeList(&prop, NULL);
    testassert(!attrs);

    // long and short names, with and without values
    attrcount = 42;
    prop.attr = "?XX,',\"?!?!\"YY,\"''''\"";
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 4);
    checkattr(attrs, 0, "?", "XX");
    checkattr(attrs, 1, "'", "");
    checkattr(attrs, 2, "?!?!", "YY");
    checkattr(attrs, 3, "''''", "");
    free(attrs);
    
    // all recognized attributes simultaneously, values with quotes
    attrcount = 42;
    prop.attr = "T11,V2222,S333333\",G\"44444444,W,P,D,R,N,C,&";
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 11);
    checkattr(attrs, 0, "T", "11");
    checkattr(attrs, 1, "V", "2222");
    checkattr(attrs, 2, "S", "333333\"");
    checkattr(attrs, 3, "G", "\"44444444");
    checkattr(attrs, 4, "W", "");
    checkattr(attrs, 5, "P", "");
    checkattr(attrs, 6, "D", "");
    checkattr(attrs, 7, "R", "");
    checkattr(attrs, 8, "N", "");
    checkattr(attrs, 9, "C", "");
    checkattr(attrs,10, "&", "");
    free(attrs);

    // kitchen sink
    attrcount = 42;
    prop.attr = "W,T11,P,?XX,D,V2222,R,',N,S333333\",C,\"?!?!\"YY,&,G\"44444444,\"''''\"";
    attrs = property_copyAttributeList(&prop, &attrcount);
    checkattrlist(attrs, attrcount, 15); 
    checkattr(attrs, 0, "W", "");
    checkattr(attrs, 1, "T", "11");
    checkattr(attrs, 2, "P", "");
    checkattr(attrs, 3, "?", "XX");
    checkattr(attrs, 4, "D", "");
    checkattr(attrs, 5, "V", "2222");
    checkattr(attrs, 6, "R", "");
    checkattr(attrs, 7, "'", "");
    checkattr(attrs, 8, "N", "");
    checkattr(attrs, 9, "S", "333333\"");
    checkattr(attrs,10, "C", "");
    checkattr(attrs,11, "?!?!", "YY");
    checkattr(attrs,12, "&", "");
    checkattr(attrs,13, "G", "\"44444444");
    checkattr(attrs,14, "''''", "");
    free(attrs);

    // SEARCH ATTRIBUTE LIST (property_copyAttributeValue)

    // null property, null name, empty name
    value = property_copyAttributeValue(NULL, NULL);
    testassert(!value);
    value = property_copyAttributeValue(NULL, "foo");
    testassert(!value);
    value = property_copyAttributeValue(NULL, "");
    testassert(!value);
    value = property_copyAttributeValue(&prop, NULL);
    testassert(!value);
    value = property_copyAttributeValue(&prop, "");
    testassert(!value);

    // null attributes, empty attributes
    prop.attr = NULL;
    value = property_copyAttributeValue(&prop, "foo");
    testassert(!value);
    prop.attr = "";
    value = property_copyAttributeValue(&prop, "foo");
    testassert(!value);

    // long and short names, with and without values
    prop.attr = "?XX,',\"?!?!\"YY,\"''''\"";
    value = property_copyAttributeValue(&prop, "missing");
    testassert(!value);
    value = property_copyAttributeValue(&prop, "X");
    testassert(!value);
    value = property_copyAttributeValue(&prop, "\"");
    testassert(!value);
    value = property_copyAttributeValue(&prop, "'''");
    testassert(!value);
    value = property_copyAttributeValue(&prop, "'''''");
    testassert(!value);

    value = property_copyAttributeValue(&prop, "?");
    testassert(0 == strcmp(value, "XX"));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "'");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "?!?!");
    testassert(0 == strcmp(value, "YY"));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "''''");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);

    // all recognized attributes simultaneously, values with quotes
    prop.attr = "T11,V2222,S333333\",G\"44444444,W,P,D,R,N,C,&";
    value = property_copyAttributeValue(&prop, "T");
    testassert(0 == strcmp(value, "11"));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "V");
    testassert(0 == strcmp(value, "2222"));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "S");
    testassert(0 == strcmp(value, "333333\""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "G");
    testassert(0 == strcmp(value, "\"44444444"));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "W");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "P");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "D");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "R");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "N");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "C");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);
    value = property_copyAttributeValue(&prop, "&");
    testassert(0 == strcmp(value, ""));
    testassert(malloc_size(value) >= 1 + strlen(value));
    free(value);

    // ATTRIBUTE LIST TO STRING (class_addProperty)

    BOOL ok;
    objc_property_t prop2;

    // null name
    ok = class_addProperty([TestRoot class], NULL, (objc_property_attribute_t *)1, 1);
    testassert(!ok);

    // null description
    ok = class_addProperty([TestRoot class], "test-null-desc", NULL, 0);
    testassert(ok);
    prop2 = class_getProperty([TestRoot class], "test-null-desc");
    testassert(prop2);
    testassert(0 == strcmp(property_getAttributes(prop2), ""));

    // empty description
    ok = class_addProperty([TestRoot class], "test-empty-desc", (objc_property_attribute_t*)1, 0);
    testassert(ok);
    prop2 = class_getProperty([TestRoot class], "test-empty-desc");
    testassert(prop2);
    testassert(0 == strcmp(property_getAttributes(prop2), ""));

    // long and short names, with and without values
    objc_property_attribute_t attrs2[] = {
        { "!", NULL }, 
        { "?", "XX" }, 
        { "'", "" }, 
        { "?!?!", "YY" }, 
        { "''''", "" }
    };
    ok = class_addProperty([TestRoot class], "test-unrecognized", attrs2, 5);
    testassert(ok);
    prop2 = class_getProperty([TestRoot class], "test-unrecognized");
    testassert(prop2);
    testassert(0 == strcmp(property_getAttributes(prop2), "?XX,',\"?!?!\"YY,\"''''\""));

    // all recognized attributes simultaneously, values with quotes
    objc_property_attribute_t attrs3[] = {
        { "&", "" }, 
        { "C", "" }, 
        { "N", "" }, 
        { "R", "" }, 
        { "D", "" }, 
        { "P", "" }, 
        { "W", "" }, 
        { "G", "\"44444444" }, 
        { "S", "333333\"" }, 
        { "V", "2222" }, 
        { "T", "11" }, 
    };
    ok = class_addProperty([TestRoot class], "test-recognized", attrs3, 11);
    testassert(ok);
    prop2 = class_getProperty([TestRoot class], "test-recognized");
    testassert(prop2);
    testassert(0 == strcmp(property_getAttributes(prop2), 
                           "&,C,N,R,D,P,W,G\"44444444,S333333\",V2222,T11"));

    // kitchen sink
    objc_property_attribute_t attrs4[] = {
        { "&", "" }, 
        { "C", "" }, 
        { "N", "" }, 
        { "R", "" }, 
        { "D", "" }, 
        { "P", "" }, 
        { "W", "" }, 
        { "!", NULL }, 
        { "G", "\"44444444" }, 
        { "S", "333333\"" }, 
        { "V", "2222" }, 
        { "T", "11" }, 
        { "?", "XX" }, 
        { "'", "" }, 
        { "?!?!", "YY" }, 
        { "''''", "" }
    };
    ok = class_addProperty([TestRoot class], "test-sink", attrs4, 16);
    testassert(ok);
    prop2 = class_getProperty([TestRoot class], "test-sink");
    testassert(prop2);
    testassert(0 == strcmp(property_getAttributes(prop2), 
                           "&,C,N,R,D,P,W,G\"44444444,S333333\",V2222,T11,"
                           "?XX,',\"?!?!\"YY,\"''''\""));

    succeed(__FILE__);
}
