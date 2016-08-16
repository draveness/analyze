/*
 * Copyright (c) 2003, 2013 Apple Computer, Inc. All rights reserved.
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
 * Copyright 1996 1995 by Open Software Foundation, Inc. 1997 1996 1995 1994 1993 1992 1991  
 *              All Rights Reserved 
 *  
 * Permission to use, copy, modify, and distribute this software and 
 * its documentation for any purpose and without fee is hereby granted, 
 * provided that the above copyright notice appears in all copies and 
 * that both the copyright notice and this permission notice appear in 
 * supporting documentation. 
 *  
 * OSF DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE 
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
 * FOR A PARTICULAR PURPOSE. 
 *  
 * IN NO EVENT SHALL OSF BE LIABLE FOR ANY SPECIAL, INDIRECT, OR 
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM 
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN ACTION OF CONTRACT, 
 * NEGLIGENCE, OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION 
 * WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. 
 * 
 */
/*
 * MkLinux
 */

/*
 * POSIX Threads - IEEE 1003.1c
 */

#ifndef _POSIX_PTHREAD_SPINLOCK_H
#define _POSIX_PTHREAD_SPINLOCK_H

#include <sys/cdefs.h>
#include <mach/mach.h>
#include <libkern/OSAtomic.h>

//typedef volatile OSSpinLock pthread_lock_t;

#define LOCK_INIT(l) ((l) = OS_SPINLOCK_INIT)
#define LOCK_INITIALIZER OS_SPINLOCK_INIT

#define _DO_SPINLOCK_LOCK(v) OSSpinLockLock(v)
#define _DO_SPINLOCK_UNLOCK(v) OSSpinLockUnlock(v)

#define TRY_LOCK(v) OSSpinLockTry((volatile OSSpinLock *)&(v))
#define LOCK(v) OSSpinLockLock((volatile OSSpinLock *)&(v))
#define UNLOCK(v) OSSpinLockUnlock((volatile OSSpinLock *)&(v))

extern void _spin_lock(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockLock instead");
extern int _spin_lock_try(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockTry instead");
extern void _spin_unlock(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockUnlock instead");

extern void spin_lock(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockLock instead");
extern int spin_lock_try(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockTry instead");
extern void spin_unlock(pthread_lock_t *lockp) __deprecated_msg("Use OSSpinLockUnlock instead");

#endif /* _POSIX_PTHREAD_SPINLOCK_H */
