#include "test.h"

OBJC_ROOT_CLASS
@interface Main @end
@implementation Main @end

int main(int argc __attribute__((unused)), char **argv)
{
    succeed(basename(argv[0]));
}
