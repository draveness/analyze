/*
 * Copyright (c) 2005-2007 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_RUNTIME_NEW_H
#define _OBJC_RUNTIME_NEW_H

#if __LP64__
typedef uint32_t mask_t;  // x86_64 & arm64 asm are less efficient with 16-bits
#else
typedef uint16_t mask_t;
#endif
typedef uintptr_t cache_key_t;

struct swift_class_t;


struct bucket_t {
private:
    cache_key_t _key;
    IMP _imp;

public:
    inline cache_key_t key() const { return _key; }
    inline IMP imp() const { return (IMP)_imp; }
    inline void setKey(cache_key_t newKey) { _key = newKey; }
    inline void setImp(IMP newImp) { _imp = newImp; }

    void set(cache_key_t newKey, IMP newImp);
};


struct cache_t {
    struct bucket_t *_buckets;
    mask_t _mask;
    mask_t _occupied;

public:
    struct bucket_t *buckets();
    mask_t mask();
    mask_t occupied();
    void incrementOccupied();
    void setBucketsAndMask(struct bucket_t *newBuckets, mask_t newMask);
    void initializeToEmpty();

    mask_t capacity();
    bool isConstantEmptyCache();
    bool canBeFreed();

    static size_t bytesForCapacity(uint32_t cap);
    static struct bucket_t * endMarker(struct bucket_t *b, uint32_t cap);

    void expand();
    void reallocate(mask_t oldCapacity, mask_t newCapacity);
    struct bucket_t * find(cache_key_t key, id receiver);

    static void bad_cache(id receiver, SEL sel, Class isa) __attribute__((noreturn));
};


// classref_t is unremapped class_t*
typedef struct classref * classref_t;

/***********************************************************************
* entsize_list_tt<Element, List, FlagMask>
* Generic implementation of an array of non-fragile structs.
*
* Element is the struct type (e.g. method_t)
* List is the specialization of entsize_list_tt (e.g. method_list_t)
* FlagMask is used to stash extra bits in the entsize field
*   (e.g. method list fixup markers)
**********************************************************************/
template <typename Element, typename List, uint32_t FlagMask>
struct entsize_list_tt {
    uint32_t entsizeAndFlags;
    uint32_t count;
    Element first;

    uint32_t entsize() const {
        return entsizeAndFlags & ~FlagMask;
    }
    uint32_t flags() const {
        return entsizeAndFlags & FlagMask;
    }

    Element& getOrEnd(uint32_t i) const { 
        assert(i <= count);
        return *(Element *)((uint8_t *)&first + i*entsize()); 
    }
    Element& get(uint32_t i) const { 
        assert(i < count);
        return getOrEnd(i);
    }

    size_t byteSize() const {
        return sizeof(*this) + (count-1)*entsize();
    }

    List *duplicate() const {
        return (List *)memdup(this, this->byteSize());
    }

    struct iterator;
    const iterator begin() const { 
        return iterator(*static_cast<const List*>(this), 0); 
    }
    iterator begin() { 
        return iterator(*static_cast<const List*>(this), 0); 
    }
    const iterator end() const { 
        return iterator(*static_cast<const List*>(this), count); 
    }
    iterator end() { 
        return iterator(*static_cast<const List*>(this), count); 
    }

    struct iterator {
        uint32_t entsize;
        uint32_t index;  // keeping track of this saves a divide in operator-
        Element* element;

        typedef std::random_access_iterator_tag iterator_category;
        typedef Element value_type;
        typedef ptrdiff_t difference_type;
        typedef Element* pointer;
        typedef Element& reference;

        iterator() { }

        iterator(const List& list, uint32_t start = 0)
            : entsize(list.entsize())
            , index(start)
            , element(&list.getOrEnd(start))
        { }

        const iterator& operator += (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element + delta*entsize);
            index += (int32_t)delta;
            return *this;
        }
        const iterator& operator -= (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element - delta*entsize);
            index -= (int32_t)delta;
            return *this;
        }
        const iterator operator + (ptrdiff_t delta) const {
            return iterator(*this) += delta;
        }
        const iterator operator - (ptrdiff_t delta) const {
            return iterator(*this) -= delta;
        }

        iterator& operator ++ () { *this += 1; return *this; }
        iterator& operator -- () { *this -= 1; return *this; }
        iterator operator ++ (int) {
            iterator result(*this); *this += 1; return result;
        }
        iterator operator -- (int) {
            iterator result(*this); *this -= 1; return result;
        }

        ptrdiff_t operator - (const iterator& rhs) const {
            return (ptrdiff_t)this->index - (ptrdiff_t)rhs.index;
        }

        Element& operator * () const { return *element; }
        Element* operator -> () const { return element; }

        operator Element& () const { return *element; }

        bool operator == (const iterator& rhs) const {
            return this->element == rhs.element;
        }
        bool operator != (const iterator& rhs) const {
            return this->element != rhs.element;
        }

        bool operator < (const iterator& rhs) const {
            return this->element < rhs.element;
        }
        bool operator > (const iterator& rhs) const {
            return this->element > rhs.element;
        }
    };
};


