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
/***********************************************************************
*	objc-class.m
*	Copyright 1988-1997, Apple Computer, Inc.
*	Author:	s. naroff
**********************************************************************/


/***********************************************************************
 * Lazy method list arrays and method list locking  (2004-10-19)
 * 
 * cls->methodLists may be in one of three forms:
 * 1. nil: The class has no methods.
 * 2. non-nil, with CLS_NO_METHOD_ARRAY set: cls->methodLists points 
 *    to a single method list, which is the class's only method list.
 * 3. non-nil, with CLS_NO_METHOD_ARRAY clear: cls->methodLists points to 
 *    an array of method list pointers. The end of the array's block 
 *    is set to -1. If the actual number of method lists is smaller 
 *    than that, the rest of the array is nil.
 * 
 * Attaching categories and adding and removing classes may change 
 * the form of the class list. In addition, individual method lists 
 * may be reallocated when fixed up.
 *
 * Classes are initially read as #1 or #2. If a category is attached 
 * or other methods added, the class is changed to #3. Once in form #3, 
 * the class is never downgraded to #1 or #2, even if methods are removed.
 * Classes added with objc_addClass are initially either #1 or #3.
 * 
 * Accessing and manipulating a class's method lists are synchronized, 
 * to prevent races when one thread restructures the list. However, 
 * if the class is not yet in use (i.e. not in class_hash), then the 
 * thread loading the class may access its method lists without locking.
 * 
 * The following functions acquire methodListLock:
 * class_getInstanceMethod
 * class_getClassMethod
 * class_nextMethodList
 * class_addMethods
 * class_removeMethods
 * class_respondsToMethod
 * _class_lookupMethodAndLoadCache
 * lookupMethodInClassAndLoadCache
 * _objc_add_category_flush_caches
 *
 * The following functions don't acquire methodListLock because they 
 * only access method lists during class load and unload:
 * _objc_register_category
 * _resolve_categories_for_class (calls _objc_add_category)
 * add_class_to_loadable_list
 * _objc_addClass
 * _objc_remove_classes_in_image
 *
 * The following functions use method lists without holding methodListLock.
 * The caller must either hold methodListLock, or be loading the class.
 * _getMethod (called by class_getInstanceMethod, class_getClassMethod, 
 *   and class_respondsToMethod)
 * _findMethodInClass (called by _class_lookupMethodAndLoadCache, 
 *   lookupMethodInClassAndLoadCache, _getMethod)
 * _findMethodInList (called by _findMethodInClass)
 * nextMethodList (called by _findMethodInClass and class_nextMethodList
 * fixupSelectorsInMethodList (called by nextMethodList)
 * _objc_add_category (called by _objc_add_category_flush_caches, 
 *   resolve_categories_for_class and _objc_register_category)
 * _objc_insertMethods (called by class_addMethods and _objc_add_category)
 * _objc_removeMethods (called by class_removeMethods)
 * _objcTweakMethodListPointerForClass (called by _objc_insertMethods)
 * get_base_method_list (called by add_class_to_loadable_list)
 * lookupNamedMethodInMethodList (called by add_class_to_loadable_list)
 ***********************************************************************/

