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
/*	maptable.m
  	Copyright 1990-1996 NeXT Software, Inc.
	Created by Bertrand Serlet, August 1990
 */


#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "objc-private.h"
#include "maptable.h"
#include "hashtable2.h"


/******		Macros and utilities	****************************/

#if defined(DEBUG)
    #define INLINE	
#else
    #define INLINE inline
#endif

typedef struct _MapPair {
    const void	*key;
    const void	*value;
} MapPair;

static INLINE unsigned xorHash(unsigned hash) { 
    unsigned xored = (hash & 0xffff) ^ (hash >> 16);
    return ((xored * 65521) + hash);
}

static INLINE unsigned bucketOf(NXMapTable *table, const void *key) {
    unsigned	hash = (table->prototype->hash)(table, key);
    return hash & table->nbBucketsMinusOne;
}

static INLINE int isEqual(NXMapTable *table, const void *key1, const void *key2) {
    return (key1 == key2) ? 1 : (table->prototype->isEqual)(table, key1, key2);
}

static INLINE unsigned nextIndex(NXMapTable *table, unsigned index) {
    return (index + 1) & table->nbBucketsMinusOne;
}

static INLINE void *allocBuckets(void *z, unsigned nb) {
    MapPair	*pairs = 1+(MapPair *)malloc_zone_malloc((malloc_zone_t *)z, ((nb+1) * sizeof(MapPair)));
    MapPair	*pair = pairs;
    while (nb--) { pair->key = NX_MAPNOTAKEY; pair->value = NULL; pair++; }
    return pairs;
}

static INLINE void freeBuckets(void *p) {
    free(-1+(MapPair *)p);
}

/*****		Global data and bootstrap	**********************/

static int isEqualPrototype (const void *info, const void *data1, const void *data2) {
    NXHashTablePrototype        *proto1 = (NXHashTablePrototype *) data1;
    NXHashTablePrototype        *proto2 = (NXHashTablePrototype *) data2;

    return (proto1->hash == proto2->hash) && (proto1->isEqual == proto2->isEqual) && (proto1->free == proto2->free) && (proto1->style == proto2->style);
    };

static uintptr_t hashPrototype (const void *info, const void *data) {
    NXHashTablePrototype        *proto = (NXHashTablePrototype *) data;

    return NXPtrHash(info, (void*)proto->hash) ^ NXPtrHash(info, (void*)proto->isEqual) ^ NXPtrHash(info, (void*)proto->free) ^ (uintptr_t) proto->style;
    };

static NXHashTablePrototype protoPrototype = {
    hashPrototype, isEqualPrototype, NXNoEffectFree, 0
};

static NXHashTable *prototypes = NULL;
	/* table of all prototypes */

/****		Fundamentals Operations			**************/

NXMapTable *NXCreateMapTableFromZone(NXMapTablePrototype prototype, unsigned capacity, void *z) {
    NXMapTable			*table = (NXMapTable *)malloc_zone_malloc((malloc_zone_t *)z, sizeof(NXMapTable));
    NXMapTablePrototype		*proto;
    if (! prototypes) prototypes = NXCreateHashTable(protoPrototype, 0, NULL);
    if (! prototype.hash || ! prototype.isEqual || ! prototype.free || prototype.style) {
	_objc_inform("*** NXCreateMapTable: invalid creation parameters\n");
	return NULL;
    }
    proto = (NXMapTablePrototype *)NXHashGet(prototypes, &prototype); 
    if (! proto) {
	proto = (NXMapTablePrototype *)malloc(sizeof(NXMapTablePrototype));
	*proto = prototype;
    	(void)NXHashInsert(prototypes, proto);
    }
    table->prototype = proto; table->count = 0;
    table->nbBucketsMinusOne = exp2u(log2u(capacity)+1) - 1;
    table->buckets = allocBuckets(z, table->nbBucketsMinusOne + 1);
    return table;
}