struct method_t {
    SEL name;
    const char *types;
    IMP imp;

    struct SortBySELAddress :
        public std::binary_function<const method_t&,
                                    const method_t&, bool>
    {
        bool operator() (const method_t& lhs,
                         const method_t& rhs)
        { return lhs.name < rhs.name; }
    };
};

struct ivar_t {
#if __x86_64__
    // *offset was originally 64-bit on some x86_64 platforms.
    // We read and write only 32 bits of it.
    // Some metadata provides all 64 bits. This is harmless for unsigned 
    // little-endian values.
    // Some code uses all 64 bits. class_addIvar() over-allocates the 
    // offset for their benefit.
#endif
    int32_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use alignment() instead
    uint32_t alignment_raw;
    uint32_t size;

    uint32_t alignment() const {
        if (alignment_raw == ~(uint32_t)0) return 1U << WORD_SHIFT;
        return 1 << alignment_raw;
    }
};

struct property_t {
    const char *name;
    const char *attributes;
};

// Two bits of entsize are used for fixup markers.
struct method_list_t : entsize_list_tt<method_t, method_list_t, 0x3> {
    bool isFixedUp() const;
    void setFixedUp();

    uint32_t indexOfMethod(const method_t *meth) const {
        uint32_t i = 
            (uint32_t)(((uintptr_t)meth - (uintptr_t)this) / entsize());
        assert(i < count);
        return i;
    }
};

struct ivar_list_t : entsize_list_tt<ivar_t, ivar_list_t, 0> {
};

struct property_list_t : entsize_list_tt<property_t, property_list_t, 0> {
};


typedef uintptr_t protocol_ref_t;  // protocol_t *, but unremapped

// Values for protocol_t->flags
#define PROTOCOL_FIXED_UP_2 (1<<31)  // must never be set by compiler
#define PROTOCOL_FIXED_UP_1 (1<<30)  // must never be set by compiler

#define PROTOCOL_FIXED_UP_MASK (PROTOCOL_FIXED_UP_1 | PROTOCOL_FIXED_UP_2)

struct protocol_t : objc_object {
    const char *mangledName;
    struct protocol_list_t *protocols;
    method_list_t *instanceMethods;
    method_list_t *classMethods;
    method_list_t *optionalInstanceMethods;
    method_list_t *optionalClassMethods;
    property_list_t *instanceProperties;
    uint32_t size;   // sizeof(protocol_t)
    uint32_t flags;
    // Fields below this point are not always present on disk.
    const char **extendedMethodTypes;
    const char *_demangledName;

    const char *demangledName();

    const char *nameForLogging() {
        return demangledName();
    }

    bool isFixedUp() const;
    void setFixedUp();

    bool hasExtendedMethodTypesField() const {
        return size >= (offsetof(protocol_t, extendedMethodTypes) 
                        + sizeof(extendedMethodTypes));
    }
    bool hasExtendedMethodTypes() const {
        return hasExtendedMethodTypesField() && extendedMethodTypes;
    }
};

struct protocol_list_t {
    // count is 64-bit by accident. 
    uintptr_t count;
    protocol_ref_t list[0]; // variable-size

    size_t byteSize() const {
        return sizeof(*this) + count*sizeof(list[0]);
    }

    protocol_list_t *duplicate() const {
        return (protocol_list_t *)memdup(this, this->byteSize());
    }

    typedef protocol_ref_t* iterator;
    typedef const protocol_ref_t* const_iterator;

    const_iterator begin() const {
        return list;
    }
    iterator begin() {
        return list;
    }
    const_iterator end() const {
        return list + count;
    }
    iterator end() {
        return list + count;
    }
};

struct locstamped_category_t {
    category_t *cat;
    struct header_info *hi;
};

struct locstamped_category_list_t {
    uint32_t count;
#if __LP64__
    uint32_t reserved;
#endif
    locstamped_category_t list[0];
};