/***********************************************************************
 * Thread-safety of class info bits  (2004-10-19)
 * 
 * Some class info bits are used to store mutable runtime state. 
 * Modifications of the info bits at particular times need to be 
 * synchronized to prevent races.
 * 
 * Three thread-safe modification functions are provided:
 * cls->setInfo()     // atomically sets some bits
 * cls->clearInfo()   // atomically clears some bits
 * cls->changeInfo()  // atomically sets some bits and clears others
 * These replace CLS_SETINFO() for the multithreaded cases.
 * 
 * Three modification windows are defined:
 * - compile time
 * - class construction or image load (before +load) in one thread
 * - multi-threaded messaging and method caches
 * 
 * Info bit modification at compile time and class construction do not 
 *   need to be locked, because only one thread is manipulating the class.
 * Info bit modification during messaging needs to be locked, because 
 *   there may be other threads simultaneously messaging or otherwise 
 *   manipulating the class.
 *   
 * Modification windows for each flag:
 * 
 * CLS_CLASS: compile-time and class load
 * CLS_META: compile-time and class load
 * CLS_INITIALIZED: +initialize
 * CLS_POSING: messaging
 * CLS_MAPPED: compile-time
 * CLS_FLUSH_CACHE: class load and messaging
 * CLS_GROW_CACHE: messaging
 * CLS_NEED_BIND: unused
 * CLS_METHOD_ARRAY: unused
 * CLS_JAVA_HYBRID: JavaBridge only
 * CLS_JAVA_CLASS: JavaBridge only
 * CLS_INITIALIZING: messaging
 * CLS_FROM_BUNDLE: class load
 * CLS_HAS_CXX_STRUCTORS: compile-time and class load
 * CLS_NO_METHOD_ARRAY: class load and messaging
 * CLS_HAS_LOAD_METHOD: class load
 * 
 * CLS_INITIALIZED and CLS_INITIALIZING have additional thread-safety 
 * constraints to support thread-safe +initialize. See "Thread safety 
 * during class initialization" for details.
 * 
 * CLS_JAVA_HYBRID and CLS_JAVA_CLASS are set immediately after JavaBridge 
 * calls objc_addClass(). The JavaBridge does not use an atomic update, 
 * but the modification counts as "class construction" unless some other 
 * thread quickly finds the class via the class list. This race is 
 * small and unlikely in well-behaved code.
 *
 * Most info bits that may be modified during messaging are also never 
 * read without a lock. There is no general read lock for the info bits.
 * CLS_INITIALIZED: classInitLock
 * CLS_FLUSH_CACHE: cacheUpdateLock
 * CLS_GROW_CACHE: cacheUpdateLock
 * CLS_NO_METHOD_ARRAY: methodListLock
 * CLS_INITIALIZING: classInitLock
 ***********************************************************************/

/***********************************************************************
* Imports.
**********************************************************************/

#include "objc-private.h"
#include "objc-abi.h"
#include "objc-auto.h"
#include <objc/message.h>


/* overriding the default object allocation and error handling routines */

OBJC_EXPORT id	(*_alloc)(Class, size_t);
OBJC_EXPORT id	(*_copy)(id, size_t);
OBJC_EXPORT id	(*_realloc)(id, size_t);
OBJC_EXPORT id	(*_dealloc)(id);
OBJC_EXPORT id	(*_zoneAlloc)(Class, size_t, void *);
OBJC_EXPORT id	(*_zoneRealloc)(id, size_t, void *);
OBJC_EXPORT id	(*_zoneCopy)(id, size_t, void *);


/***********************************************************************
* Information about multi-thread support:
*
* Since we do not lock many operations which walk the superclass, method
* and ivar chains, these chains must remain intact once a class is published
* by inserting it into the class hashtable.  All modifications must be
* atomic so that someone walking these chains will always geta valid
* result.
***********************************************************************/



/***********************************************************************
* object_getClass.
* Locking: None. If you add locking, tell gdb (rdar://7516456).
**********************************************************************/
Class object_getClass(id obj)
{
    if (obj) return obj->getIsa();
    else return Nil;
}


/***********************************************************************
* object_setClass.
**********************************************************************/
Class object_setClass(id obj, Class cls)
{
    if (!obj) return nil;

    // Prevent a deadlock between the weak reference machinery
    // and the +initialize machinery by ensuring that no 
    // weakly-referenced object has an un-+initialized isa.
    // Unresolved future classes are not so protected.
    if (!cls->isFuture()  &&  !cls->isInitialized()) {
        _class_initialize(_class_getNonMetaClass(cls, nil));
    }

    return obj->changeIsa(cls);
}


/***********************************************************************
* object_isClass.
**********************************************************************/
BOOL object_isClass(id obj)
{
    if (!obj) return NO;
    return obj->isClass();
}


/***********************************************************************
* object_getClassName.
**********************************************************************/
const char *object_getClassName(id obj)
{
    return class_getName(obj ? obj->getIsa() : nil);
}


/***********************************************************************
 * object_getMethodImplementation.
 **********************************************************************/
IMP object_getMethodImplementation(id obj, SEL name)
{
    Class cls = (obj ? obj->getIsa() : nil);
    return class_getMethodImplementation(cls, name);
}


/***********************************************************************
 * object_getMethodImplementation_stret.
 **********************************************************************/
#if SUPPORT_STRET
IMP object_getMethodImplementation_stret(id obj, SEL name)
{
    Class cls = (obj ? obj->getIsa() : nil);
    return class_getMethodImplementation_stret(cls, name);
}
#endif