NXMapTable *NXCreateMapTable(NXMapTablePrototype prototype, unsigned capacity) {
    return NXCreateMapTableFromZone(prototype, capacity, malloc_default_zone());
}

void NXFreeMapTable(NXMapTable *table) {
    NXResetMapTable(table);
    freeBuckets(table->buckets);
    free(table);
}

void NXResetMapTable(NXMapTable *table) {
    MapPair	*pairs = (MapPair *)table->buckets;
    void	(*freeProc)(struct _NXMapTable *, void *, void *) = table->prototype->free;
    unsigned	index = table->nbBucketsMinusOne + 1;
    while (index--) {
	if (pairs->key != NX_MAPNOTAKEY) {
	    freeProc(table, (void *)pairs->key, (void *)pairs->value);
	    pairs->key = NX_MAPNOTAKEY; pairs->value = NULL;
	}
	pairs++;
    }
    table->count = 0;
}

BOOL NXCompareMapTables(NXMapTable *table1, NXMapTable *table2) {
    if (table1 == table2) return YES;
    if (table1->count != table2->count) return NO;
    else {
	const void *key;
	const void *value;
	NXMapState	state = NXInitMapState(table1);
	while (NXNextMapState(table1, &state, &key, &value)) {
	    if (NXMapMember(table2, key, (void**)&value) == NX_MAPNOTAKEY) return NO;
	}
	return YES;
    }
}

unsigned NXCountMapTable(NXMapTable *table) { return table->count; }

static INLINE void *_NXMapMember(NXMapTable *table, const void *key, void **value) {
    MapPair	*pairs = (MapPair *)table->buckets;
    unsigned	index = bucketOf(table, key);
    MapPair	*pair = pairs + index;
    if (pair->key == NX_MAPNOTAKEY) return NX_MAPNOTAKEY;
    if (isEqual(table, pair->key, key)) {
	*value = (void *)pair->value;
	return (void *)pair->key;
    } else {
	unsigned	index2 = index;
	while ((index2 = nextIndex(table, index2)) != index) {
	    pair = pairs + index2;
	    if (pair->key == NX_MAPNOTAKEY) return NX_MAPNOTAKEY;
	    if (isEqual(table, pair->key, key)) {
	    	*value = (void *)pair->value;
		return (void *)pair->key;
	    }
	}
	return NX_MAPNOTAKEY;
    }
}

void *NXMapMember(NXMapTable *table, const void *key, void **value) {
    return _NXMapMember(table, key, value);
}

void *NXMapGet(NXMapTable *table, const void *key) {
    void	*value;
    return (_NXMapMember(table, key, &value) != NX_MAPNOTAKEY) ? value : NULL;
}

static void _NXMapRehash(NXMapTable *table) {
    MapPair	*pairs = (MapPair *)table->buckets;
    MapPair	*pair = pairs;
    unsigned	numBuckets = table->nbBucketsMinusOne + 1;
    unsigned	index = numBuckets;
    unsigned	oldCount = table->count;
    
    table->nbBucketsMinusOne = 2 * numBuckets - 1;
    table->count = 0; 
    table->buckets = allocBuckets(malloc_zone_from_ptr(table), table->nbBucketsMinusOne + 1);
    while (index--) {
	if (pair->key != NX_MAPNOTAKEY) {
	    (void)NXMapInsert(table, pair->key, pair->value);
	}
	pair++;
    }
    if (oldCount != table->count)
	_objc_inform("*** maptable: count differs after rehashing; probably indicates a broken invariant: there are x and y such as isEqual(x, y) is TRUE but hash(x) != hash (y)\n");
    freeBuckets(pairs);
}

