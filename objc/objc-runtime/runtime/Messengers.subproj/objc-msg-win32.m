#include "objc-private.h"

// out-of-band parameter to objc_msgForward
#define kFwdMsgSend 1
#define kFwdMsgSendStret 0

// objc_msgSend parameters
#define SELF 8[ebp]
#define SUPER 8[ebp]
#define SELECTOR 12[ebp]
#define FIRST_ARG 16[ebp]

// objc_msgSend_stret parameters
#define STRUCT_ADDR 8[ebp]
#define SELF_STRET 12[ebp]
#define SUPER_STRET 12[ebp]
#define SELECTOR_STRET 16[ebp]

// objc_super parameter to sendSuper
#define super_receiver 0
#define super_class 4

// struct objc_class fields
#define isa 0
#define cache 32

// struct objc_method fields
#define method_name 0
#define method_imp 8

// struct objc_cache fields
#define mask 0
#define occupied 4
#define buckets 8

void *_objc_forward_handler = NULL;
void *_objc_forward_stret_handler = NULL;

__declspec(naked) Method _cache_getMethod(Class cls, SEL sel, IMP objc_msgForward_imp)
{
    __asm {
        push ebp
        mov ebp, esp

        mov ecx, SELECTOR
        mov edx, SELF

// CacheLookup WORD_RETURN, CACHE_GET
        push edi
        mov edi, cache[edx]

        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

MISS:
        xor eax, eax
        pop esi
        pop edi
        leave
        ret

HIT:
        mov ecx, FIRST_ARG
        cmp ecx, method_imp[eax]
        je MISS
        pop esi
        pop edi
        leave
        ret
    }
}

__declspec(naked) IMP _cache_getImp(Class cls, SEL sel)
{
    __asm {
        push ebp
        mov ebp, esp

        mov ecx, SELECTOR
        mov edx, SELF

// CacheLookup WORD_RETURN, CACHE_GET
        push edi
        mov edi, cache[edx]

        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

MISS:
        pop esi
        pop edi
        xor eax, eax
        leave
        ret

HIT:
        pop esi
        pop edi
        mov eax, method_imp[eax]
        leave
        ret
    }
}


OBJC_EXPORT __declspec(naked) id objc_msgSend(id a, SEL b, ...)
{
    __asm {
        push ebp
        mov ebp, esp

        // load receiver and selector
        mov ecx, SELECTOR
        mov eax, SELF

#if SUPPORT_GC
        // check whether selector is ignored
#error oops
#endif

        // check whether receiver is nil
        test eax, eax
        je NIL

        // receiver (in eax) is non-nil: search the cache
        mov edx, isa[eax]

        // CacheLookup WORD_RETURN, MSG_SEND
        push edi
        mov edi, cache[edx]
        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

HIT:
        mov eax, method_imp[eax]
        pop esi
        pop edi
        mov edx, kFwdMsgSend
        leave
        jmp eax

        // cache miss: search method lists
MISS:
        pop esi
        pop edi
        mov edx, SELF
        mov eax, isa[edx]

        // MethodTableLookup WORD_RETURN, MSG_SEND
        push eax
        push ecx
        push edx
        call _class_lookupMethodAndLoadCache3

        mov edx, kFwdMsgSend
        leave
        jmp eax

        // message send to nil: return zero
NIL:
        // eax is already zero
        mov edx, 0
        leave
        ret
    }
}


OBJC_EXPORT __declspec(naked) double objc_msgSend_fpret(id a, SEL b, ...)
{
    __asm {
        push ebp
        mov ebp, esp

        // load receiver and selector
        mov ecx, SELECTOR
        mov eax, SELF

#if SUPPORT_GC
        // check whether selector is ignored
#error oops
#endif

        // check whether receiver is nil
        test eax, eax
        je NIL

        // receiver (in eax) is non-nil: search the cache
        mov edx, isa[eax]

        // CacheLookup WORD_RETURN, MSG_SEND
        push edi
        mov edi, cache[edx]
        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

HIT:
        mov eax, method_imp[eax]
        pop esi
        pop edi
        mov edx, kFwdMsgSend
        leave
        jmp eax

        // cache miss: search method lists
MISS:
        pop esi
        pop edi
        mov edx, SELF
        mov eax, isa[edx]

        // MethodTableLookup WORD_RETURN, MSG_SEND
        push eax
        push ecx
        push edx
        call _class_lookupMethodAndLoadCache3

        mov edx, kFwdMsgSend
        leave
        jmp eax

        // message send to nil: return zero
NIL:
        fldz
        leave
        ret
    }
}


