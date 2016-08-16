/*
 * Copyright (c) 1999-2007 Apple Inc.  All Rights Reserved.
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
	Object.m
	Copyright 1988-1996 NeXT Software, Inc.
*/

#include "objc-private.h"

#undef id
#undef Class

typedef struct objc_class *Class;
typedef struct objc_object *id;

#if __OBJC2__

__OSX_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_NA)
OBJC_ROOT_CLASS
@interface Object { 
    Class isa; 
} 
@end

@implementation Object

+ (id)initialize
{
    return self; 
}

+ (id)class
{
    return self;
}

-(id) retain
{
    return _objc_rootRetain(self);
}

-(void) release
{
    _objc_rootRelease(self);
}

-(id) autorelease
{
    return _objc_rootAutorelease(self);
}

+(id) retain
{
    return self;
}

+(void) release
{
}

+(id) autorelease
{
    return self;
}


@end


// __OBJC2__
#else
// not __OBJC2__

#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <malloc/malloc.h>

#include "Object.h"
#include "Protocol.h"
#include "objc-runtime.h"
#include "objc-auto.h"


// Error Messages
static const char
	_errShouldHaveImp[] = "should have implemented the '%s' method.",
	_errShouldNotImp[] = "should NOT have implemented the '%s' method.",
	_errLeftUndone[] = "method '%s' not implemented",
	_errBadSel[] = "method %s given invalid selector %s",
	_errDoesntRecognize[] = "does not recognize selector %c%s";


@implementation Object


+ (id)initialize
{
	return self; 
}

- (id)awake
{
	return self; 
}

+ (id)poseAs: aFactory
{ 
	return class_poseAs(self, aFactory); 
}

+ (id)new
{
	id newObject = (*_alloc)((Class)self, 0);
	Class metaClass = self->ISA();
	if (class_getVersion(metaClass) > 1)
	    return [newObject init];
	else
	    return newObject;
}

+ (id)alloc
{
	return (*_zoneAlloc)((Class)self, 0, malloc_default_zone()); 
}

+ (id)allocFromZone:(void *) z
{
	return (*_zoneAlloc)((Class)self, 0, z); 
}

- (id)init
{
    return self;
}

- (const char *)name
{
	return class_getName(isa); 
}

+ (const char *)name
{
	return class_getName((Class)self); 
}

- (unsigned)hash
{
	return (unsigned)(((uintptr_t)self) >> 2);
}

- (BOOL)isEqual:anObject
{
	return anObject == self; 
}

- (id)free
{ 
	return (*_dealloc)(self); 
}

+ (id)free
{
	return nil; 
}

- (id)self
{
	return self; 
}


-(id)class
{
	return (id)isa; 
}

+ (id)class
{
	return self;
}

- (void *)zone
{
	void *z = malloc_zone_from_ptr(self);
	return z ? z : malloc_default_zone();
}

+ (id)superclass
{ 
	return self->superclass; 
}

- (id)superclass
{ 
	return isa->superclass; 
}

+ (int) version
{
	return class_getVersion((Class)self);
}

+ (id)setVersion: (int) aVersion
{
        class_setVersion((Class)self, aVersion);
	return self;
}

- (BOOL)isKindOf:aClass
{
	Class cls;
	for (cls = isa; cls; cls = cls->superclass) 
		if (cls == (Class)aClass)
			return YES;
	return NO;
}

- (BOOL)isMemberOf:aClass
{
	return isa == (Class)aClass;
}

- (BOOL)isKindOfClassNamed:(const char *)aClassName
{
	Class cls;
	for (cls = isa; cls; cls = cls->superclass) 
		if (strcmp(aClassName, class_getName(cls)) == 0)
			return YES;
	return NO;
}

- (BOOL)isMemberOfClassNamed:(const char *)aClassName
{
	return strcmp(aClassName, class_getName(isa)) == 0;
}

+ (BOOL)instancesRespondTo:(SEL)aSelector
{
	return class_respondsToMethod((Class)self, aSelector);
}

- (BOOL)respondsTo:(SEL)aSelector
{
	return class_respondsToMethod(isa, aSelector);
}

- (id)copy
{
	return [self copyFromZone: [self zone]];
}

- (id)copyFromZone:(void *)z
{
	return (*_zoneCopy)(self, 0, z); 
}

- (IMP)methodFor:(SEL)aSelector
{
	return class_lookupMethod(isa, aSelector);
}

+ (IMP)instanceMethodFor:(SEL)aSelector
{
	return class_lookupMethod(self, aSelector);
}

- (id)perform:(SEL)aSelector
{ 
	if (aSelector)
		return ((id(*)(id, SEL))objc_msgSend)(self, aSelector); 
	else
		return [self error:_errBadSel, sel_getName(_cmd), aSelector];
}

- (id)perform:(SEL)aSelector with:anObject
{
	if (aSelector)
		return ((id(*)(id, SEL, id))objc_msgSend)(self, aSelector, anObject); 
	else
		return [self error:_errBadSel, sel_getName(_cmd), aSelector];
}

- (id)perform:(SEL)aSelector with:obj1 with:obj2
{
	if (aSelector)
		return ((id(*)(id, SEL, id, id))objc_msgSend)(self, aSelector, obj1, obj2); 
	else
		return [self error:_errBadSel, sel_getName(_cmd), aSelector];
}

- (id)subclassResponsibility:(SEL)aSelector
{
	return [self error:_errShouldHaveImp, sel_getName(aSelector)];
}

- (id)notImplemented:(SEL)aSelector
{
	return [self error:_errLeftUndone, sel_getName(aSelector)];
}

