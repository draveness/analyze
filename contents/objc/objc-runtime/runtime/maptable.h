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
/*	maptable.h
	Scalable hash table of mappings.
	Bertrand, August 1990
	Copyright 1990-1996 NeXT Software, Inc.
*/

#ifndef _OBJC_MAPTABLE_H_
#define _OBJC_MAPTABLE_H_

#ifndef _OBJC_PRIVATE_H_
#   define OBJC_MAP_AVAILABILITY __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_0,__MAC_10_1, __IPHONE_NA,__IPHONE_NA);
#else
#   define OBJC_MAP_AVAILABILITY
#endif

#include <objc/objc.h>

__BEGIN_DECLS

/***************	Definitions		***************/

    /* This module allows hashing of arbitrary associations [key -> value].  Keys and values must be pointers or integers, and client is responsible for allocating/deallocating this data.  A deallocation call-back is provided.
    NX_MAPNOTAKEY (-1) is used internally as a marker, and therefore keys must always be different from -1.
    As well-behaved scalable data structures, hash tables double in size when they start becoming full, thus guaranteeing both average constant time access and linear size. */

typedef struct _NXMapTable {
    /* private data structure; may change */
    const struct _NXMapTablePrototype	*prototype;
    unsigned	count;
    unsigned	nbBucketsMinusOne;
    void	*buckets;
} NXMapTable OBJC_MAP_AVAILABILITY;

typedef struct _NXMapTablePrototype {
    unsigned	(*hash)(NXMapTable *, const void *key);
    int		(*isEqual)(NXMapTable *, const void *key1, const void *key2);
    void	(*free)(NXMapTable *, void *key, void *value);
    int		style; /* reserved for future expansion; currently 0 */
} NXMapTablePrototype OBJC_MAP_AVAILABILITY;
    
    /* invariants assumed by the implementation: 
	A - key != -1
	B - key1 == key2 => hash(key1) == hash(key2)
	    when key varies over time, hash(key) must remain invariant
	    e.g. if string key, the string must not be changed
	C - isEqual(key1, key2) => key1 == key2
    */

#define NX_MAPNOTAKEY	((void *)(-1))

/***************	Functions		***************/

OBJC_EXPORT NXMapTable *NXCreateMapTableFromZone(NXMapTablePrototype prototype, unsigned capacity, void *z) OBJC_MAP_AVAILABILITY;
OBJC_EXPORT NXMapTable *NXCreateMapTable(NXMapTablePrototype prototype, unsigned capacity) OBJC_MAP_AVAILABILITY;
    /* capacity is only a hint; 0 creates a small table */

OBJC_EXPORT void NXFreeMapTable(NXMapTable *table) OBJC_MAP_AVAILABILITY;
    /* call free for each pair, and recovers table */
	
OBJC_EXPORT void NXResetMapTable(NXMapTable *table) OBJC_MAP_AVAILABILITY;
    /* free each pair; keep current capacity */

OBJC_EXPORT BOOL NXCompareMapTables(NXMapTable *table1, NXMapTable *table2) OBJC_MAP_AVAILABILITY;
    /* Returns YES if the two sets are equal (each member of table1 in table2, and table have same size) */

OBJC_EXPORT unsigned NXCountMapTable(NXMapTable *table) OBJC_MAP_AVAILABILITY;
    /* current number of data in table */
	
OBJC_EXPORT void *NXMapMember(NXMapTable *table, const void *key, void **value) OBJC_MAP_AVAILABILITY;
    /* return original table key or NX_MAPNOTAKEY.  If key is found, value is set */
	
OBJC_EXPORT void *NXMapGet(NXMapTable *table, const void *key) OBJC_MAP_AVAILABILITY;
    /* return original corresponding value or NULL.  When NULL need be stored as value, NXMapMember can be used to test for presence */
	
OBJC_EXPORT void *NXMapInsert(NXMapTable *table, const void *key, const void *value) OBJC_MAP_AVAILABILITY;
    /* override preexisting pair; Return previous value or NULL. */
	
OBJC_EXPORT void *NXMapRemove(NXMapTable *table, const void *key) OBJC_MAP_AVAILABILITY;
    /* previous value or NULL is returned */
	
/* Iteration over all elements of a table consists in setting up an iteration state and then to progress until all entries have been visited.  An example of use for counting elements in a table is:
    unsigned	count = 0;
    const MyKey	*key;
    const MyValue	*value;
    NXMapState	state = NXInitMapState(table);
    while(NXNextMapState(table, &state, &key, &value)) {
	count++;
    }
*/

typedef struct {int index;} NXMapState OBJC_MAP_AVAILABILITY;
    /* callers should not rely on actual contents of the struct */

OBJC_EXPORT NXMapState NXInitMapState(NXMapTable *table) OBJC_MAP_AVAILABILITY;

OBJC_EXPORT int NXNextMapState(NXMapTable *table, NXMapState *state, const void **key, const void **value) OBJC_MAP_AVAILABILITY;
    /* returns 0 when all elements have been visited */

/***************	Conveniences		***************/

OBJC_EXPORT const NXMapTablePrototype NXPtrValueMapPrototype OBJC_MAP_AVAILABILITY;
    /* hashing is pointer/integer hashing;
      isEqual is identity;
      free is no-op. */
OBJC_EXPORT const NXMapTablePrototype NXStrValueMapPrototype OBJC_MAP_AVAILABILITY;
    /* hashing is string hashing;
      isEqual is strcmp;
      free is no-op. */
OBJC_EXPORT const NXMapTablePrototype NXObjectMapPrototype  OBJC2_UNAVAILABLE;
    /* for objects; uses methods: hash, isEqual:, free, all for key. */

__END_DECLS

#endif /* _OBJC_MAPTABLE_H_ */
