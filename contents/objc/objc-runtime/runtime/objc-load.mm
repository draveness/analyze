/*
 * Copyright (c) 1999-2001, 2004-2007 Apple Inc.  All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 *	objc-load.m
 *	Copyright 1988-1996, NeXT Software, Inc.
 *	Author:	s. naroff
 *
 */

#include "objc-private.h"
#include "objc-load.h"

#if !__OBJC2__  &&  !TARGET_OS_WIN32

extern void (*callbackFunction)( Class, Category );


/**********************************************************************************
* objc_loadModule.
*
* NOTE: Loading isn't really thread safe.  If a load message recursively calls
* objc_loadModules() both sets will be loaded correctly, but if the original
* caller calls objc_unloadModules() it will probably unload the wrong modules.
* If a load message calls objc_unloadModules(), then it will unload
* the modules currently being loaded, which will probably cause a crash.
*
* Error handling is still somewhat crude.  If we encounter errors while
* linking up classes or categories, we will not recover correctly.
*
* I removed attempts to lock the class hashtable, since this introduced
* deadlock which was hard to remove.  The only way you can get into trouble
* is if one thread loads a module while another thread tries to access the
* loaded classes (using objc_lookUpClass) before the load is complete.
**********************************************************************************/
int objc_loadModule(char *moduleName, void (*class_callback) (Class, Category), int *errorCode)
{
    int								successFlag = 1;
    int								locErrorCode;
    NSObjectFileImage				objectFileImage;
    NSObjectFileImageReturnCode		code;

    // So we don't have to check this everywhere
    if (errorCode == NULL)
        errorCode = &locErrorCode;

    if (moduleName == NULL)
    {
        *errorCode = NSObjectFileImageInappropriateFile;
        return 0;
    }

    if (_dyld_present () == 0)
    {
        *errorCode = NSObjectFileImageFailure;
        return 0;
    }

    callbackFunction = class_callback;
    code = NSCreateObjectFileImageFromFile (moduleName, &objectFileImage);
    if (code != NSObjectFileImageSuccess)
    {
        *errorCode = code;
        return 0;
    }

    if (NSLinkModule(objectFileImage, moduleName, NSLINKMODULE_OPTION_RETURN_ON_ERROR) == NULL) {
        NSLinkEditErrors error;
        int errorNum;
        const char *fileName, *errorString;
        NSLinkEditError(&error, &errorNum, &fileName, &errorString);
        // These errors may overlap with other errors that objc_loadModule returns in other failure cases.
        *errorCode = error;
        return 0;
    }
    callbackFunction = NULL;


    return successFlag;
}

/**********************************************************************************
* objc_loadModules.
**********************************************************************************/
/* Lock for dynamic loading and unloading. */
//	static OBJC_DECLARE_LOCK (loadLock);


long	objc_loadModules   (char *			modlist[],
                         void *			errStream,
                         void			(*class_callback) (Class, Category),
                         headerType **	hdr_addr,
                         char *			debug_file)
{
    char **				modules;
    int					code;
    int					itWorked;

    if (modlist == 0)
        return 0;

    for (modules = &modlist[0]; *modules != 0; modules++)
    {
        itWorked = objc_loadModule (*modules, class_callback, &code);
        if (itWorked == 0)
        {
            //if (errStream)
            //	NXPrintf ((NXStream *) errStream, "objc_loadModules(%s) code = %d\n", *modules, code);
            return 1;
        }

        if (hdr_addr)
            *(hdr_addr++) = 0;
    }

    return 0;
}

/**********************************************************************************
* objc_unloadModules.
*
* NOTE:  Unloading isn't really thread safe.  If an unload message calls
* objc_loadModules() or objc_unloadModules(), then the current call
* to objc_unloadModules() will probably unload the wrong stuff.
**********************************************************************************/

long	objc_unloadModules (void *			errStream,
                         void			(*unload_callback) (Class, Category))
{
    headerType *	header_addr = 0;
    int errflag = 0;

    // TODO: to make unloading work, should get the current header

    if (header_addr)
    {
        ; // TODO: unload the current header
    }
    else
    {
        errflag = 1;
    }

    return errflag;
}

#endif
