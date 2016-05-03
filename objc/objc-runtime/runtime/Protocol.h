/*
 * Copyright (c) 1999-2003, 2006-2007 Apple Inc.  All Rights Reserved.
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
	Protocol.h
	Copyright 1991-1996 NeXT Software, Inc.
*/

#ifndef _OBJC_PROTOCOL_H_
#define _OBJC_PROTOCOL_H_

#if !__OBJC__

// typedef Protocol is here:
#include <objc/runtime.h>


#elif __OBJC2__

#include <objc/NSObject.h>

// All methods of class Protocol are unavailable. 
// Use the functions in objc/runtime.h instead.

__OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
@interface Protocol : NSObject
@end


#else

#include <objc/Object.h>

__OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0)
@interface Protocol : Object
{
@private
    char *protocol_name OBJC2_UNAVAILABLE;
    struct objc_protocol_list *protocol_list OBJC2_UNAVAILABLE;
    struct objc_method_description_list *instance_methods OBJC2_UNAVAILABLE;
    struct objc_method_description_list *class_methods OBJC2_UNAVAILABLE;
}

/* Obtaining attributes intrinsic to the protocol */

- (const char *)name OBJC2_UNAVAILABLE;

/* Testing protocol conformance */

- (BOOL) conformsTo: (Protocol *)aProtocolObject OBJC2_UNAVAILABLE;

/* Looking up information specific to a protocol */

- (struct objc_method_description *) descriptionForInstanceMethod:(SEL)aSel
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_0,__MAC_10_5, __IPHONE_2_0,__IPHONE_2_0);
- (struct objc_method_description *) descriptionForClassMethod:(SEL)aSel 
    __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_0,__MAC_10_5, __IPHONE_2_0,__IPHONE_2_0);

@end

#endif

#endif /* _OBJC_PROTOCOL_H_ */
