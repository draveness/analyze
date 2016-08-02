
#ifndef _OBJC_CACHE_H
#define _OBJC_CACHE_H

#include "objc-private.h"

__BEGIN_DECLS

extern IMP cache_getImp(Class cls, SEL sel);

extern void cache_fill(Class cls, SEL sel, IMP imp, id receiver);

extern void cache_erase_nolock(Class cls);

extern void cache_delete(Class cls);

extern void cache_collect(bool collectALot);

__END_DECLS

#endif
