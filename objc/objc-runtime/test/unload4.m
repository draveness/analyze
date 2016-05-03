// unload4: contains some objc metadata other than imageinfo
// libobjc must keep it open

#if __OBJC2__
int fake2 __attribute__((section("__DATA,__objc_foo"))) = 0;
#else
int fake2 __attribute__((section("__OBJC,__foo"))) = 0;
#endif

// getsectiondata() falls over if __TEXT has no contents
const char *unload4 = "unload4";