- (id)doesNotRecognize:(SEL)aMessage
{
	return [self error:_errDoesntRecognize, 
		class_isMetaClass(isa) ? '+' : '-', sel_getName(aMessage)];
}

- (id)error:(const char *)aCStr, ... 
{
	va_list ap;
	va_start(ap,aCStr); 
	(*_error)(self, aCStr, ap); 
	_objc_error (self, aCStr, ap);	/* In case (*_error)() returns. */
	va_end(ap);
        return nil;
}

- (void) printForDebugger:(void *)stream
{
}

- (id)write:(void *) stream
{
	return self;
}

- (id)read:(void *) stream
{
	return self;
}

- (id)forward: (SEL) sel : (marg_list) args
{
    return [self doesNotRecognize: sel];
}

/* this method is not part of the published API */

- (unsigned)methodArgSize:(SEL)sel
{
    Method	method = class_getInstanceMethod((Class)isa, sel);
    if (! method) return 0;
    return method_getSizeOfArguments(method);
}

- (id)performv: (SEL) sel : (marg_list) args
{
    unsigned	size;

    // Messages to nil object always return nil
    if (! self) return nil;

    // Calculate size of the marg_list from the method's
    // signature.  This looks for the method in self
    // and its superclasses.
    size = [self methodArgSize: sel];

    // If neither self nor its superclasses implement
    // it, forward the message because self might know
    // someone who does.  This is a "chained" forward...
    if (! size) return [self forward: sel: args];

    // Message self with the specified selector and arguments
    return objc_msgSendv (self, sel, size, args); 
}

/* Testing protocol conformance */

- (BOOL) conformsTo: (Protocol *)aProtocolObj
{
  return [(id)isa conformsTo:aProtocolObj];
}

+ (BOOL) conformsTo: (Protocol *)aProtocolObj
{
  Class cls;
  for (cls = self; cls; cls = cls->superclass)
    {
      if (class_conformsToProtocol(cls, aProtocolObj)) return YES;
    }
  return NO;
}


/* Looking up information for a method */

- (struct objc_method_description *) descriptionForMethod:(SEL)aSelector
{
  Class cls;
  struct objc_method_description *m;

  /* Look in the protocols first. */
  for (cls = isa; cls; cls = cls->superclass)
    {
      if (cls->ISA()->version >= 3)
        {
	  struct objc_protocol_list *protocols = 
              (struct objc_protocol_list *)cls->protocols;
  
	  while (protocols)
	    {
	      int i;

	      for (i = 0; i < protocols->count; i++)
		{
		  Protocol *p = protocols->list[i];

		  if (class_isMetaClass(cls))
		    m = [p descriptionForClassMethod:aSelector];
		  else
		    m = [p descriptionForInstanceMethod:aSelector];

		  if (m) {
		      return m;
		  }
		}
  
	      if (cls->ISA()->version <= 4)
		break;
  
	      protocols = protocols->next;
	    }
	}
    }

  /* Then try the class implementations. */
    for (cls = isa; cls; cls = cls->superclass) {
        void *iterator = 0;
	int i;
        struct objc_method_list *mlist;
        while ( (mlist = class_nextMethodList( cls, &iterator )) ) {
            for (i = 0; i < mlist->method_count; i++)
                if (mlist->method_list[i].method_name == aSelector) {
		    m = (struct objc_method_description *)&mlist->method_list[i];
                    return m;
		}
        }
    }
  return 0;
}

+ (struct objc_method_description *) descriptionForInstanceMethod:(SEL)aSelector
{
  Class cls;

  /* Look in the protocols first. */
  for (cls = self; cls; cls = cls->superclass)
    {
      if (cls->ISA()->version >= 3)
        {
	  struct objc_protocol_list *protocols = 
              (struct objc_protocol_list *)cls->protocols;
  
	  while (protocols)
	    {
	      int i;

	      for (i = 0; i < protocols->count; i++)
		{
		  Protocol *p = protocols->list[i];
		  struct objc_method_description *m;

		  if ((m = [p descriptionForInstanceMethod:aSelector]))
		    return m;
		}
  
	      if (cls->ISA()->version <= 4)
		break;
  
	      protocols = protocols->next;
	    }
	}
    }

  /* Then try the class implementations. */
    for (cls = self; cls; cls = cls->superclass) {
        void *iterator = 0;
	int i;
        struct objc_method_list *mlist;
        while ( (mlist = class_nextMethodList( cls, &iterator )) ) {
            for (i = 0; i < mlist->method_count; i++)
                if (mlist->method_list[i].method_name == aSelector) {
		    struct objc_method_description *m;
		    m = (struct objc_method_description *)&mlist->method_list[i];
                    return m;
		}
        }
    }
  return 0;
}


/* Obsolete methods (for binary compatibility only). */

+ (id)superClass
{
	return [self superclass];
}

- (id)superClass
{
	return [self superclass];
}

- (BOOL)isKindOfGivenName:(const char *)aClassName
{
	return [self isKindOfClassNamed: aClassName];
}

- (BOOL)isMemberOfGivenName:(const char *)aClassName
{
	return [self isMemberOfClassNamed: aClassName];
}

- (struct objc_method_description *) methodDescFor:(SEL)aSelector
{
  return [self descriptionForMethod: aSelector];
}

+ (struct objc_method_description *) instanceMethodDescFor:(SEL)aSelector
{
  return [self descriptionForInstanceMethod: aSelector];
}

- (id)findClass:(const char *)aClassName
{
	return objc_lookUpClass(aClassName);
}

- (id)shouldNotImplement:(SEL)aSelector
{
	return [self error:_errShouldNotImp, sel_getName(aSelector)];
}


@end

#endif
