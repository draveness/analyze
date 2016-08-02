/*
 * Copyright (c) 1999-2003, 2005-2007 Apple Inc.  All Rights Reserved.
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
	Object.h
	Copyright 1988-1996 NeXT Software, Inc.
  
	DEFINED AS:	A common class
	HEADER FILES:	<objc/Object.h>

*/

#ifndef _OBJC_OBJECT_H_
#define _OBJC_OBJECT_H_

#include <stdarg.h>
#include <objc/objc-runtime.h>

#if __OBJC__  &&  !__OBJC2__

__OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_NA)
OBJC_ROOT_CLASS
@interface Object
{
	Class isa;	/* A pointer to the instance's class structure */
}

/* Initializing classes and instances */

+ (id)initialize;
- (id)init;

/* Creating, copying, and freeing instances */

+ (id)new;
+ (id)free;
- (id)free;
+ (id)alloc;
- (id)copy;
+ (id)allocFromZone:(void *)zone;
- (id)copyFromZone:(void *)zone;
- (void *)zone;

/* Identifying classes */

+ (id)class;
+ (id)superclass;
+ (const char *) name;
- (id)class;
- (id)superclass;
- (const char *) name;

/* Identifying and comparing instances */

- (id)self;
- (unsigned int) hash;
- (BOOL) isEqual:anObject;

/* Testing inheritance relationships */

- (BOOL) isKindOf: aClassObject;
- (BOOL) isMemberOf: aClassObject;
- (BOOL) isKindOfClassNamed: (const char *)aClassName;
- (BOOL) isMemberOfClassNamed: (const char *)aClassName;

/* Testing class functionality */

+ (BOOL) instancesRespondTo:(SEL)aSelector;
- (BOOL) respondsTo:(SEL)aSelector;

/* Testing protocol conformance */

- (BOOL) conformsTo: (Protocol *)aProtocolObject;
+ (BOOL) conformsTo: (Protocol *)aProtocolObject;

/* Obtaining method descriptors from protocols */

- (struct objc_method_description *) descriptionForMethod:(SEL)aSel;
+ (struct objc_method_description *) descriptionForInstanceMethod:(SEL)aSel;

/* Obtaining method handles */

- (IMP) methodFor:(SEL)aSelector;
+ (IMP) instanceMethodFor:(SEL)aSelector;

/* Sending messages determined at run time */

- (id)perform:(SEL)aSelector;
- (id)perform:(SEL)aSelector with:anObject;
- (id)perform:(SEL)aSelector with:object1 with:object2;

/* Posing */

+ (id)poseAs: aClassObject;

/* Enforcing intentions */
 
- (id)subclassResponsibility:(SEL)aSelector;
- (id)notImplemented:(SEL)aSelector;

/* Error handling */

- (id)doesNotRecognize:(SEL)aSelector;
- (id)error:(const char *)aString, ...;

/* Debugging */

- (void) printForDebugger:(void *)stream;

/* Archiving */

- (id)awake;
- (id)write:(void *)stream;
- (id)read:(void *)stream;
+ (int) version;
+ (id)setVersion: (int) aVersion;

/* Forwarding */

- (id)forward: (SEL)sel : (marg_list)args;
- (id)performv: (SEL)sel : (marg_list)args;

@end

/* Abstract Protocol for Archiving */

@interface Object (Archiving)

- (id)startArchiving: (void *)stream;
- (id)finishUnarchiving;

@end

/* Abstract Protocol for Dynamic Loading */

@interface Object (DynamicLoading)

//+ finishLoading:(headerType *)header;
struct mach_header;
+ (id)finishLoading:(struct mach_header *)header;
+ (id)startUnloading;

@end

#endif

#endif /* _OBJC_OBJECT_H_ */
