#ifndef _OBJC_RT_H_
#define _OBJC_RT_H_

#include <objc/objc-api.h>


typedef struct {
    int count;  // number of pointer pairs that follow
    void *modStart;
    void *modEnd;
    void *protoStart;
    void *protoEnd;
    void *iiStart;
    void *iiEnd;
    void *selrefsStart;
    void *selrefsEnd;
    void *clsrefsStart;
    void *clsrefsEnd;
} objc_sections;

OBJC_EXPORT void *_objc_init_image(HMODULE image, const objc_sections *sects);
OBJC_EXPORT void _objc_load_image(HMODULE image, void *hinfo);
OBJC_EXPORT void _objc_unload_image(HMODULE image, void *hinfo);

#endif