Ivar object_setInstanceVariable(id obj, const char *name, void *value)
{
    Ivar ivar = nil;

    if (obj  &&  name  &&  !obj->isTaggedPointer()) {
        if ((ivar = class_getInstanceVariable(obj->ISA(), name))) {
            object_setIvar(obj, ivar, (id)value);
        }
    }
    return ivar;
}

Ivar object_getInstanceVariable(id obj, const char *name, void **value)
{
    if (obj  &&  name  &&  !obj->isTaggedPointer()) {
        Ivar ivar;
        if ((ivar = class_getInstanceVariable(obj->ISA(), name))) {
            if (value) *value = (void *)object_getIvar(obj, ivar);
            return ivar;
        }
    }
    if (value) *value = nil;
    return nil;
}

static bool is_scanned_offset(ptrdiff_t ivar_offset, const uint8_t *layout) {
    ptrdiff_t index = 0, ivar_index = ivar_offset / sizeof(void*);
    uint8_t byte;
    while ((byte = *layout++)) {
        unsigned skips = (byte >> 4);
        unsigned scans = (byte & 0x0F);
        index += skips;
        while (scans--) {
            if (index == ivar_index) return YES;
            if (index > ivar_index) return NO;
            ++index;
        }
    }
    return NO;
}

// FIXME:  this could be optimized.

static Class _ivar_getClass(Class cls, Ivar ivar) {
    Class ivar_class = nil;
    const char *ivar_name = ivar_getName(ivar);
    Ivar named_ivar = _class_getVariable(cls, ivar_name, &ivar_class);
    if (named_ivar) {
        // the same ivar name can appear multiple times along the superclass chain.
        while (named_ivar != ivar && ivar_class != nil) {
            ivar_class = ivar_class->superclass;
            named_ivar = _class_getVariable(cls, ivar_getName(ivar), &ivar_class);
        }
    }
    return ivar_class;
}

void object_setIvar(id obj, Ivar ivar, id value)
{
    if (obj  &&  ivar  &&  !obj->isTaggedPointer()) {
        Class cls = _ivar_getClass(obj->ISA(), ivar);
        ptrdiff_t ivar_offset = ivar_getOffset(ivar);
        id *location = (id *)((char *)obj + ivar_offset);
        // if this ivar is a member of an ARR compiled class, then issue the correct barrier according to the layout.
        if (_class_usesAutomaticRetainRelease(cls)) {
            // for ARR, layout strings are relative to the instance start.
            uint32_t instanceStart = _class_getInstanceStart(cls);
            const uint8_t *weak_layout = class_getWeakIvarLayout(cls);
            if (weak_layout && is_scanned_offset(ivar_offset - instanceStart, weak_layout)) {
                // use the weak system to write to this variable.
                objc_storeWeak(location, value);
                return;
            }
            const uint8_t *strong_layout = class_getIvarLayout(cls);
            if (strong_layout && is_scanned_offset(ivar_offset - instanceStart, strong_layout)) {
                objc_storeStrong(location, value);
                return;
            }
        }
#if SUPPORT_GC
        if (UseGC) {
            // for GC, check for weak references.
            const uint8_t *weak_layout = class_getWeakIvarLayout(cls);
            if (weak_layout && is_scanned_offset(ivar_offset, weak_layout)) {
                objc_assign_weak(value, location);
            }
        }
        objc_assign_ivar(value, obj, ivar_offset);
#else
        *location = value;
#endif
    }
}


id object_getIvar(id obj, Ivar ivar)
{
    if (obj  &&  ivar  &&  !obj->isTaggedPointer()) {
        Class cls = obj->ISA();
        ptrdiff_t ivar_offset = ivar_getOffset(ivar);
        if (_class_usesAutomaticRetainRelease(cls)) {
            // for ARR, layout strings are relative to the instance start.
            uint32_t instanceStart = _class_getInstanceStart(cls);
            const uint8_t *weak_layout = class_getWeakIvarLayout(cls);
            if (weak_layout && is_scanned_offset(ivar_offset - instanceStart, weak_layout)) {
                // use the weak system to read this variable.
                id *location = (id *)((char *)obj + ivar_offset);
                return objc_loadWeak(location);
            }
        }
        id *idx = (id *)((char *)obj + ivar_offset);
#if SUPPORT_GC
        if (UseGC) {
            const uint8_t *weak_layout = class_getWeakIvarLayout(cls);
            if (weak_layout && is_scanned_offset(ivar_offset, weak_layout)) {
                return objc_read_weak(idx);
            }
        }
#endif
        return *idx;
    }
    return nil;
}


