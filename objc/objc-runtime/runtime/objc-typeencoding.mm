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
* objc-typeencoding.m
* Parsing of old-style type strings.
**********************************************************************/

#include "objc-private.h"

/***********************************************************************
* SubtypeUntil.
*
* Delegation.
**********************************************************************/
static int	SubtypeUntil	       (const char *	type,
                                char		end)
{
    int		level = 0;
    const char *	head = type;

    //
    while (*type)
    {
        if (!*type || (!level && (*type == end)))
            return (int)(type - head);

        switch (*type)
        {
            case ']': case '}': case ')': level--; break;
            case '[': case '{': case '(': level += 1; break;
        }

        type += 1;
    }

    _objc_fatal ("Object: SubtypeUntil: end of type encountered prematurely\n");
    return 0;
}


/***********************************************************************
* SkipFirstType.
**********************************************************************/
static const char *	SkipFirstType	   (const char *	type)
{
    while (1)
    {
        switch (*type++)
        {
            case 'O':	/* bycopy */
            case 'n':	/* in */
            case 'o':	/* out */
            case 'N':	/* inout */
            case 'r':	/* const */
            case 'V':	/* oneway */
            case '^':	/* pointers */
                break;

            case '@':   /* objects */
                if (type[0] == '?') type++;  /* Blocks */
                return type;

                /* arrays */
            case '[':
                while ((*type >= '0') && (*type <= '9'))
                    type += 1;
                return type + SubtypeUntil (type, ']') + 1;

                /* structures */
            case '{':
                return type + SubtypeUntil (type, '}') + 1;

                /* unions */
            case '(':
                return type + SubtypeUntil (type, ')') + 1;

                /* basic types */
            default:
                return type;
        }
    }
}


/***********************************************************************
* encoding_getNumberOfArguments.
**********************************************************************/
unsigned int 
encoding_getNumberOfArguments(const char *typedesc)
{
    unsigned nargs;

    // First, skip the return type
    typedesc = SkipFirstType (typedesc);

    // Next, skip stack size
    while ((*typedesc >= '0') && (*typedesc <= '9'))
        typedesc += 1;

    // Now, we have the arguments - count how many
    nargs = 0;
    while (*typedesc)
    {
        // Traverse argument type
        typedesc = SkipFirstType (typedesc);

        // Skip GNU runtime's register parameter hint
        if (*typedesc == '+') typedesc++;

        // Traverse (possibly negative) argument offset
        if (*typedesc == '-')
            typedesc += 1;
        while ((*typedesc >= '0') && (*typedesc <= '9'))
            typedesc += 1;

        // Made it past an argument
        nargs += 1;
    }

    return nargs;
}

/***********************************************************************
* encoding_getSizeOfArguments.
**********************************************************************/
unsigned 
encoding_getSizeOfArguments(const char *typedesc)
{
    unsigned		stack_size;

    // Get our starting points
    stack_size = 0;

    // Skip the return type
    typedesc = SkipFirstType (typedesc);

    // Convert ASCII number string to integer
    while ((*typedesc >= '0') && (*typedesc <= '9'))
        stack_size = (stack_size * 10) + (*typedesc++ - '0');

    return stack_size;
}


/***********************************************************************
* encoding_getArgumentInfo.
**********************************************************************/
unsigned int 
encoding_getArgumentInfo(const char *typedesc, unsigned int arg,
                         const char **type, int *offset)
{
    unsigned nargs = 0;
    int self_offset = 0;
    bool offset_is_negative = NO;

    // First, skip the return type
    typedesc = SkipFirstType (typedesc);

    // Next, skip stack size
    while ((*typedesc >= '0') && (*typedesc <= '9'))
        typedesc += 1;

    // Now, we have the arguments - position typedesc to the appropriate argument
    while (*typedesc && nargs != arg)
    {

        // Skip argument type
        typedesc = SkipFirstType (typedesc);

        if (nargs == 0)
        {
            // Skip GNU runtime's register parameter hint
            if (*typedesc == '+') typedesc++;

            // Skip negative sign in offset
            if (*typedesc == '-')
            {
                offset_is_negative = YES;
                typedesc += 1;
            }
            else
                offset_is_negative = NO;

            while ((*typedesc >= '0') && (*typedesc <= '9'))
                self_offset = self_offset * 10 + (*typedesc++ - '0');
            if (offset_is_negative)
                self_offset = -(self_offset);

        }

        else
        {
            // Skip GNU runtime's register parameter hint
            if (*typedesc == '+') typedesc++;

            // Skip (possibly negative) argument offset
            if (*typedesc == '-')
                typedesc += 1;
            while ((*typedesc >= '0') && (*typedesc <= '9'))
                typedesc += 1;
        }

        nargs += 1;
    }

    if (*typedesc)
    {
        int arg_offset = 0;

        *type	 = typedesc;
        typedesc = SkipFirstType (typedesc);

        if (arg == 0)
        {
            *offset = 0;
        }

        else
        {
            // Skip GNU register parameter hint
            if (*typedesc == '+') typedesc++;

            // Pick up (possibly negative) argument offset
            if (*typedesc == '-')
            {
                offset_is_negative = YES;
                typedesc += 1;
            }
            else
                offset_is_negative = NO;

            while ((*typedesc >= '0') && (*typedesc <= '9'))
                arg_offset = arg_offset * 10 + (*typedesc++ - '0');
            if (offset_is_negative)
                arg_offset = - arg_offset;

            *offset = arg_offset - self_offset;
        }

    }

    else
    {
        *type	= 0;
        *offset	= 0;
    }

    return nargs;
}


void 
encoding_getReturnType(const char *t, char *dst, size_t dst_len)
{
    size_t len;
    const char *end;

    if (!dst) return;
    if (!t) {
        strncpy(dst, "", dst_len);
        return;
    }

    end = SkipFirstType(t);
    len = end - t;
    strncpy(dst, t, MIN(len, dst_len));
    if (len < dst_len) memset(dst+len, 0, dst_len - len);
}

/***********************************************************************
* encoding_copyReturnType.  Returns the method's return type string 
* on the heap. 
**********************************************************************/
char *
encoding_copyReturnType(const char *t)
{
    size_t len;
    const char *end;
    char *result;

    if (!t) return NULL;

    end = SkipFirstType(t);
    len = end - t;
    result = (char *)malloc(len + 1);
    strncpy(result, t, len);
    result[len] = '\0';
    return result;
}


void 
encoding_getArgumentType(const char *t, unsigned int index, 
                         char *dst, size_t dst_len)
{
    size_t len;
    const char *end;
    int offset;

    if (!dst) return;
    if (!t) {
        strncpy(dst, "", dst_len);
        return;
    }

    encoding_getArgumentInfo(t, index, &t, &offset);

    if (!t) {
        strncpy(dst, "", dst_len);
        return;
    }

    end = SkipFirstType(t);
    len = end - t;
    strncpy(dst, t, MIN(len, dst_len));
    if (len < dst_len) memset(dst+len, 0, dst_len - len);
}


/***********************************************************************
* encoding_copyArgumentType.  Returns a single argument's type string 
* on the heap. Argument 0 is `self`; argument 1 is `_cmd`. 
**********************************************************************/
char *
encoding_copyArgumentType(const char *t, unsigned int index)
{
    size_t len;
    const char *end;
    char *result;
    int offset;

    if (!t) return NULL;

    encoding_getArgumentInfo(t, index, &t, &offset);

    if (!t) return NULL;

    end = SkipFirstType(t);
    len = end - t;
    result = (char *)malloc(len + 1);
    strncpy(result, t, len);
    result[len] = '\0';
    return result;
}
