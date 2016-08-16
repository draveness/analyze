/* -*- mode: C++; c-basic-offset: 4; tab-width: 4 -*-
 *
 * Copyright (c) 2003-2008 Apple Computer, Inc. All rights reserved.
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
#ifndef _MACH_O_DYLD_PRIV_H_
#define _MACH_O_DYLD_PRIV_H_


#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>

#if __cplusplus
extern "C" {
#endif /* __cplusplus */


//
// Possible state changes for which you can register to be notified
//
enum dyld_image_states
{
	dyld_image_state_mapped					= 10,		// No batch notification for this
	dyld_image_state_dependents_mapped		= 20,		// Only batch notification for this
	dyld_image_state_rebased				= 30, 
	dyld_image_state_bound					= 40,
	dyld_image_state_dependents_initialized	= 45,		// Only single notification for this
	dyld_image_state_initialized			= 50,
	dyld_image_state_terminated				= 60		// Only single notification for this
};

// 
// Callback that provides a bottom-up array of images
// For dyld_image_state_[dependents_]mapped state only, returning non-NULL will cause dyld to abort loading all those images
// and append the returned string to its load failure error message. dyld does not free the string, so
// it should be a literal string or a static buffer
//
typedef const char* (*dyld_image_state_change_handler)(enum dyld_image_states state, uint32_t infoCount, const struct dyld_image_info info[]);

//
// Register a handler to be called when any image changes to the requested state.
// If 'batch' is true, the callback is called with an array of all images that are in the requested state sorted by dependency.
// If 'batch' is false, the callback is called with one image at a time as each image transitions to the the requested state.
// During the call to this function, the handler may be called back with existing images and the handler should
// not return a string, since there is no load to abort.  In batch mode, existing images at or past the request
// state supplied in the callback.  In non-batch mode, the callback is called for each image exactly in the
// requested state.    
//
extern void
dyld_register_image_state_change_handler(enum dyld_image_states state, bool batch, dyld_image_state_change_handler handler);


//
// get slide for a given loaded mach_header  
// Mac OS X 10.6 and later
//
extern intptr_t _dyld_get_image_slide(const struct mach_header* mh);


//
// get pointer to this process's dyld_all_image_infos
// Exists in Mac OS X 10.4 and later through _dyld_func_lookup()
// Exists in Mac OS X 10.6 and later through libSystem.dylib
//
const struct dyld_all_image_infos* _dyld_get_all_image_infos();



struct dyld_unwind_sections
{
	const struct mach_header*		mh;
	const void*						dwarf_section;
	uintptr_t						dwarf_section_length;
	const void*						compact_unwind_section;
	uintptr_t						compact_unwind_section_length;
};


//
// Returns true iff some loaded mach-o image contains "addr".
//	info->mh							mach header of image containing addr
//  info->dwarf_section					pointer to start of __TEXT/__eh_frame section
//  info->dwarf_section_length			length of __TEXT/__eh_frame section
//  info->compact_unwind_section		pointer to start of __TEXT/__unwind_info section
//  info->compact_unwind_section_length	length of __TEXT/__unwind_info section
//
// Exists in Mac OS X 10.6 and later 
extern bool _dyld_find_unwind_sections(void* addr, struct dyld_unwind_sections* info);


//
// This is an optimized form of dladdr() that only returns the dli_fname field.
//
// Exists in Mac OS X 10.6 and later 
extern const char* dyld_image_path_containing_address(const void* addr);







#if __cplusplus
}
#endif /* __cplusplus */

#endif /* _MACH_O_DYLD_PRIV_H_ */