OBJC_EXPORT __declspec(naked) id objc_msgSendSuper(struct objc_super *a, SEL b, ...)
{
    __asm {
        push ebp
        mov ebp, esp

        // load class and selector
        mov eax, SUPER
        mov ecx, SELECTOR
        mov edx, super_class[eax]

#if SUPPORT_GC
        // check whether selector is ignored
#error oops
#endif

        // search the cache (class in edx)
        // CacheLookup WORD_RETURN, MSG_SENDSUPER
        push edi
        mov edi, cache[edx]
        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

HIT:
        mov eax, method_imp[eax]
        pop esi
        pop edi
        mov edx, SUPER
        mov edx, super_receiver[edx]
        mov SUPER, edx
        mov edx, kFwdMsgSend
        leave
        jmp eax

        // cache miss: search method lists
MISS:

        pop esi
        pop edi
        mov eax, SUPER
        mov edx, super_receiver[eax]
        mov SUPER, edx
        mov eax, super_class[eax]

        // MethodTableLookup WORD_RETURN, MSG_SENDSUPER
        push eax
        push ecx
        push edx
        call _class_lookupMethodAndLoadCache3

        mov edx, kFwdMsgSend
        leave
        jmp eax
    }
}


OBJC_EXPORT __declspec(naked) void objc_msgSend_stret(void)
{
    __asm {
        push ebp
        mov ebp, esp

        // load receiver and selector
        mov ecx, SELECTOR_STRET
        mov eax, SELF_STRET

#if SUPPORT_GC
        // check whether selector is ignored
#error oops
#endif

        // check whether receiver is nil
        test eax, eax
        je NIL

        // receiver (in eax) is non-nil: search the cache
        mov edx, isa[eax]

        // CacheLookup WORD_RETURN, MSG_SEND
        push edi
        mov edi, cache[edx]
        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

HIT:
        mov eax, method_imp[eax]
        pop esi
        pop edi
        mov edx, kFwdMsgSendStret
        leave
        jmp eax

        // cache miss: search method lists
MISS:
        pop esi
        pop edi
        mov edx, SELF_STRET
        mov eax, isa[edx]

        // MethodTableLookup WORD_RETURN, MSG_SEND
        push eax
        push ecx
        push edx
        call _class_lookupMethodAndLoadCache3

        mov edx, kFwdMsgSendStret
        leave
        jmp eax

        // message send to nil: return zero
NIL:
        // eax is already zero
        mov edx, 0
        leave
        ret
    }
}


OBJC_EXPORT __declspec(naked) id objc_msgSendSuper_stret(struct objc_super *a, SEL b, ...)
{
    __asm {
        push ebp
        mov ebp, esp

        // load class and selector
        mov eax, SUPER_STRET
        mov ecx, SELECTOR_STRET
        mov edx, super_class[eax]

#if SUPPORT_GC
        // check whether selector is ignored
#error oops
#endif

        // search the cache (class in edx)
        // CacheLookup WORD_RETURN, MSG_SENDSUPER
        push edi
        mov edi, cache[edx]
        push esi
        mov esi, mask[edi]
        mov edx, ecx
        shr edx, 2
SCAN:
        and edx, esi
        mov eax, buckets[edi][edx*4]
        test eax, eax
        je MISS
        cmp ecx, method_name[eax]
        je HIT
        add edx, 1
        jmp SCAN

HIT:
        mov eax, method_imp[eax]
        pop esi
        pop edi
        mov edx, SUPER_STRET
        mov edx, super_receiver[edx]
        mov SUPER_STRET, edx
        mov edx, kFwdMsgSendStret
        leave
        jmp eax

        // cache miss: search method lists
MISS:

        pop esi
        pop edi
        mov eax, SUPER_STRET
        mov edx, super_receiver[eax]
        mov SUPER_STRET, edx
        mov eax, super_class[eax]

        // MethodTableLookup WORD_RETURN, MSG_SENDSUPER
        push eax
        push ecx
        push edx
        call _class_lookupMethodAndLoadCache3

        mov edx, kFwdMsgSendStret
        leave
        jmp eax
    }
}


OBJC_EXPORT __declspec(naked) id _objc_msgForward(id a, SEL b, ...)
{
    __asm {
        mov ecx, _objc_forward_handler
        jmp ecx
    }
}

OBJC_EXPORT __declspec(naked) id _objc_msgForward_stret(id a, SEL b, ...)
{
    __asm {
        mov ecx, _objc_forward_stret_handler
        jmp ecx
    }
}


__declspec(naked) id _objc_msgForward_cached(id a, SEL b, ...)
{
    __asm {
        cmp edx, kFwdMsgSendStret
        je  STRET
        jmp _objc_msgForward
STRET:
        jmp _objc_msgForward_stret
    }
}


OBJC_EXPORT __declspec(naked) void method_invoke(void)
{
    __asm {
        push ebp
        mov ebp, esp

        mov ecx, SELECTOR
        mov edx, method_name[ecx]
        mov eax, method_imp[ecx]
        mov SELECTOR, edx

        leave
        jmp eax
    }
}


OBJC_EXPORT __declspec(naked) void method_invoke_stret(void)
{
    __asm {
        push ebp
        mov ebp, esp

        mov ecx, SELECTOR_STRET
        mov edx, method_name[ecx]
        mov eax, method_imp[ecx]
        mov SELECTOR_STRET, edx

        leave
        jmp eax
    }
}


__declspec(naked) id _objc_ignored_method(id obj, SEL sel)
{
    return obj;
}