/***********************************************************************
* object_cxxDestructFromClass.
* Call C++ destructors on obj, starting with cls's 
*   dtor method (if any) followed by superclasses' dtors (if any), 
*   stopping at cls's dtor (if any).
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
**********************************************************************/
static void object_cxxDestructFromClass(id obj, Class cls)
{
    void (*dtor)(id);

    // Call cls's dtor first, then superclasses's dtors.

    for ( ; cls; cls = cls->superclass) {
        if (!cls->hasCxxDtor()) return; 
        dtor = (void(*)(id))
            lookupMethodInClassAndLoadCache(cls, SEL_cxx_destruct);
        if (dtor != (void(*)(id))_objc_msgForward_impcache) {
            if (PrintCxxCtors) {
                _objc_inform("CXX: calling C++ destructors for class %s", 
                             cls->nameForLogging());
            }
            (*dtor)(obj);
        }
    }
}


/***********************************************************************
* object_cxxDestruct.
* Call C++ destructors on obj, if any.
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
**********************************************************************/
void object_cxxDestruct(id obj)
{
    if (!obj) return;
    if (obj->isTaggedPointer()) return;
    object_cxxDestructFromClass(obj, obj->ISA());
}


/***********************************************************************
* object_cxxConstructFromClass.
* Recursively call C++ constructors on obj, starting with base class's 
*   ctor method (if any) followed by subclasses' ctors (if any), stopping 
*   at cls's ctor (if any).
* Does not check cls->hasCxxCtor(). The caller should preflight that.
* Returns self if construction succeeded.
* Returns nil if some constructor threw an exception. The exception is 
*   caught and discarded. Any partial construction is destructed.
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
*
* .cxx_construct returns id. This really means:
* return self: construction succeeded
* return nil:  construction failed because a C++ constructor threw an exception
**********************************************************************/
id 
object_cxxConstructFromClass(id obj, Class cls)
{
    assert(cls->hasCxxCtor());  // required for performance, not correctness

    id (*ctor)(id);
    Class supercls;

    supercls = cls->superclass;

    // Call superclasses' ctors first, if any.
    if (supercls  &&  supercls->hasCxxCtor()) {
        bool ok = object_cxxConstructFromClass(obj, supercls);
        if (!ok) return nil;  // some superclass's ctor failed - give up
    }

    // Find this class's ctor, if any.
    ctor = (id(*)(id))lookupMethodInClassAndLoadCache(cls, SEL_cxx_construct);
    if (ctor == (id(*)(id))_objc_msgForward_impcache) return obj;  // no ctor - ok
    
    // Call this class's ctor.
    if (PrintCxxCtors) {
        _objc_inform("CXX: calling C++ constructors for class %s", 
                     cls->nameForLogging());
    }
    if ((*ctor)(obj)) return obj;  // ctor called and succeeded - ok

    // This class's ctor was called and failed. 
    // Call superclasses's dtors to clean up.
    if (supercls) object_cxxDestructFromClass(obj, supercls);
    return nil;
}