// class_data_bits_t is the class_t->data field (class_rw_t pointer plus flags)
// The extra bits are optimized for the retain/release and alloc/dealloc paths.

// Values for class_ro_t->flags
// These are emitted by the compiler and are part of the ABI. 
// class is a metaclass
#define RO_META               (1<<0)
// class is a root class
#define RO_ROOT               (1<<1)
// class has .cxx_construct/destruct implementations
#define RO_HAS_CXX_STRUCTORS  (1<<2)
// class has +load implementation
// #define RO_HAS_LOAD_METHOD    (1<<3)
// class has visibility=hidden set
#define RO_HIDDEN             (1<<4)
// class has attribute(objc_exception): OBJC_EHTYPE_$_ThisClass is non-weak
#define RO_EXCEPTION          (1<<5)
// this bit is available for reassignment
// #define RO_REUSE_ME           (1<<6) 
// class compiled with -fobjc-arc (automatic retain/release)
#define RO_IS_ARR             (1<<7)
// class has .cxx_destruct but no .cxx_construct (with RO_HAS_CXX_STRUCTORS)
#define RO_HAS_CXX_DTOR_ONLY  (1<<8)

// class is in an unloadable bundle - must never be set by compiler
#define RO_FROM_BUNDLE        (1<<29)
// class is unrealized future class - must never be set by compiler
#define RO_FUTURE             (1<<30)
// class is realized - must never be set by compiler
#define RO_REALIZED           (1<<31)

// Values for class_rw_t->flags
// These are not emitted by the compiler and are never used in class_ro_t. 
// Their presence should be considered in future ABI versions.
// class_t->data is class_rw_t, not class_ro_t
#define RW_REALIZED           (1<<31)
// class is unresolved future class
#define RW_FUTURE             (1<<30)
// class is initialized
#define RW_INITIALIZED        (1<<29)
// class is initializing
#define RW_INITIALIZING       (1<<28)
// class_rw_t->ro is heap copy of class_ro_t
#define RW_COPIED_RO          (1<<27)
// class allocated but not yet registered
#define RW_CONSTRUCTING       (1<<26)
// class allocated and registered
#define RW_CONSTRUCTED        (1<<25)
// GC:  class has unsafe finalize method
#define RW_FINALIZE_ON_MAIN_THREAD (1<<24)
// class +load has been called
#define RW_LOADED             (1<<23)
#if !SUPPORT_NONPOINTER_ISA
// class instances may have associative references
#define RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS (1<<22)
#endif
// class has instance-specific GC layout
#define RW_HAS_INSTANCE_SPECIFIC_LAYOUT (1 << 21)
// available for use
// #define RW_20       (1<<20)
// class has started realizing but not yet completed it
#define RW_REALIZING          (1<<19)

// NOTE: MORE RW_ FLAGS DEFINED BELOW


// Values for class_rw_t->flags or class_t->bits
// These flags are optimized for retain/release and alloc/dealloc
// 64-bit stores more of them in class_t->bits to reduce pointer indirection.

#if !__LP64__

// class or superclass has .cxx_construct implementation
#define RW_HAS_CXX_CTOR       (1<<18)
// class or superclass has .cxx_destruct implementation
#define RW_HAS_CXX_DTOR       (1<<17)
// class or superclass has default alloc/allocWithZone: implementation
// Note this is is stored in the metaclass.
#define RW_HAS_DEFAULT_AWZ    (1<<16)
// class's instances requires raw isa
// not tracked for 32-bit because it only applies to non-pointer isa
// #define RW_REQUIRES_RAW_ISA

// class is a Swift class
#define FAST_IS_SWIFT         (1UL<<0)
// class or superclass has default retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference
#define FAST_HAS_DEFAULT_RR   (1UL<<1)
// data pointer
#define FAST_DATA_MASK        0xfffffffcUL

#elif 1
// Leaks-compatible version that steals low bits only.

// class or superclass has .cxx_construct implementation
#define RW_HAS_CXX_CTOR       (1<<18)
// class or superclass has .cxx_destruct implementation
#define RW_HAS_CXX_DTOR       (1<<17)
// class or superclass has default alloc/allocWithZone: implementation
// Note this is is stored in the metaclass.
#define RW_HAS_DEFAULT_AWZ    (1<<16)

// class is a Swift class
#define FAST_IS_SWIFT           (1UL<<0)
// class or superclass has default retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference
#define FAST_HAS_DEFAULT_RR     (1UL<<1)
// class's instances requires raw isa
#define FAST_REQUIRES_RAW_ISA   (1UL<<2)
// data pointer
#define FAST_DATA_MASK          0x00007ffffffffff8UL

