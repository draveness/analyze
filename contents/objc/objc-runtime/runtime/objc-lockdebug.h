/*
 * Copyright (c) 2015 Apple Inc.  All Rights Reserved.
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

extern void lockdebug_mutex_lock(mutex_tt<true> *lock);
extern void lockdebug_mutex_try_lock(mutex_tt<true> *lock);
extern void lockdebug_mutex_unlock(mutex_tt<true> *lock);
extern void lockdebug_mutex_assert_locked(mutex_tt<true> *lock);
extern void lockdebug_mutex_assert_unlocked(mutex_tt<true> *lock);

static inline void lockdebug_mutex_lock(mutex_tt<false> *lock) { }
static inline void lockdebug_mutex_try_lock(mutex_tt<false> *lock) { }
static inline void lockdebug_mutex_unlock(mutex_tt<false> *lock) { }
static inline void lockdebug_mutex_assert_locked(mutex_tt<false> *lock) { }
static inline void lockdebug_mutex_assert_unlocked(mutex_tt<false> *lock) { }


extern void lockdebug_monitor_enter(monitor_tt<true> *lock);
extern void lockdebug_monitor_leave(monitor_tt<true> *lock);
extern void lockdebug_monitor_wait(monitor_tt<true> *lock);
extern void lockdebug_monitor_assert_locked(monitor_tt<true> *lock);
extern void lockdebug_monitor_assert_unlocked(monitor_tt<true> *lock);

static inline void lockdebug_monitor_enter(monitor_tt<false> *lock) { }
static inline void lockdebug_monitor_leave(monitor_tt<false> *lock) { }
static inline void lockdebug_monitor_wait(monitor_tt<false> *lock) { }
static inline void lockdebug_monitor_assert_locked(monitor_tt<false> *lock) { }
static inline void lockdebug_monitor_assert_unlocked(monitor_tt<false> *lock) {}


extern void 
lockdebug_recursive_mutex_lock(recursive_mutex_tt<true> *lock);
extern void 
lockdebug_recursive_mutex_unlock(recursive_mutex_tt<true> *lock);
extern void 
lockdebug_recursive_mutex_assert_locked(recursive_mutex_tt<true> *lock);
extern void 
lockdebug_recursive_mutex_assert_unlocked(recursive_mutex_tt<true> *lock);

static inline void 
lockdebug_recursive_mutex_lock(recursive_mutex_tt<false> *lock) { }
static inline void 
lockdebug_recursive_mutex_unlock(recursive_mutex_tt<false> *lock) { }
static inline void 
lockdebug_recursive_mutex_assert_locked(recursive_mutex_tt<false> *lock) { }
static inline void 
lockdebug_recursive_mutex_assert_unlocked(recursive_mutex_tt<false> *lock) { }


extern void lockdebug_rwlock_read(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_try_read_success(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_unlock_read(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_write(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_try_write_success(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_unlock_write(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_assert_reading(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_assert_writing(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_assert_locked(rwlock_tt<true> *lock);
extern void lockdebug_rwlock_assert_unlocked(rwlock_tt<true> *lock);

static inline void lockdebug_rwlock_read(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_try_read_success(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_unlock_read(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_write(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_try_write_success(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_unlock_write(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_assert_reading(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_assert_writing(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_assert_locked(rwlock_tt<false> *) { }
static inline void lockdebug_rwlock_assert_unlocked(rwlock_tt<false> *) { }