/***********************************************************************
* _class_resolveClassMethod
* Call +resolveClassMethod, looking for a method to be added to class cls.
* cls should be a metaclass.
* Does not check if the method already exists.
**********************************************************************/
static void _class_resolveClassMethod(Class cls, SEL sel, id inst)
{
    assert(cls->isMetaClass());

    if (! lookUpImpOrNil(cls, SEL_resolveClassMethod, inst, 
                         NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
    {
        // Resolver not implemented.
        return;
    }

    BOOL (*msg)(Class, SEL, SEL) = (__typeof__(msg))objc_msgSend;
    bool resolved = msg(_class_getNonMetaClass(cls, inst), 
                        SEL_resolveClassMethod, sel);

    // Cache the result (good or bad) so the resolver doesn't fire next time.
    // +resolveClassMethod adds to self->ISA() a.k.a. cls
    IMP imp = lookUpImpOrNil(cls, sel, inst, 
                             NO/*initialize*/, YES/*cache*/, NO/*resolver*/);

    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveClassMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}


/***********************************************************************
* _class_resolveInstanceMethod
* Call +resolveInstanceMethod, looking for a method to be added to class cls.
* cls may be a metaclass or a non-meta class.
* Does not check if the method already exists.
**********************************************************************/
static void _class_resolveInstanceMethod(Class cls, SEL sel, id inst)
{
    if (! lookUpImpOrNil(cls->ISA(), SEL_resolveInstanceMethod, cls, 
                         NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
    {
        // Resolver not implemented.
        return;
    }

    BOOL (*msg)(Class, SEL, SEL) = (__typeof__(msg))objc_msgSend;
    bool resolved = msg(cls, SEL_resolveInstanceMethod, sel);

    // Cache the result (good or bad) so the resolver doesn't fire next time.
    // +resolveInstanceMethod adds to self a.k.a. cls
    IMP imp = lookUpImpOrNil(cls, sel, inst, 
                             NO/*initialize*/, YES/*cache*/, NO/*resolver*/);

    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveInstanceMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}


/***********************************************************************
* _class_resolveMethod
* Call +resolveClassMethod or +resolveInstanceMethod.
* Returns nothing; any result would be potentially out-of-date already.
* Does not check if the method already exists.
**********************************************************************/
void _class_resolveMethod(Class cls, SEL sel, id inst)
{
    if (! cls->isMetaClass()) {
        // try [cls resolveInstanceMethod:sel]
        _class_resolveInstanceMethod(cls, sel, inst);
    } 
    else {
        // try [nonMetaClass resolveClassMethod:sel]
        // and [cls resolveInstanceMethod:sel]
        _class_resolveClassMethod(cls, sel, inst);
        if (!lookUpImpOrNil(cls, sel, inst, 
                            NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
        {
            _class_resolveInstanceMethod(cls, sel, inst);
        }
    }
}


/***********************************************************************
* class_getClassMethod.  Return the class method for the specified
* class and selector.
**********************************************************************/
Method class_getClassMethod(Class cls, SEL sel)
{
    if (!cls  ||  !sel) return nil;

    return class_getInstanceMethod(cls->getMeta(), sel);
}


/***********************************************************************
* class_getInstanceVariable.  Return the named instance variable.
**********************************************************************/
Ivar class_getInstanceVariable(Class cls, const char *name)
{
    if (!cls  ||  !name) return nil;

    return _class_getVariable(cls, name, nil);
}


/***********************************************************************
* class_getClassVariable.  Return the named class variable.
**********************************************************************/
Ivar class_getClassVariable(Class cls, const char *name)
{
    if (!cls) return nil;

    return class_getInstanceVariable(cls->ISA(), name);
}


/***********************************************************************
* gdb_objc_class_changed
* Tell gdb that a class changed. Currently used for OBJC2 ivar layouts only
* Does nothing; gdb sets a breakpoint on it.
**********************************************************************/
BREAKPOINT_FUNCTION( 
    void gdb_objc_class_changed(Class cls, unsigned long changes, const char *classname)
);


/***********************************************************************
* class_respondsToSelector.
**********************************************************************/
BOOL class_respondsToMethod(Class cls, SEL sel)
{
    OBJC_WARN_DEPRECATED;

    return class_respondsToSelector(cls, sel);
}


BOOL class_respondsToSelector(Class cls, SEL sel)
{
    return class_respondsToSelector_inst(cls, sel, nil);
}


// inst is an instance of cls or a subclass thereof, or nil if none is known.
// Non-nil inst is faster in some cases. See lookUpImpOrForward() for details.
bool class_respondsToSelector_inst(Class cls, SEL sel, id inst)
{
    IMP imp;

    if (!sel  ||  !cls) return NO;

    // Avoids +initialize because it historically did so.
    // We're not returning a callable IMP anyway.
    imp = lookUpImpOrNil(cls, sel, inst, 
                         NO/*initialize*/, YES/*cache*/, YES/*resolver*/);
    return bool(imp);
}


/***********************************************************************
* class_getMethodImplementation.
* Returns the IMP that would be invoked if [obj sel] were sent, 
* where obj is an instance of class cls.
**********************************************************************/
IMP class_lookupMethod(Class cls, SEL sel)
{
    OBJC_WARN_DEPRECATED;

    // No one responds to zero!
    if (!sel) {
        __objc_error(cls, "invalid selector (null)");
    }

    return class_getMethodImplementation(cls, sel);
}

IMP class_getMethodImplementation(Class cls, SEL sel)
{
    IMP imp;

    if (!cls  ||  !sel) return nil;

    imp = lookUpImpOrNil(cls, sel, nil, 
                         YES/*initialize*/, YES/*cache*/, YES/*resolver*/);

    // Translate forwarding function to C-callable external version
    if (!imp) {
        return _objc_msgForward;
    }

    return imp;
}

#if SUPPORT_STRET
IMP class_getMethodImplementation_stret(Class cls, SEL sel)
{
    IMP imp = class_getMethodImplementation(cls, sel);

    // Translate forwarding function to struct-returning version
    if (imp == (IMP)&_objc_msgForward /* not _internal! */) {
        return (IMP)&_objc_msgForward_stret;
    }
    return imp;
}
#endif


/***********************************************************************
* instrumentObjcMessageSends
**********************************************************************/
#if !SUPPORT_MESSAGE_LOGGING

void	instrumentObjcMessageSends(BOOL flag)
{
}

#else

bool objcMsgLogEnabled = false;
static int objcMsgLogFD = -1;

bool logMessageSend(bool isClassMethod,
                    const char *objectsClass,
                    const char *implementingClass,
                    SEL selector)
{
    char	buf[ 1024 ];

    // Create/open the log file
    if (objcMsgLogFD == (-1))
    {
        snprintf (buf, sizeof(buf), "/tmp/msgSends-%d", (int) getpid ());
        objcMsgLogFD = secure_open (buf, O_WRONLY | O_CREAT, geteuid());
        if (objcMsgLogFD < 0) {
            // no log file - disable logging
            objcMsgLogEnabled = false;
            objcMsgLogFD = -1;
            return true;
        }
    }

    // Make the log entry
    snprintf(buf, sizeof(buf), "%c %s %s %s\n",
            isClassMethod ? '+' : '-',
            objectsClass,
            implementingClass,
            sel_getName(selector));

    static spinlock_t lock;
    lock.lock();
    write (objcMsgLogFD, buf, strlen(buf));
    lock.unlock();

    // Tell caller to not cache the method
    return false;
}

void instrumentObjcMessageSends(BOOL flag)
{
    bool enable = flag;

    // Shortcut NOP
    if (objcMsgLogEnabled == enable)
        return;

    // If enabling, flush all method caches so we get some traces
    if (enable)
        _objc_flush_caches(Nil);

    // Sync our log file
    if (objcMsgLogFD != -1)
        fsync (objcMsgLogFD);

    objcMsgLogEnabled = enable;
}

// SUPPORT_MESSAGE_LOGGING
#endif


Class _calloc_class(size_t size)
{
#if SUPPORT_GC
    if (UseGC) return (Class) malloc_zone_calloc(gc_zone, 1, size);
#endif
    return (Class) calloc(1, size);
}

Class class_getSuperclass(Class cls)
{
    if (!cls) return nil;
    return cls->superclass;
}

BOOL class_isMetaClass(Class cls)
{
    if (!cls) return NO;
    return cls->isMetaClass();
}


size_t class_getInstanceSize(Class cls)
{
    if (!cls) return 0;
    return cls->alignedInstanceSize();
}


/***********************************************************************
* method_getNumberOfArguments.
**********************************************************************/
unsigned int method_getNumberOfArguments(Method m)
{
    if (!m) return 0;
    return encoding_getNumberOfArguments(method_getTypeEncoding(m));
}


void method_getReturnType(Method m, char *dst, size_t dst_len)
{
    encoding_getReturnType(method_getTypeEncoding(m), dst, dst_len);
}


char * method_copyReturnType(Method m)
{
    return encoding_copyReturnType(method_getTypeEncoding(m));
}


void method_getArgumentType(Method m, unsigned int index, 
                            char *dst, size_t dst_len)
{
    encoding_getArgumentType(method_getTypeEncoding(m),
                             index, dst, dst_len);
}


char * method_copyArgumentType(Method m, unsigned int index)
{
    return encoding_copyArgumentType(method_getTypeEncoding(m), index);
}


/***********************************************************************
* _objc_constructOrFree
* Call C++ constructors, and free() if they fail.
* bytes->isa must already be set.
* cls must have cxx constructors.
* Returns the object, or nil.
**********************************************************************/
id
_objc_constructOrFree(id bytes, Class cls)
{
    assert(cls->hasCxxCtor());  // for performance, not correctness

    id obj = object_cxxConstructFromClass(bytes, cls);
    if (!obj) {
#if SUPPORT_GC
        if (UseGC) {
            auto_zone_retain(gc_zone, bytes);  // gc free expects rc==1
        }
#endif
        free(bytes);
    }

    return obj;
}


/***********************************************************************
* _class_createInstancesFromZone
* Batch-allocating version of _class_createInstanceFromZone.
* Attempts to allocate num_requested objects, each with extraBytes.
* Returns the number of allocated objects (possibly zero), with 
* the allocated pointers in *results.
**********************************************************************/
unsigned
_class_createInstancesFromZone(Class cls, size_t extraBytes, void *zone, 
                               id *results, unsigned num_requested)
{
    unsigned num_allocated;
    if (!cls) return 0;

    size_t size = cls->instanceSize(extraBytes);

#if SUPPORT_GC
    if (UseGC) {
        num_allocated = 
            auto_zone_batch_allocate(gc_zone, size, AUTO_OBJECT_SCANNED, 0, 1, 
                                     (void**)results, num_requested);
    } else 
#endif
    {
        unsigned i;
        num_allocated = 
            malloc_zone_batch_malloc((malloc_zone_t *)(zone ? zone : malloc_default_zone()), 
                                     size, (void**)results, num_requested);
        for (i = 0; i < num_allocated; i++) {
            bzero(results[i], size);
        }
    }

    // Construct each object, and delete any that fail construction.

    unsigned shift = 0;
    unsigned i;
    bool ctor = cls->hasCxxCtor();
    for (i = 0; i < num_allocated; i++) {
        id obj = results[i];
        obj->initIsa(cls);    // fixme allow indexed
        if (ctor) obj = _objc_constructOrFree(obj, cls);

        if (obj) {
            results[i-shift] = obj;
        } else {
            shift++;
        }
    }

    return num_allocated - shift;    
}


/***********************************************************************
* inform_duplicate. Complain about duplicate class implementations.
**********************************************************************/
void 
inform_duplicate(const char *name, Class oldCls, Class cls)
{
#if TARGET_OS_WIN32
    (DebugDuplicateClasses ? _objc_fatal : _objc_inform)
        ("Class %s is implemented in two different images.", name);
#else
    const header_info *oldHeader = _headerForClass(oldCls);
    const header_info *newHeader = _headerForClass(cls);
    const char *oldName = oldHeader ? oldHeader->fname : "??";
    const char *newName = newHeader ? newHeader->fname : "??";

    (DebugDuplicateClasses ? _objc_fatal : _objc_inform)
        ("Class %s is implemented in both %s and %s. "
         "One of the two will be used. Which one is undefined.",
         name, oldName, newName);
#endif
}


const char *
copyPropertyAttributeString(const objc_property_attribute_t *attrs,
                            unsigned int count)
{
    char *result;
    unsigned int i;
    if (count == 0) return strdup("");
    
#if DEBUG
    // debug build: sanitize input
    for (i = 0; i < count; i++) {
        assert(attrs[i].name);
        assert(strlen(attrs[i].name) > 0);
        assert(! strchr(attrs[i].name, ','));
        assert(! strchr(attrs[i].name, '"'));
        if (attrs[i].value) assert(! strchr(attrs[i].value, ','));
    }
#endif

    size_t len = 0;
    for (i = 0; i < count; i++) {
        if (attrs[i].value) {
            size_t namelen = strlen(attrs[i].name);
            if (namelen > 1) namelen += 2;  // long names get quoted
            len += namelen + strlen(attrs[i].value) + 1;
        }
    }

    result = (char *)malloc(len + 1);
    char *s = result;
    for (i = 0; i < count; i++) {
        if (attrs[i].value) {
            size_t namelen = strlen(attrs[i].name);
            if (namelen > 1) {
                s += sprintf(s, "\"%s\"%s,", attrs[i].name, attrs[i].value);
            } else {
                s += sprintf(s, "%s%s,", attrs[i].name, attrs[i].value);
            }
        }
    }

    // remove trailing ',' if any
    if (s > result) s[-1] = '\0';

    return result;
}

/*
  Property attribute string format:

  - Comma-separated name-value pairs. 
  - Name and value may not contain ,
  - Name may not contain "
  - Value may be empty
  - Name is single char, value follows
  - OR Name is double-quoted string of 2+ chars, value follows

  Grammar:
    attribute-string: \0
    attribute-string: name-value-pair (',' name-value-pair)*
    name-value-pair:  unquoted-name optional-value
    name-value-pair:  quoted-name optional-value
    unquoted-name:    [^",]
    quoted-name:      '"' [^",]{2,} '"'
    optional-value:   [^,]*

*/
static unsigned int 
iteratePropertyAttributes(const char *attrs, 
                          bool (*fn)(unsigned int index, 
                                     void *ctx1, void *ctx2, 
                                     const char *name, size_t nlen, 
                                     const char *value, size_t vlen), 
                          void *ctx1, void *ctx2)
{
    if (!attrs) return 0;

#if DEBUG
    const char *attrsend = attrs + strlen(attrs);
#endif
    unsigned int attrcount = 0;

    while (*attrs) {
        // Find the next comma-separated attribute
        const char *start = attrs;
        const char *end = start + strcspn(attrs, ",");

        // Move attrs past this attribute and the comma (if any)
        attrs = *end ? end+1 : end;

        assert(attrs <= attrsend);
        assert(start <= attrsend);
        assert(end <= attrsend);
        
        // Skip empty attribute
        if (start == end) continue;

        // Process one non-empty comma-free attribute [start,end)
        const char *nameStart;
        const char *nameEnd;

        assert(start < end);
        assert(*start);
        if (*start != '\"') {
            // single-char short name
            nameStart = start;
            nameEnd = start+1;
            start++;
        }
        else {
            // double-quoted long name
            nameStart = start+1;
            nameEnd = nameStart + strcspn(nameStart, "\",");
            start++;                       // leading quote
            start += nameEnd - nameStart;  // name
            if (*start == '\"') start++;   // trailing quote, if any
        }

        // Process one possibly-empty comma-free attribute value [start,end)
        const char *valueStart;
        const char *valueEnd;

        assert(start <= end);

        valueStart = start;
        valueEnd = end;

        bool more = (*fn)(attrcount, ctx1, ctx2, 
                          nameStart, nameEnd-nameStart, 
                          valueStart, valueEnd-valueStart);
        attrcount++;
        if (!more) break;
    }

    return attrcount;
}


static bool 
copyOneAttribute(unsigned int index, void *ctxa, void *ctxs, 
                 const char *name, size_t nlen, const char *value, size_t vlen)
{
    objc_property_attribute_t **ap = (objc_property_attribute_t**)ctxa;
    char **sp = (char **)ctxs;

    objc_property_attribute_t *a = *ap;
    char *s = *sp;

    a->name = s;
    memcpy(s, name, nlen);
    s += nlen;
    *s++ = '\0';
    
    a->value = s;
    memcpy(s, value, vlen);
    s += vlen;
    *s++ = '\0';

    a++;
    
    *ap = a;
    *sp = s;

    return YES;
}

                 
objc_property_attribute_t *
copyPropertyAttributeList(const char *attrs, unsigned int *outCount)
{
    if (!attrs) {
        if (outCount) *outCount = 0;
        return nil;
    }

    // Result size:
    //   number of commas plus 1 for the attributes (upper bound)
    //   plus another attribute for the attribute array terminator
    //   plus strlen(attrs) for name/value string data (upper bound)
    //   plus count*2 for the name/value string terminators (upper bound)
    unsigned int attrcount = 1;
    const char *s;
    for (s = attrs; s && *s; s++) {
        if (*s == ',') attrcount++;
    }

    size_t size = 
        attrcount * sizeof(objc_property_attribute_t) + 
        sizeof(objc_property_attribute_t) + 
        strlen(attrs) + 
        attrcount * 2;
    objc_property_attribute_t *result = (objc_property_attribute_t *) 
        calloc(size, 1);

    objc_property_attribute_t *ra = result;
    char *rs = (char *)(ra+attrcount+1);

    attrcount = iteratePropertyAttributes(attrs, copyOneAttribute, &ra, &rs);

    assert((uint8_t *)(ra+1) <= (uint8_t *)result+size);
    assert((uint8_t *)rs <= (uint8_t *)result+size);

    if (attrcount == 0) {
        free(result);
        result = nil;
    }

    if (outCount) *outCount = attrcount;
    return result;
}


static bool 
findOneAttribute(unsigned int index, void *ctxa, void *ctxs, 
                 const char *name, size_t nlen, const char *value, size_t vlen)
{
    const char *query = (char *)ctxa;
    char **resultp = (char **)ctxs;

    if (strlen(query) == nlen  &&  0 == strncmp(name, query, nlen)) {
        char *result = (char *)calloc(vlen+1, 1);
        memcpy(result, value, vlen);
        result[vlen] = '\0';
        *resultp = result;
        return NO;
    }

    return YES;
}

char *copyPropertyAttributeValue(const char *attrs, const char *name)
{
    char *result = nil;

    iteratePropertyAttributes(attrs, findOneAttribute, (void*)name, &result);

    return result;
}