void *NXMapInsert(NXMapTable *table, const void *key, const void *value) {
    MapPair	*pairs = (MapPair *)table->buckets;
    unsigned	index = bucketOf(table, key);
    MapPair	*pair = pairs + index;
    if (key == NX_MAPNOTAKEY) {
	_objc_inform("*** NXMapInsert: invalid key: -1\n");
	return NULL;
    }

    unsigned numBuckets = table->nbBucketsMinusOne + 1;

    if (pair->key == NX_MAPNOTAKEY) {
	pair->key = key; pair->value = value;
	table->count++;
	if (table->count * 4 > numBuckets * 3) _NXMapRehash(table);
	return NULL;
    }
    
    if (isEqual(table, pair->key, key)) {
	const void	*old = pair->value;
	if (old != value) pair->value = value;/* avoid writing unless needed! */
	return (void *)old;
    } else if (table->count == numBuckets) {
	/* no room: rehash and retry */
	_NXMapRehash(table);
	return NXMapInsert(table, key, value);
    } else {
	unsigned	index2 = index;
	while ((index2 = nextIndex(table, index2)) != index) {
	    pair = pairs + index2;
	    if (pair->key == NX_MAPNOTAKEY) {
              pair->key = key; pair->value = value;
		table->count++;
		if (table->count * 4 > numBuckets * 3) _NXMapRehash(table);
		return NULL;
	    }
	    if (isEqual(table, pair->key, key)) {
		const void	*old = pair->value;
		if (old != value) pair->value = value;/* avoid writing unless needed! */
		return (void *)old;
	    }
	}
	/* no room: can't happen! */
	_objc_inform("**** NXMapInsert: bug\n");
	return NULL;
    }
}

static int mapRemove = 0;

void *NXMapRemove(NXMapTable *table, const void *key) {
    MapPair	*pairs = (MapPair *)table->buckets;
    unsigned	index = bucketOf(table, key);
    MapPair	*pair = pairs + index;
    unsigned	chain = 1; /* number of non-nil pairs in a row */
    int		found = 0;
    const void	*old = NULL;
    if (pair->key == NX_MAPNOTAKEY) return NULL;
    mapRemove ++;
    /* compute chain */
    {
	unsigned	index2 = index;
	if (isEqual(table, pair->key, key)) {found ++; old = pair->value; }
	while ((index2 = nextIndex(table, index2)) != index) {
	    pair = pairs + index2;
	    if (pair->key == NX_MAPNOTAKEY) break;
	    if (isEqual(table, pair->key, key)) {found ++; old = pair->value; }
	    chain++;
	}
    }
    if (! found) return NULL;
    if (found != 1) _objc_inform("**** NXMapRemove: incorrect table\n");
    /* remove then reinsert */
    {
	MapPair	buffer[16];
	MapPair	*aux = (chain > 16) ? (MapPair *)malloc(sizeof(MapPair)*(chain-1)) : buffer;
	unsigned	auxnb = 0;
	int	nb = chain;
	unsigned	index2 = index;
	while (nb--) {
	    pair = pairs + index2;
	    if (! isEqual(table, pair->key, key)) aux[auxnb++] = *pair;
	    pair->key = NX_MAPNOTAKEY; pair->value = NULL;
	    index2 = nextIndex(table, index2);
	}
	table->count -= chain;
	if (auxnb != chain-1) _objc_inform("**** NXMapRemove: bug\n");
	while (auxnb--) NXMapInsert(table, aux[auxnb].key, aux[auxnb].value);
	if (chain > 16) free(aux);
    }
    return (void *)old;
}

NXMapState NXInitMapState(NXMapTable *table) {
    NXMapState	state;
    state.index = table->nbBucketsMinusOne + 1;
    return state;
}
    
int NXNextMapState(NXMapTable *table, NXMapState *state, const void **key, const void **value) {
    MapPair	*pairs = (MapPair *)table->buckets;
    while (state->index--) {
	MapPair	*pair = pairs + state->index;
	if (pair->key != NX_MAPNOTAKEY) {
	    *key = pair->key; *value = pair->value;
	    return YES;
	}
    }
    return NO;
}