#else
// Leaks-incompatible version that steals lots of bits.

// class is a Swift class
#define FAST_IS_SWIFT           (1UL<<0)
// class's instances requires raw isa
#define FAST_REQUIRES_RAW_ISA   (1UL<<1)
// class or superclass has .cxx_destruct implementation
//   This bit is aligned with isa_t->hasCxxDtor to save an instruction.
#define FAST_HAS_CXX_DTOR       (1UL<<2)
// data pointer
#define FAST_DATA_MASK          0x00007ffffffffff8UL
// class or superclass has .cxx_construct implementation
#define FAST_HAS_CXX_CTOR       (1UL<<47)
// class or superclass has default alloc/allocWithZone: implementation
// Note this is is stored in the metaclass.
#define FAST_HAS_DEFAULT_AWZ    (1UL<<48)
// class or superclass has default retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference
#define FAST_HAS_DEFAULT_RR     (1UL<<49)
// summary bit for fast alloc path: !hasCxxCtor and 
//   !requiresRawIsa and instanceSize fits into shiftedSize
#define FAST_ALLOC              (1UL<<50)
// instance size in units of 16 bytes
//   or 0 if the instance size is too big in this field
//   This field must be LAST
#define FAST_SHIFTED_SIZE_SHIFT 51

// FAST_ALLOC means
//   FAST_HAS_CXX_CTOR is set
//   FAST_REQUIRES_RAW_ISA is not set
//   FAST_SHIFTED_SIZE is not zero
// FAST_ALLOC does NOT check FAST_HAS_DEFAULT_AWZ because that 
// bit is stored on the metaclass.
#define FAST_ALLOC_MASK  (FAST_HAS_CXX_CTOR | FAST_REQUIRES_RAW_ISA)
#define FAST_ALLOC_VALUE (0)

#endif


struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;
    
    const char * name;
    method_list_t * baseMethodList;
    protocol_list_t * baseProtocols;
    const ivar_list_t * ivars;

    const uint8_t * weakIvarLayout;
    property_list_t *baseProperties;

    method_list_t *baseMethods() const {
        return baseMethodList;
    }
};


/***********************************************************************
* list_array_tt<Element, List>
* Generic implementation for metadata that can be augmented by categories.
*
* Element is the underlying metadata type (e.g. method_t)
* List is the metadata's list type (e.g. method_list_t)
*
* A list_array_tt has one of three values:
* - empty
* - a pointer to a single list
* - an array of pointers to lists
*
* countLists/beginLists/endLists iterate the metadata lists
* count/begin/end iterate the underlying metadata elements
**********************************************************************/
template <typename Element, typename List>
class list_array_tt {
    struct array_t {
        uint32_t count;
        List* lists[0];

        static size_t byteSize(uint32_t count) {
            return sizeof(array_t) + count*sizeof(lists[0]);
        }
        size_t byteSize() {
            return byteSize(count);
        }
    };

 protected:
    class iterator {
        List **lists;
        List **listsEnd;
        typename List::iterator m, mEnd;

     public:
        iterator(List **begin, List **end) 
            : lists(begin), listsEnd(end)
        {
            if (begin != end) {
                m = (*begin)->begin();
                mEnd = (*begin)->end();
            }
        }

        const Element& operator * () const {
            return *m;
        }
        Element& operator * () {
            return *m;
        }

        bool operator != (const iterator& rhs) const {
            if (lists != rhs.lists) return true;
            if (lists == listsEnd) return false;  // m is undefined
            if (m != rhs.m) return true;
            return false;
        }

        const iterator& operator ++ () {
            assert(m != mEnd);
            m++;
            if (m == mEnd) {
                assert(lists != listsEnd);
                lists++;
                if (lists != listsEnd) {
                    m = (*lists)->begin();
                    mEnd = (*lists)->end();
                }
            }
            return *this;
        }
    };

 private:
    union {
        List* list;
        uintptr_t arrayAndFlag;
    };

    bool hasArray() const {
        return arrayAndFlag & 1;
    }

    array_t *array() {
        return (array_t *)(arrayAndFlag & ~1);
    }

    void setArray(array_t *array) {
        arrayAndFlag = (uintptr_t)array | 1;
    }

 public:

    uint32_t count() {
        uint32_t result = 0;
        for (auto lists = beginLists(), end = endLists(); 
             lists != end;
             ++lists)
        {
            result += (*lists)->count;
        }
        return result;
    }

