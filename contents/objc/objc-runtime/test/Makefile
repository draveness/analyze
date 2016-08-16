# quick test
all:
	perl test.pl $(MAKEFLAGS)

# default-arch but otherwise comprehensive test for buildbot
buildbot: 
	perl test.pl $(MAKEFLAGS) MEM=mrc,arc,gc CC=clang LANGUAGE=objc,objc++

# comprehensive tests
mac macos macosx:
	perl test.pl $(MAKEFLAGS) ARCH=x86_64,i386 MEM=mrc,arc,gc CC=clang LANGUAGE=objc,objc++

iphonesimulator:
	perl test.pl $(MAKEFLAGS) ARCH=i386 SDK=iphonesimulator MEM=mrc,arc CC=clang LANGUAGE=objc,objc++

iphoneos:
	perl test.pl $(MAKEFLAGS) ARCH=armv6,armv7 SDK=iphoneos MEM=mrc,arc CC=clang LANGUAGE=objc,objc++

clean: 
	@ perl test.pl clean
