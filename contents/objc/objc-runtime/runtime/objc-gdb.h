/*
 * Copyright (c) 2008 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_GDB_H
#define _OBJC_GDB_H

/* 
 * WARNING  DANGER  HAZARD  BEWARE  EEK
 * 
 * Everything in this file is for debugger and developer tool use only.
 * These will change in arbitrary OS updates and in unpredictable ways.
 * When your program breaks, you get to keep both pieces.
 */

#ifdef __APPLE_API_PRIVATE

#define _OBJC_PRIVATE_H_
#include <stdint.h>
#include <objc/hashtable.h>
#include <objc/maptable.h>

__BEGIN_DECLS


/***********************************************************************
* Class pointer preflighting
**********************************************************************/

// Return cls if it's a valid class, or crash.
OBJC_EXPORT Class gdb_class_getClass(Class cls)
#if __OBJC2__
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_1);
#else
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_3_1);
#endif

// Same as gdb_class_getClass(object_getClass(cls)).
OBJC_EXPORT Class gdb_object_getClass(id obj)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_4_3);


/***********************************************************************
* Class lists for heap.
**********************************************************************/

#if __OBJC2__

// Maps class name to Class, for in-use classes only. NXStrValueMapPrototype.
OBJC_EXPORT NXMapTable *gdb_objc_realized_classes
    __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_3_1);

#else

// Hashes Classes, for all known classes. Custom prototype.
OBJC_EXPORT NXHashTable *_objc_debug_class_hash
    __OSX_AVAILABLE_STARTING(__MAC_10_2, __IPHONE_NA);

#endif


/***********************************************************************
* Non-pointer isa
**********************************************************************/

#if __OBJC2__

// Extract isa pointer from an isa field.
// (Class)(isa & mask) == class pointer
OBJC_EXPORT const uintptr_t objc_debug_isa_class_mask
    __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_7_0);

// Extract magic cookie from an isa field.
// (isa & magic_mask) == magic_value
OBJC_EXPORT const uintptr_t objc_debug_isa_magic_mask
    __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_7_0);
OBJC_EXPORT const uintptr_t objc_debug_isa_magic_value
    __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_7_0);

#endif


/***********************************************************************
* Tagged pointer decoding
**********************************************************************/
#if __OBJC2__

// if (obj & mask) obj is a tagged pointer object
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_mask
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

// tag_slot = (obj >> slot_shift) & slot_mask
OBJC_EXPORT unsigned int objc_debug_taggedpointer_slot_shift
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_slot_mask
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

// class = classes[tag_slot]
OBJC_EXPORT Class objc_debug_taggedpointer_classes[]
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

// payload = (obj << payload_lshift) >> payload_rshift
// Payload signedness is determined by the signedness of the right-shift.
OBJC_EXPORT unsigned int objc_debug_taggedpointer_payload_lshift
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);
OBJC_EXPORT unsigned int objc_debug_taggedpointer_payload_rshift
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

#endif


/***********************************************************************
* Breakpoints in objc_msgSend for debugger stepping.
* The array is a {0,0} terminated list of addresses. 
* Each address is one of the following:
* OBJC_MESSENGER_START:    Address is the start of a messenger function.
* OBJC_MESSENGER_END_FAST: Address is a jump insn that calls an IMP.
* OBJC_MESSENGER_END_SLOW: Address is some insn in the slow lookup path.
* OBJC_MESSENGER_END_NIL:  Address is a return insn for messages to nil.
* 
* Every path from OBJC_MESSENGER_START should reach some OBJC_MESSENGER_END.
* At all ENDs, the stack and parameter register state is the same as START.
*
* In some cases, the END_FAST case jumps to something other than the
* method's implementation. In those cases the jump's destination will 
* be another function that is marked OBJC_MESSENGER_START.
**********************************************************************/
#if __OBJC2__

#define OBJC_MESSENGER_START    1
#define OBJC_MESSENGER_END_FAST 2
#define OBJC_MESSENGER_END_SLOW 3
#define OBJC_MESSENGER_END_NIL  4

struct objc_messenger_breakpoint {
    uintptr_t address;
    uintptr_t kind;
};

OBJC_EXPORT struct objc_messenger_breakpoint 
gdb_objc_messenger_breakpoints[]
    __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0);

#endif


#ifndef OBJC_NO_GC

/***********************************************************************
 * Garbage Collector heap dump
**********************************************************************/

/* Dump GC heap; if supplied the name is returned in filenamebuffer.  Returns YES on success. */
OBJC_EXPORT BOOL objc_dumpHeap(char *filenamebuffer, unsigned long length)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_NA);

#define OBJC_HEAP_DUMP_FILENAME_FORMAT "/tmp/objc-gc-heap-dump-%d-%d"

#endif

__END_DECLS

#endif

#endif