    iterator begin() {
        return iterator(beginLists(), endLists());
    }

    iterator end() {
        List **e = endLists();
        return iterator(e, e);
    }


    uint32_t countLists() {
        if (hasArray()) {
            return array()->count;
        } else if (list) {
            return 1;
        } else {
            return 0;
        }
    }

    List** beginLists() {
        if (hasArray()) {
            return array()->lists;
        } else {
            return &list;
        }
    }

    List** endLists() {
        if (hasArray()) {
            return array()->lists + array()->count;
        } else if (list) {
            return &list + 1;
        } else {
            return &list;
        }
    }

    void attachLists(List* const * addedLists, uint32_t addedCount) {
        if (addedCount == 0) return;

        if (hasArray()) {
            // many lists -> many lists
            uint32_t oldCount = array()->count;
            uint32_t newCount = oldCount + addedCount;
            setArray((array_t *)realloc(array(), array_t::byteSize(newCount)));
            array()->count = newCount;
            memmove(array()->lists + addedCount, array()->lists, 
                    oldCount * sizeof(array()->lists[0]));
            memcpy(array()->lists, addedLists, 
                   addedCount * sizeof(array()->lists[0]));
        }
        else if (!list  &&  addedCount == 1) {
            // 0 lists -> 1 list
            list = addedLists[0];
        } 
        else {
            // 1 list -> many lists
            List* oldList = list;
            uint32_t oldCount = oldList ? 1 : 0;
            uint32_t newCount = oldCount + addedCount;
            setArray((array_t *)malloc(array_t::byteSize(newCount)));
            array()->count = newCount;
            if (oldList) array()->lists[addedCount] = oldList;
            memcpy(array()->lists, addedLists, 
                   addedCount * sizeof(array()->lists[0]));
        }
    }

    void tryFree() {
        if (hasArray()) {
            for (uint32_t i = 0; i < array()->count; i++) {
                try_free(array()->lists[i]);
            }
            try_free(array());
        }
        else if (list) {
            try_free(list);
        }
    }

    template<typename Result>
    Result duplicate() {
        Result result;

        if (hasArray()) {
            array_t *a = array();
            result.setArray((array_t *)memdup(a, a->byteSize()));
            for (uint32_t i = 0; i < a->count; i++) {
                result.array()->lists[i] = a->lists[i]->duplicate();
            }
        } else if (list) {
            result.list = list->duplicate();
        } else {
            result.list = nil;
        }

        return result;
    }
};


class method_array_t : 
    public list_array_tt<method_t, method_list_t> 
{
    typedef list_array_tt<method_t, method_list_t> Super;

 public:
    method_list_t **beginCategoryMethodLists() {
        return beginLists();
    }
    
    method_list_t **endCategoryMethodLists(Class cls);

    method_array_t duplicate() {
        return Super::duplicate<method_array_t>();
    }
};


class property_array_t : 
    public list_array_tt<property_t, property_list_t> 
{
    typedef list_array_tt<property_t, property_list_t> Super;

 public:
    property_array_t duplicate() {
        return Super::duplicate<property_array_t>();
    }
};


class protocol_array_t : 
    public list_array_tt<protocol_ref_t, protocol_list_t> 
{
    typedef list_array_tt<protocol_ref_t, protocol_list_t> Super;

 public:
    protocol_array_t duplicate() {
        return Super::duplicate<protocol_array_t>();
    }
};


struct class_rw_t {
    uint32_t flags;
    uint32_t version;

    const class_ro_t *ro;

    method_array_t methods;
    property_array_t properties;
    protocol_array_t protocols;

    Class firstSubclass;
    Class nextSiblingClass;

    char *demangledName;

    void setFlags(uint32_t set) 
    {
        OSAtomicOr32Barrier(set, &flags);
    }

    void clearFlags(uint32_t clear) 
    {
        OSAtomicXor32Barrier(clear, &flags);
    }

    // set and clear must not overlap
    void changeFlags(uint32_t set, uint32_t clear) 
    {
        assert((set & clear) == 0);

        uint32_t oldf, newf;
        do {
            oldf = flags;
            newf = (oldf | set) & ~clear;
        } while (!OSAtomicCompareAndSwap32Barrier(oldf, newf, (volatile int32_t *)&flags));
    }
};


struct class_data_bits_t {

