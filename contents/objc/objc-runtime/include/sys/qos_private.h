/*
 * Copyright (c) 2014 Apple Inc. All rights reserved.
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

#ifndef _QOS_SYS_PRIVATE_H
#define _QOS_SYS_PRIVATE_H

/*! 
 * @constant QOS_CLASS_MAINTENANCE
 * @abstract A QOS class which indicates work performed by this thread was not
 * initiated by the user and that the user may be unaware of the results.
 * @discussion Such work is requested to run at a priority far below other work
 * including significant I/O throttling. The use of this QOS class indicates
 * the work should be run in the most energy and thermally-efficient manner
 * possible, and may be deferred for a long time in order to preserve
 * system responsiveness for the user.
 * This is SPI for use by Spotlight and Time Machine only.
 */
#define QOS_CLASS_MAINTENANCE	0x05

#endif //_QOS_SYS_PRIVATE_H
