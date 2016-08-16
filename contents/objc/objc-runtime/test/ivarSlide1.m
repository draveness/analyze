#include "test.h"
#include <stdint.h>
#include <objc/runtime.h>

#define OLD 0
#include "ivarSlide.h"

#include "testroot.i"

@implementation Super @end

@implementation ShrinkingSuper @end

@implementation MoreStrongSuper @end
@implementation LessStrongSuper @end
@implementation MoreWeakSuper @end
@implementation MoreWeak2Super @end
@implementation LessWeakSuper @end
@implementation LessWeak2Super @end
@implementation NoGCChangeSuper @end
@implementation RunsOf15 @end
