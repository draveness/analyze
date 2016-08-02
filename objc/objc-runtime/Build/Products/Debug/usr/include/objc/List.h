/*
 * Copyright (c) 1999-2002, 2005-2007 Apple Inc.  All Rights Reserved.
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
    List.h
    Copyright 1988-1996 NeXT Software, Inc.

    DEFINED AS:	A common class
    HEADER FILES:	objc/List.h

*/

#ifndef _OBJC_LIST_H_
#define _OBJC_LIST_H_

#if __OBJC__  &&  !__OBJC2__  &&  !__cplusplus

#include <objc/Object.h>
#include <Availability.h>

DEPRECATED_ATTRIBUTE
@interface List : Object
{
@public
    id 		*dataPtr  DEPRECATED_ATTRIBUTE;	/* data of the List object */
    unsigned 	numElements  DEPRECATED_ATTRIBUTE;	/* Actual number of elements */
    unsigned 	maxElements  DEPRECATED_ATTRIBUTE;	/* Total allocated elements */
}

/* Creating, freeing */

- (id)free  DEPRECATED_ATTRIBUTE;
- (id)freeObjects  DEPRECATED_ATTRIBUTE;
- (id)copyFromZone:(void *)z  DEPRECATED_ATTRIBUTE;
  
/* Initializing */

- (id)init  DEPRECATED_ATTRIBUTE;
- (id)initCount:(unsigned)numSlots  DEPRECATED_ATTRIBUTE;

/* Comparing two lists */

- (BOOL)isEqual: anObject  DEPRECATED_ATTRIBUTE;
  
/* Managing the storage capacity */

- (unsigned)capacity  DEPRECATED_ATTRIBUTE;
- (id)setAvailableCapacity:(unsigned)numSlots  DEPRECATED_ATTRIBUTE;

/* Manipulating objects by index */

- (unsigned)count  DEPRECATED_ATTRIBUTE;
- (id)objectAt:(unsigned)index  DEPRECATED_ATTRIBUTE;
- (id)lastObject  DEPRECATED_ATTRIBUTE;
- (id)addObject:anObject  DEPRECATED_ATTRIBUTE;
- (id)insertObject:anObject at:(unsigned)index  DEPRECATED_ATTRIBUTE;
- (id)removeObjectAt:(unsigned)index  DEPRECATED_ATTRIBUTE;
- (id)removeLastObject  DEPRECATED_ATTRIBUTE;
- (id)replaceObjectAt:(unsigned)index with:newObject  DEPRECATED_ATTRIBUTE;
- (id)appendList: (List *)otherList  DEPRECATED_ATTRIBUTE;

/* Manipulating objects by id */

- (unsigned)indexOf:anObject  DEPRECATED_ATTRIBUTE;
- (id)addObjectIfAbsent:anObject  DEPRECATED_ATTRIBUTE;
- (id)removeObject:anObject  DEPRECATED_ATTRIBUTE;
- (id)replaceObject:anObject with:newObject  DEPRECATED_ATTRIBUTE;

/* Emptying the list */

- (id)empty  DEPRECATED_ATTRIBUTE;

/* Sending messages to elements of the list */

- (id)makeObjectsPerform:(SEL)aSelector  DEPRECATED_ATTRIBUTE;
- (id)makeObjectsPerform:(SEL)aSelector with:anObject  DEPRECATED_ATTRIBUTE;

/*
 * The following new... methods are now obsolete.  They remain in this 
 * interface file for backward compatibility only.  Use Object's alloc method 
 * and the init... methods defined in this class instead.
 */

+ (id)new  DEPRECATED_ATTRIBUTE;
+ (id)newCount:(unsigned)numSlots  DEPRECATED_ATTRIBUTE;

@end

typedef struct {
    @defs(List);
} NXListId  DEPRECATED_ATTRIBUTE;

#define NX_ADDRESS(x) (((NXListId *)(x))->dataPtr)

#define NX_NOT_IN_LIST	0xffffffff

#endif

#endif /* _OBJC_LIST_H_ */
