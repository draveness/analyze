//
//  objc-auto-dump.h
//  objc
//  The raw dump file format
//  See objc-gdb.h for the primitive.
//
//  Created by Blaine Garst on 12/8/08.
//  Copyright 2008 Apple, Inc. All rights reserved.
//
#ifndef _OBJC_AUTO_DUMP_H_
#define _OBJC_AUTO_DUMP_H_

/*
 *  Raw file format definitions
 */
 
// must be unique in first letter...
// RAW FORMAT
#define HEADER      "dumpster"
#define THREAD      't'
#define LOCAL       'l'
#define NODE        'n'
#define REGISTER    'r'
#define ROOT        'g'
#define WEAK        'w'
#define CLASS       'c'
#define END         'e'

#define SixtyFour 1
#define Little    2

/*

Raw format, not that anyone should really care.  Most programs should use the cooked file reader.

<rawfile := <header> <arch> <middle>* <end>
<header> :=  'd' 'u' 'm' 'p' 's' 't' 'e' 'r'                    ; the HEADER string
<arch>   :=  SixtyFour? + Little?                               ; architecture
<middle> := <thread> | <root> | <node> | <weak> | <class>
<thread> := <register> <stack> <local>*                         ; the triple
<register>      := 'r' longLength [bytes]                       ; the register bank
<stack>         := 't' longLength [bytes]                       ; the stack
<local>         := 'l' [long]                                   ; a thread local node
<root>          := 'g' longAddress longValue
<node>          := 'n' longAddress longSize intLayout longRefcount longIsa?
<weak>          := 'w' longAddress longValue
<class>         := 'c' longAddress <name> <strongLayout> <weakLayout>
<name>          := intLength [bytes]                            ; no null byte
<strongLayout>  := intLength [bytes]                            ; including 0 byte at end
<weakLayout>    := intLength [bytes]                            ; including 0 byte at end
<end>           := 'e'

 */

#endif