    // Values are the FAST_ flags above.
    uintptr_t bits;
private:
    bool getBit(uintptr_t bit)
    {
        return bits & bit;
    }

#if FAST_ALLOC
    static uintptr_t updateFastAlloc(uintptr_t oldBits, uintptr_t change)
    {
        if (change & FAST_ALLOC_MASK) {
            if (((oldBits & FAST_ALLOC_MASK) == FAST_ALLOC_VALUE)  &&  
                ((oldBits >> FAST_SHIFTED_SIZE_SHIFT) != 0)) 
            {
                oldBits |= FAST_ALLOC;
            } else {
                oldBits &= ~FAST_ALLOC;
            }
        }
        return oldBits;
    }
#else
    static uintptr_t updateFastAlloc(uintptr_t oldBits, uintptr_t change) {
        return oldBits;
    }
#endif

    void setBits(uintptr_t set) 
    {
        uintptr_t oldBits;
        uintptr_t newBits;
        do {
            oldBits = LoadExclusive(&bits);
            newBits = updateFastAlloc(oldBits | set, set);
        } while (!StoreReleaseExclusive(&bits, oldBits, newBits));
    }

    void clearBits(uintptr_t clear) 
    {
        uintptr_t oldBits;
        uintptr_t newBits;
        do {
            oldBits = LoadExclusive(&bits);
            newBits = updateFastAlloc(oldBits & ~clear, clear);
        } while (!StoreReleaseExclusive(&bits, oldBits, newBits));
    }

public:

    class_rw_t* data() {
        return (class_rw_t *)(bits & FAST_DATA_MASK);
    }
    void setData(class_rw_t *newData)
    {
        assert(!data()  ||  (newData->flags & (RW_REALIZING | RW_FUTURE)));
        // Set during realization or construction only. No locking needed.
        bits = (bits & ~FAST_DATA_MASK) | (uintptr_t)newData;
    }

    bool hasDefaultRR() {
        return getBit(FAST_HAS_DEFAULT_RR);
    }
    void setHasDefaultRR() {
        setBits(FAST_HAS_DEFAULT_RR);
    }
    void setHasCustomRR() {
        clearBits(FAST_HAS_DEFAULT_RR);
    }

#if FAST_HAS_DEFAULT_AWZ
    bool hasDefaultAWZ() {
        return getBit(FAST_HAS_DEFAULT_AWZ);
    }
    void setHasDefaultAWZ() {
        setBits(FAST_HAS_DEFAULT_AWZ);
    }
    void setHasCustomAWZ() {
        clearBits(FAST_HAS_DEFAULT_AWZ);
    }
#else
    bool hasDefaultAWZ() {
        return data()->flags & RW_HAS_DEFAULT_AWZ;
    }
    void setHasDefaultAWZ() {
        data()->setFlags(RW_HAS_DEFAULT_AWZ);
    }
    void setHasCustomAWZ() {
        data()->clearFlags(RW_HAS_DEFAULT_AWZ);
    }
#endif

#if FAST_HAS_CXX_CTOR
    bool hasCxxCtor() {
        return getBit(FAST_HAS_CXX_CTOR);
    }
    void setHasCxxCtor() {
        setBits(FAST_HAS_CXX_CTOR);
    }
#else
    bool hasCxxCtor() {
        return data()->flags & RW_HAS_CXX_CTOR;
    }
    void setHasCxxCtor() {
        data()->setFlags(RW_HAS_CXX_CTOR);
    }
#endif

#if FAST_HAS_CXX_DTOR
    bool hasCxxDtor() {
        return getBit(FAST_HAS_CXX_DTOR);
    }
    void setHasCxxDtor() {
        setBits(FAST_HAS_CXX_DTOR);
    }
#else
    bool hasCxxDtor() {
        return data()->flags & RW_HAS_CXX_DTOR;
    }
    void setHasCxxDtor() {
        data()->setFlags(RW_HAS_CXX_DTOR);
    }
#endif

#if FAST_REQUIRES_RAW_ISA
    bool requiresRawIsa() {
        return getBit(FAST_REQUIRES_RAW_ISA);
    }
    void setRequiresRawIsa() {
        setBits(FAST_REQUIRES_RAW_ISA);
    }
#else
# if SUPPORT_NONPOINTER_ISA
#   error oops
# endif
    bool requiresRawIsa() {
        return true;
    }
    void setRequiresRawIsa() {
        // nothing
    }
#endif

#if FAST_ALLOC
    size_t fastInstanceSize() 
    {
        assert(bits & FAST_ALLOC);
        return (bits >> FAST_SHIFTED_SIZE_SHIFT) * 16;
    }
    void setFastInstanceSize(size_t newSize) 
    {
        // Set during realization or construction only. No locking needed.
        assert(data()->flags & RW_REALIZING);

        // Round up to 16-byte boundary, then divide to get 16-byte units
        newSize = ((newSize + 15) & ~15) / 16;
        
        uintptr_t newBits = newSize << FAST_SHIFTED_SIZE_SHIFT;
        if ((newBits >> FAST_SHIFTED_SIZE_SHIFT) == newSize) {
            int shift = WORD_BITS - FAST_SHIFTED_SIZE_SHIFT;
            uintptr_t oldBits = (bits << shift) >> shift;
            if ((oldBits & FAST_ALLOC_MASK) == FAST_ALLOC_VALUE) {
                newBits |= FAST_ALLOC;
            }
            bits = oldBits | newBits;
        }
    }