/***********************************************************************
* NXMapKeyCopyingInsert
* Like NXMapInsert, but strdups the key if necessary.
* Used to prevent stale pointers when bundles are unloaded.
**********************************************************************/
void *NXMapKeyCopyingInsert(NXMapTable *table, const void *key, const void *value)
{
    void *realKey; 
    void *realValue = NULL;

    if ((realKey = NXMapMember(table, key, &realValue)) != NX_MAPNOTAKEY) {
        // key DOES exist in table - use table's key for insertion
    } else {
        // key DOES NOT exist in table - copy the new key before insertion
        realKey = (void *)strdup((char *)key);
    }
    return NXMapInsert(table, realKey, value);
}


/***********************************************************************
* NXMapKeyFreeingRemove
* Like NXMapRemove, but frees the existing key if necessary.
* Used to prevent stale pointers when bundles are unloaded.
**********************************************************************/
void *NXMapKeyFreeingRemove(NXMapTable *table, const void *key)
{
    void *realKey;
    void *realValue = NULL;

    if ((realKey = NXMapMember(table, key, &realValue)) != NX_MAPNOTAKEY) {
        // key DOES exist in table - remove pair and free key
        realValue = NXMapRemove(table, realKey);
        free(realKey); // the key from the table, not necessarily the one given
        return realValue;
    } else {
        // key DOES NOT exist in table - nothing to do
        return NULL;
    }
}


/****		Conveniences		*************************************/

static unsigned _mapPtrHash(NXMapTable *table, const void *key) {
#ifdef __LP64__
    return (unsigned)(((uintptr_t)key) >> 3);
#else
    return ((uintptr_t)key) >> 2;
#endif
}
    
static unsigned _mapStrHash(NXMapTable *table, const void *key) {
    unsigned		hash = 0;
    unsigned char	*s = (unsigned char *)key;
    /* unsigned to avoid a sign-extend */
    /* unroll the loop */
    if (s) for (; ; ) { 
	if (*s == '\0') break;
	hash ^= *s++;
	if (*s == '\0') break;
	hash ^= *s++ << 8;
	if (*s == '\0') break;
	hash ^= *s++ << 16;
	if (*s == '\0') break;
	hash ^= *s++ << 24;
    }
    return xorHash(hash);
}
    
static int _mapPtrIsEqual(NXMapTable *table, const void *key1, const void *key2) {
    return key1 == key2;
}

static int _mapStrIsEqual(NXMapTable *table, const void *key1, const void *key2) {
    if (key1 == key2) return YES;
    if (! key1) return ! strlen ((char *) key2);
    if (! key2) return ! strlen ((char *) key1);
    if (((char *) key1)[0] != ((char *) key2)[0]) return NO;
    return (strcmp((char *) key1, (char *) key2)) ? NO : YES;
}
    
static void _mapNoFree(NXMapTable *table, void *key, void *value) {}

const NXMapTablePrototype NXPtrValueMapPrototype = {
    _mapPtrHash, _mapPtrIsEqual, _mapNoFree, 0
};

const NXMapTablePrototype NXStrValueMapPrototype = {
    _mapStrHash, _mapStrIsEqual, _mapNoFree, 0
};


#if !__OBJC2__  &&  !TARGET_OS_WIN32

/* This only works with class Object, which is unavailable. */

/* Method prototypes */
@interface DoesNotExist
+ (id)class;
+ (id)initialize;
- (id)description;
- (const char *)UTF8String;
- (unsigned long)hash;
- (BOOL)isEqual:(id)object;
- (void)free;
@end

static unsigned _mapObjectHash(NXMapTable *table, const void *key) {
    return [(id)key hash];
}
    
static int _mapObjectIsEqual(NXMapTable *table, const void *key1, const void *key2) {
    return [(id)key1 isEqual:(id)key2];
}

static void _mapObjectFree(NXMapTable *table, void *key, void *value) {
    [(id)key free];
}

const NXMapTablePrototype NXObjectMapPrototype = {
    _mapObjectHash, _mapObjectIsEqual, _mapObjectFree, 0
};

#endif
