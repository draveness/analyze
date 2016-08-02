#!/bin/sh
# Simple script to run the libclosure tests
# Note: to build the testing root, the makefile will ask to authenticate with sudo
# Use the RootsDirectory environment variable to direct the build to somewhere other than /tmp/

RootsDirectory=${RootsDirectory:-/tmp/}
StartingDir="$PWD"
ObjcDir="`dirname $0`"
TestsDir="test/"
cd "$ObjcDir"
# <rdar://problem/6456031> ER: option to not require extra privileges (-nosudo or somesuch)
Buildit="/Network/Servers/xs1/release/bin/buildit -rootsDirectory ${RootsDirectory} -arch i386 -arch x86_64 -project objc4 ."
echo Sudoing for buildit:
sudo $Buildit
XIT=$?
if [[ $XIT == 0 ]]; then
  cd "$TestsDir"
  #ObjcRootPath="$RootsDirectory/objc4.roots/objc4~dst/usr/lib/libobjc.A.dylib"
  #ObjcRootHeaders="$RootsDirectory/objc4.roots/objc4~dst/usr/include/"
  #make HALT=YES OBJC_LIB="$ObjcRootPath" OTHER_CFLAGS="-isystem $ObjcRootHeaders"
  perl test.pl ARCHS=x86_64 OBJC_ROOT="$RootsDirectory/objc4.roots/"
  XIT=`expr $XIT \| $?`
  perl test.pl ARCHS=i386 OBJC_ROOT="$RootsDirectory/objc4.roots/"
  XIT=`expr $XIT \| $?`
  perl test.pl ARCHS=x86_64 GUARDMALLOC=YES OBJC_ROOT="$RootsDirectory/objc4.roots/"
  XIT=`expr $XIT \| $?`
  perl test.pl ARCHS=i386 GUARDMALLOC=YES OBJC_ROOT="$RootsDirectory/objc4.roots/"
  XIT=`expr $XIT \| $?`
  perl test.pl clean
fi
cd "$StartingDir"
exit $XIT