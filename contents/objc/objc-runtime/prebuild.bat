@echo off

echo prebuild: installing headers
xcopy /Y "%ProjectDir%runtime\objc.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\objc-api.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\objc-auto.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\objc-exception.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\message.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\runtime.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\hashtable.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\hashtable2.h" "%DSTROOT%\AppleInternal\include\objc\"
xcopy /Y "%ProjectDir%runtime\maptable.h" "%DSTROOT%\AppleInternal\include\objc\"

echo prebuild: setting version
version