    bool canAllocFast() {
        return bits & FAST_ALLOC;
    }
#else
    size_t fastInstanceSize() {
        abort();
    }
    void setFastInstanceSize(size_t) {
        // nothing
    }
    bool canAllocFast() {
        return false;
    }
#endif

    bool isSwift() {
        return getBit(FAST_IS_SWIFT);
    }

    void setIsSwift() {
        setBits(FAST_IS_SWIFT);
    }
};


struct objc_class : objc_object {
    // Class ISA;
    Class superclass;
    cache_t cache;             // formerly cache pointer and vtable
    class_data_bits_t bits;    // class_rw_t * plus custom rr/alloc flags

    class_rw_t *data() { 
        return bits.data();
    }
    void setData(class_rw_t *newData) {
        bits.setData(newData);
    }

    void setInfo(uint32_t set) {
        assert(isFuture()  ||  isRealized());
        data()->setFlags(set);
    }

    void clearInfo(uint32_t clear) {
        assert(isFuture()  ||  isRealized());
        data()->clearFlags(clear);
    }

    // set and clear must not overlap
    void changeInfo(uint32_t set, uint32_t clear) {
        assert(isFuture()  ||  isRealized());
        assert((set & clear) == 0);
        data()->changeFlags(set, clear);
    }

    bool hasCustomRR() {
        return ! bits.hasDefaultRR();
    }
    void setHasDefaultRR() {
        assert(isInitializing());
        bits.setHasDefaultRR();
    }
    void setHasCustomRR(bool inherited = false);
    void printCustomRR(bool inherited);

    bool hasCustomAWZ() {
        return ! bits.hasDefaultAWZ();
    }
    void setHasDefaultAWZ() {
        assert(isInitializing());
        bits.setHasDefaultAWZ();
    }
    void setHasCustomAWZ(bool inherited = false);
    void printCustomAWZ(bool inherited);

    bool requiresRawIsa() {
        return bits.requiresRawIsa();
    }
    void setRequiresRawIsa(bool inherited = false);
    void printRequiresRawIsa(bool inherited);

    bool canAllocIndexed() {
        assert(!isFuture());
        return !requiresRawIsa();
    }
    bool canAllocFast() {
        assert(!isFuture());
        return bits.canAllocFast();
    }


    bool hasCxxCtor() {
        // addSubclass() propagates this flag from the superclass.
        assert(isRealized());
        return bits.hasCxxCtor();
    }
    void setHasCxxCtor() { 
        bits.setHasCxxCtor();
    }

    bool hasCxxDtor() {
        // addSubclass() propagates this flag from the superclass.
        assert(isRealized());
        return bits.hasCxxDtor();
    }
    void setHasCxxDtor() { 
        bits.setHasCxxDtor();
    }


    bool isSwift() {
        return bits.isSwift();
    }


#if SUPPORT_NONPOINTER_ISA
    // Tracked in non-pointer isas; not tracked otherwise
#else
    bool instancesHaveAssociatedObjects() {
        // this may be an unrealized future class in the CF-bridged case
        assert(isFuture()  ||  isRealized());
        return data()->flags & RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS;
    }

    void setInstancesHaveAssociatedObjects() {
        // this may be an unrealized future class in the CF-bridged case
        assert(isFuture()  ||  isRealized());
        setInfo(RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS);
    }
#endif

    bool shouldGrowCache() {
        return true;
    }

    void setShouldGrowCache(bool) {
        // fixme good or bad for memory use?
    }

    bool shouldFinalizeOnMainThread() {
        // finishInitializing() propagates this flag from the superclass.
        assert(isRealized());
        return data()->flags & RW_FINALIZE_ON_MAIN_THREAD;
    }

