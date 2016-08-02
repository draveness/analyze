/*
 * Copyright (c) 2002, 2006 Apple Inc.  All Rights Reserved.
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

#ifndef __OBJC_SNYC_H_
#define __OBJC_SNYC_H_

#include <objc/objc.h>


/** 
 * Begin synchronizing on 'obj'.  
 * Allocates recursive pthread_mutex associated with 'obj' if needed.
 * 
 * @param obj The object to begin synchronizing on.
 * 
 * @return OBJC_SYNC_SUCCESS once lock is acquired.  
 */
OBJC_EXPORT  int objc_sync_enter(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_2_0);

/** 
 * End synchronizing on 'obj'. 
 * 
 * @param obj The objet to end synchronizing on.
 * 
 * @return OBJC_SYNC_SUCCESS or OBJC_SYNC_NOT_OWNING_THREAD_ERROR
 */
OBJC_EXPORT  int objc_sync_exit(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_3, __IPHONE_2_0);

// The wait/notify functions have never worked correctly and no longer exist.
OBJC_EXPORT  int objc_sync_wait(id obj, long long milliSecondsMaxWait) 
    UNAVAILABLE_ATTRIBUTE;
OBJC_EXPORT  int objc_sync_notify(id obj) 
    UNAVAILABLE_ATTRIBUTE;
OBJC_EXPORT  int objc_sync_notifyAll(id obj) 
    UNAVAILABLE_ATTRIBUTE;

enum {
	OBJC_SYNC_SUCCESS                 = 0,
	OBJC_SYNC_NOT_OWNING_THREAD_ERROR = -1,
	OBJC_SYNC_TIMED_OUT               = -2,
	OBJC_SYNC_NOT_INITIALIZED         = -3		
};


#endif // __OBJC_SNYC_H_
