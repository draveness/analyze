// TEST_CONFIG
// rdar://8052003 rdar://8077031

#include "test.h"

#include <malloc/malloc.h>
#include <objc/runtime.h>

// add SELCOUNT methods to each of CLASSCOUNT classes
#define CLASSCOUNT 100
#define SELCOUNT 200

int main()
{
    int i, j;
    malloc_statistics_t start, end;

    Class root;
    root = objc_allocateClassPair(NULL, "Root", 0);
    objc_registerClassPair(root);

    Class classes[CLASSCOUNT];
    for (i = 0; i < CLASSCOUNT; i++) {
        char *classname;
        asprintf(&classname, "GrP_class_%d", i);
        classes[i] = objc_allocateClassPair(root, classname, 0);
        objc_registerClassPair(classes[i]);
        free(classname);
    }

    SEL selectors[SELCOUNT];
    for (i = 0; i < SELCOUNT; i++) {
        char *selname;
        asprintf(&selname, "GrP_sel_%d", i);
        selectors[i] = sel_registerName(selname);
        free(selname);
    }

    malloc_zone_statistics(NULL, &start);

    for (i = 0; i < CLASSCOUNT; i++) {
        for (j = 0; j < SELCOUNT; j++) {
            class_addMethod(classes[i], selectors[j], (IMP)main, "");
        }
    }

    malloc_zone_statistics(NULL, &end);

    // expected: 3-word method struct plus two other words
    ssize_t expected = (sizeof(void*) * (3+2)) * SELCOUNT * CLASSCOUNT;
    ssize_t actual = end.size_in_use - start.size_in_use;
    testassert(actual < expected * 3);  // allow generous fudge factor

    succeed(__FILE__);
}