    void setShouldFinalizeOnMainThread() {
        assert(isRealized());
        setInfo(RW_FINALIZE_ON_MAIN_THREAD);
    }

    bool isInitializing() {
        return getMeta()->data()->flags & RW_INITIALIZING;
    }

    void setInitializing() {
        assert(!isMetaClass());
        ISA()->setInfo(RW_INITIALIZING);
    }

    bool isInitialized() {
        return getMeta()->data()->flags & RW_INITIALIZED;
    }

    void setInitialized();

    bool isLoadable() {
        assert(isRealized());
        return true;  // any class registered for +load is definitely loadable
    }

    IMP getLoadMethod();

    // Locking: To prevent concurrent realization, hold runtimeLock.
    bool isRealized() {
        return data()->flags & RW_REALIZED;
    }

    // Returns true if this is an unrealized future class.
    // Locking: To prevent concurrent realization, hold runtimeLock.
    bool isFuture() { 
        return data()->flags & RW_FUTURE;
    }

    bool isMetaClass() {
        assert(this);
        assert(isRealized());
        return data()->ro->flags & RO_META;
    }

    // NOT identical to this->ISA when this is a metaclass
    Class getMeta() {
        if (isMetaClass()) return (Class)this;
        else return this->ISA();
    }

    bool isRootClass() {
        return superclass == nil;
    }
    bool isRootMetaclass() {
        return ISA() == (Class)this;
    }

    const char *mangledName() { 
        // fixme can't assert locks here
        assert(this);

        if (isRealized()  ||  isFuture()) {
            return data()->ro->name;
        } else {
            return ((const class_ro_t *)data())->name;
        }
    }
    
    const char *demangledName(bool realize = false);
    const char *nameForLogging();

    // May be unaligned depending on class's ivars.
    uint32_t unalignedInstanceSize() {
        assert(isRealized());
        return data()->ro->instanceSize;
    }

    // Class's ivar size rounded up to a pointer-size boundary.
    uint32_t alignedInstanceSize() {
        return word_align(unalignedInstanceSize());
    }

    size_t instanceSize(size_t extraBytes) {
        size_t size = alignedInstanceSize() + extraBytes;
        // CF requires all objects be at least 16 bytes.
        if (size < 16) size = 16;
        return size;
    }

    void setInstanceSize(uint32_t newSize) {
        assert(isRealized());
        if (newSize != data()->ro->instanceSize) {
            assert(data()->flags & RW_COPIED_RO);
            *const_cast<uint32_t *>(&data()->ro->instanceSize) = newSize;
        }
        bits.setFastInstanceSize(newSize);
    }
};


struct swift_class_t : objc_class {
    uint32_t flags;
    uint32_t instanceAddressOffset;
    uint32_t instanceSize;
    uint16_t instanceAlignMask;
    uint16_t reserved;

    uint32_t classSize;
    uint32_t classAddressOffset;
    void *description;
    // ...

    void *baseAddress() {
        return (void *)((uint8_t *)this - classAddressOffset);
    }
};


struct category_t {
    const char *name;
    classref_t cls;
    struct method_list_t *instanceMethods;
    struct method_list_t *classMethods;
    struct protocol_list_t *protocols;
    struct property_list_t *instanceProperties;

    method_list_t *methodsForMeta(bool isMeta) {
        if (isMeta) return classMethods;
        else return instanceMethods;
    }

    property_list_t *propertiesForMeta(bool isMeta) {
        if (isMeta) return nil; // classProperties;
        else return instanceProperties;
    }
};

struct objc_super2 {
    id receiver;
    Class current_class;
};

struct message_ref_t {
    IMP imp;
    SEL sel;
};


extern Method protocol_getMethod(protocol_t *p, SEL sel, bool isRequiredMethod, bool isInstanceMethod, bool recursive);

static inline void
foreach_realized_class_and_subclass_2(Class top, bool (^code)(Class)) 
{
    // runtimeLock.assertWriting();
    assert(top);
    Class cls = top;
    while (1) {
        if (!code(cls)) break;

        if (cls->data()->firstSubclass) {
            cls = cls->data()->firstSubclass;
        } else {
            while (!cls->data()->nextSiblingClass  &&  cls != top) {
                cls = cls->superclass;
            }
            if (cls == top) break;
            cls = cls->data()->nextSiblingClass;
        }
    }
}

static inline void
foreach_realized_class_and_subclass(Class top, void (^code)(Class)) 
{
    foreach_realized_class_and_subclass_2(top, ^bool(Class cls) { 
        code(cls); return true; 
    });
}

#endif
