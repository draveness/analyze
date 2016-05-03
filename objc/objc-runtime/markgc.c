/*
 * Copyright (c) 2007-2009 Apple Inc.  All Rights Reserved.
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

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/errno.h>
#include <mach-o/fat.h>
#include <mach-o/arch.h>
#include <mach-o/loader.h>

// from "objc-private.h"
// masks for objc_image_info.flags
#define OBJC_IMAGE_SUPPORTS_GC (1<<1)

// Some OS X SDKs don't define these.
#ifndef CPU_TYPE_ARM
#define CPU_TYPE_ARM            ((cpu_type_t) 12)
#endif
#ifndef CPU_ARCH_ABI64
#define CPU_ARCH_ABI64  0x01000000              /* 64 bit ABI */
#endif
#ifndef CPU_TYPE_ARM64
#define CPU_TYPE_ARM64          (CPU_TYPE_ARM | CPU_ARCH_ABI64)
#endif

// File abstraction taken from ld64/FileAbstraction.hpp
// and ld64/MachOFileAbstraction.hpp.

#ifdef __OPTIMIZE__
#define INLINE	__attribute__((always_inline))
#else
#define INLINE
#endif

//
// This abstraction layer is for use with file formats that have 64-bit/32-bit and Big-Endian/Little-Endian variants
//
// For example: to make a utility that handles 32-bit little enidan files use:  Pointer32<LittleEndian>
//
//
//		get16()			read a 16-bit number from an E endian struct
//		set16()			write a 16-bit number to an E endian struct
//		get32()			read a 32-bit number from an E endian struct
//		set32()			write a 32-bit number to an E endian struct
//		get64()			read a 64-bit number from an E endian struct
//		set64()			write a 64-bit number to an E endian struct
//
//		getBits()		read a bit field from an E endian struct (bitCount=number of bits in field, firstBit=bit index of field)
//		setBits()		write a bit field to an E endian struct (bitCount=number of bits in field, firstBit=bit index of field)
//
//		getBitsRaw()	read a bit field from a struct with native endianness
//		setBitsRaw()	write a bit field from a struct with native endianness
//

class BigEndian
{
public:
    static uint16_t	get16(const uint16_t& from)				INLINE { return OSReadBigInt16(&from, 0); }
    static void		set16(uint16_t& into, uint16_t value)	INLINE { OSWriteBigInt16(&into, 0, value); }
    
    static uint32_t	get32(const uint32_t& from)				INLINE { return OSReadBigInt32(&from, 0); }
    static void		set32(uint32_t& into, uint32_t value)	INLINE { OSWriteBigInt32(&into, 0, value); }
    
    static uint64_t get64(const uint64_t& from)				INLINE { return OSReadBigInt64(&from, 0); }
    static void		set64(uint64_t& into, uint64_t value)	INLINE { OSWriteBigInt64(&into, 0, value); }
    
    static uint32_t	getBits(const uint32_t& from,
                            uint8_t firstBit, uint8_t bitCount)	INLINE { return getBitsRaw(get32(from), firstBit, bitCount); }
    static void		setBits(uint32_t& into, uint32_t value,
                            uint8_t firstBit, uint8_t bitCount)	INLINE { uint32_t temp = get32(into); setBitsRaw(temp, value, firstBit, bitCount); set32(into, temp); }
    
    static uint32_t	getBitsRaw(const uint32_t& from,
                               uint8_t firstBit, uint8_t bitCount)	INLINE { return ((from >> (32-firstBit-bitCount)) & ((1<<bitCount)-1)); }
    static void		setBitsRaw(uint32_t& into, uint32_t value,
                               uint8_t firstBit, uint8_t bitCount)	INLINE { uint32_t temp = into;
        const uint32_t mask = ((1<<bitCount)-1);
        temp &= ~(mask << (32-firstBit-bitCount));
        temp |= ((value & mask) << (32-firstBit-bitCount));
        into = temp; }
    enum { little_endian = 0 };
};


class LittleEndian
{
public:
    static uint16_t	get16(const uint16_t& from)				INLINE { return OSReadLittleInt16(&from, 0); }
    static void		set16(uint16_t& into, uint16_t value)	INLINE { OSWriteLittleInt16(&into, 0, value); }
    
    static uint32_t	get32(const uint32_t& from)				INLINE { return OSReadLittleInt32(&from, 0); }
    static void		set32(uint32_t& into, uint32_t value)	INLINE { OSWriteLittleInt32(&into, 0, value); }
    
    static uint64_t get64(const uint64_t& from)				INLINE { return OSReadLittleInt64(&from, 0); }
    static void		set64(uint64_t& into, uint64_t value)	INLINE { OSWriteLittleInt64(&into, 0, value); }
    
    static uint32_t	getBits(const uint32_t& from,
                            uint8_t firstBit, uint8_t bitCount)	INLINE { return getBitsRaw(get32(from), firstBit, bitCount); }
    static void		setBits(uint32_t& into, uint32_t value,
                            uint8_t firstBit, uint8_t bitCount)	INLINE { uint32_t temp = get32(into); setBitsRaw(temp, value, firstBit, bitCount); set32(into, temp); }
    
    static uint32_t	getBitsRaw(const uint32_t& from,
                               uint8_t firstBit, uint8_t bitCount)	INLINE { return ((from >> firstBit) & ((1<<bitCount)-1)); }
    static void		setBitsRaw(uint32_t& into, uint32_t value,
                               uint8_t firstBit, uint8_t bitCount)	INLINE {  uint32_t temp = into;
        const uint32_t mask = ((1<<bitCount)-1);
        temp &= ~(mask << firstBit);
        temp |= ((value & mask) << firstBit);
        into = temp; }
    enum { little_endian = 1 };
};

#if __BIG_ENDIAN__
typedef BigEndian CurrentEndian;
typedef LittleEndian OtherEndian;
#elif __LITTLE_ENDIAN__
typedef LittleEndian CurrentEndian;
typedef BigEndian OtherEndian;
#else
#error unknown endianness
#endif


template <typename _E>
class Pointer32
{
public:
    typedef uint32_t	uint_t;
    typedef int32_t		sint_t;
    typedef _E			E;
    
    static uint64_t	getP(const uint_t& from)				INLINE { return _E::get32(from); }
    static void		setP(uint_t& into, uint64_t value)		INLINE { _E::set32(into, value); }
};


template <typename _E>
class Pointer64
{
public:
    typedef uint64_t	uint_t;
    typedef int64_t		sint_t;
    typedef _E			E;
    
    static uint64_t	getP(const uint_t& from)				INLINE { return _E::get64(from); }
    static void		setP(uint_t& into, uint64_t value)		INLINE { _E::set64(into, value); }
};


//
// mach-o file header
//
template <typename P> struct macho_header_content {};
template <> struct macho_header_content<Pointer32<BigEndian> >    { mach_header		fields; };
template <> struct macho_header_content<Pointer64<BigEndian> >	  { mach_header_64	fields; };
template <> struct macho_header_content<Pointer32<LittleEndian> > { mach_header		fields; };
template <> struct macho_header_content<Pointer64<LittleEndian> > { mach_header_64	fields; };

template <typename P>
class macho_header {
public:
    uint32_t		magic() const					INLINE { return E::get32(header.fields.magic); }
    void			set_magic(uint32_t value)		INLINE { E::set32(header.fields.magic, value); }
    
    uint32_t		cputype() const					INLINE { return E::get32(header.fields.cputype); }
    void			set_cputype(uint32_t value)		INLINE { E::set32((uint32_t&)header.fields.cputype, value); }
    
    uint32_t		cpusubtype() const				INLINE { return E::get32(header.fields.cpusubtype); }
    void			set_cpusubtype(uint32_t value)	INLINE { E::set32((uint32_t&)header.fields.cpusubtype, value); }
    
    uint32_t		filetype() const				INLINE { return E::get32(header.fields.filetype); }
    void			set_filetype(uint32_t value)	INLINE { E::set32(header.fields.filetype, value); }
    
    uint32_t		ncmds() const					INLINE { return E::get32(header.fields.ncmds); }
    void			set_ncmds(uint32_t value)		INLINE { E::set32(header.fields.ncmds, value); }
    
    uint32_t		sizeofcmds() const				INLINE { return E::get32(header.fields.sizeofcmds); }
    void			set_sizeofcmds(uint32_t value)	INLINE { E::set32(header.fields.sizeofcmds, value); }
    
    uint32_t		flags() const					INLINE { return E::get32(header.fields.flags); }
    void			set_flags(uint32_t value)		INLINE { E::set32(header.fields.flags, value); }
    
    uint32_t		reserved() const				INLINE { return E::get32(header.fields.reserved); }
    void			set_reserved(uint32_t value)	INLINE { E::set32(header.fields.reserved, value); }
    
    typedef typename P::E		E;
private:
    macho_header_content<P>	header;
};


//
// mach-o load command
//
template <typename P>
class macho_load_command {
public:
    uint32_t		cmd() const						INLINE { return E::get32(command.cmd); }
    void			set_cmd(uint32_t value)			INLINE { E::set32(command.cmd, value); }
    
    uint32_t		cmdsize() const					INLINE { return E::get32(command.cmdsize); }
    void			set_cmdsize(uint32_t value)		INLINE { E::set32(command.cmdsize, value); }
    
    typedef typename P::E		E;
private:
    load_command	command;
};




//
// mach-o segment load command
//
template <typename P> struct macho_segment_content {};
template <> struct macho_segment_content<Pointer32<BigEndian> >    { segment_command	fields; enum { CMD = LC_SEGMENT		}; };
template <> struct macho_segment_content<Pointer64<BigEndian> >	   { segment_command_64	fields; enum { CMD = LC_SEGMENT_64	}; };
template <> struct macho_segment_content<Pointer32<LittleEndian> > { segment_command	fields; enum { CMD = LC_SEGMENT		}; };
template <> struct macho_segment_content<Pointer64<LittleEndian> > { segment_command_64	fields; enum { CMD = LC_SEGMENT_64	}; };

template <typename P>
class macho_segment_command {
public:
    uint32_t		cmd() const						INLINE { return E::get32(segment.fields.cmd); }
    void			set_cmd(uint32_t value)			INLINE { E::set32(segment.fields.cmd, value); }
    
    uint32_t		cmdsize() const					INLINE { return E::get32(segment.fields.cmdsize); }
    void			set_cmdsize(uint32_t value)		INLINE { E::set32(segment.fields.cmdsize, value); }
    
    const char*		segname() const					INLINE { return segment.fields.segname; }
    void			set_segname(const char* value)	INLINE { strncpy(segment.fields.segname, value, 16); }
    
    uint64_t		vmaddr() const					INLINE { return P::getP(segment.fields.vmaddr); }
    void			set_vmaddr(uint64_t value)		INLINE { P::setP(segment.fields.vmaddr, value); }
    
    uint64_t		vmsize() const					INLINE { return P::getP(segment.fields.vmsize); }
    void			set_vmsize(uint64_t value)		INLINE { P::setP(segment.fields.vmsize, value); }
    
    uint64_t		fileoff() const					INLINE { return P::getP(segment.fields.fileoff); }
    void			set_fileoff(uint64_t value)		INLINE { P::setP(segment.fields.fileoff, value); }
    
    uint64_t		filesize() const				INLINE { return P::getP(segment.fields.filesize); }
    void			set_filesize(uint64_t value)	INLINE { P::setP(segment.fields.filesize, value); }
    
    uint32_t		maxprot() const					INLINE { return E::get32(segment.fields.maxprot); }
    void			set_maxprot(uint32_t value)		INLINE { E::set32((uint32_t&)segment.fields.maxprot, value); }
    
    uint32_t		initprot() const				INLINE { return E::get32(segment.fields.initprot); }
    void			set_initprot(uint32_t value)	INLINE { E::set32((uint32_t&)segment.fields.initprot, value); }
    
    uint32_t		nsects() const					INLINE { return E::get32(segment.fields.nsects); }
    void			set_nsects(uint32_t value)		INLINE { E::set32(segment.fields.nsects, value); }
    
    uint32_t		flags() const					INLINE { return E::get32(segment.fields.flags); }
    void			set_flags(uint32_t value)		INLINE { E::set32(segment.fields.flags, value); }
    
    enum {
        CMD = macho_segment_content<P>::CMD
    };
    
    typedef typename P::E		E;
private:
    macho_segment_content<P>	segment;
};


//
// mach-o section
//
template <typename P> struct macho_section_content {};
template <> struct macho_section_content<Pointer32<BigEndian> >    { section	fields; };
template <> struct macho_section_content<Pointer64<BigEndian> >	   { section_64	fields; };
template <> struct macho_section_content<Pointer32<LittleEndian> > { section	fields; };
template <> struct macho_section_content<Pointer64<LittleEndian> > { section_64	fields; };

template <typename P>
class macho_section {
public:
    const char*		sectname() const				INLINE { return section.fields.sectname; }
    void			set_sectname(const char* value)	INLINE { strncpy(section.fields.sectname, value, 16); }
    
    const char*		segname() const					INLINE { return section.fields.segname; }
    void			set_segname(const char* value)	INLINE { strncpy(section.fields.segname, value, 16); }
    
    uint64_t		addr() const					INLINE { return P::getP(section.fields.addr); }
    void			set_addr(uint64_t value)		INLINE { P::setP(section.fields.addr, value); }
    
    uint64_t		size() const					INLINE { return P::getP(section.fields.size); }
    void			set_size(uint64_t value)		INLINE { P::setP(section.fields.size, value); }
    
    uint32_t		offset() const					INLINE { return E::get32(section.fields.offset); }
    void			set_offset(uint32_t value)		INLINE { E::set32(section.fields.offset, value); }
    
    uint32_t		align() const					INLINE { return E::get32(section.fields.align); }
    void			set_align(uint32_t value)		INLINE { E::set32(section.fields.align, value); }
    
    uint32_t		reloff() const					INLINE { return E::get32(section.fields.reloff); }
    void			set_reloff(uint32_t value)		INLINE { E::set32(section.fields.reloff, value); }
    
    uint32_t		nreloc() const					INLINE { return E::get32(section.fields.nreloc); }
    void			set_nreloc(uint32_t value)		INLINE { E::set32(section.fields.nreloc, value); }
    
    uint32_t		flags() const					INLINE { return E::get32(section.fields.flags); }
    void			set_flags(uint32_t value)		INLINE { E::set32(section.fields.flags, value); }
    
    uint32_t		reserved1() const				INLINE { return E::get32(section.fields.reserved1); }
    void			set_reserved1(uint32_t value)	INLINE { E::set32(section.fields.reserved1, value); }
    
    uint32_t		reserved2() const				INLINE { return E::get32(section.fields.reserved2); }
    void			set_reserved2(uint32_t value)	INLINE { E::set32(section.fields.reserved2, value); }
    
    typedef typename P::E		E;
private:
    macho_section_content<P>	section;
};




static bool debug = true;

bool processFile(const char *filename);

int main(int argc, const char *argv[]) {
    for (int i = 1; i < argc; ++i) {
        if (!processFile(argv[i])) return 1;
    }
    return 0;
}

struct imageinfo {
    uint32_t version;
    uint32_t flags;
};


// Segment and section names are 16 bytes and may be un-terminated.
bool segnameEquals(const char *lhs, const char *rhs)
{
    return 0 == strncmp(lhs, rhs, 16);
}

bool segnameStartsWith(const char *segname, const char *prefix)
{
    return 0 == strncmp(segname, prefix, strlen(prefix));
}

bool sectnameEquals(const char *lhs, const char *rhs)
{
    return segnameEquals(lhs, rhs);
}


template <typename P>
void dosect(uint8_t *start, macho_section<P> *sect, bool isOldABI, bool isOSX)
{
    if (debug) printf("section %.16s from segment %.16s\n",
                      sect->sectname(), sect->segname());
    
    if (isOSX) {
        // Add "supports GC" flag to objc image info
        if ((segnameStartsWith(sect->segname(),  "__DATA")  &&
             sectnameEquals(sect->sectname(), "__objc_imageinfo"))  ||
            (segnameEquals(sect->segname(),  "__OBJC")  &&
             sectnameEquals(sect->sectname(), "__image_info")))
        {
            imageinfo *ii = (imageinfo*)(start + sect->offset());
            P::E::set32(ii->flags, P::E::get32(ii->flags) | OBJC_IMAGE_SUPPORTS_GC);
            if (debug) printf("added GC support flag\n");
        }
    }
    
    if (isOldABI) {
        // Keep init funcs because libSystem doesn't call _objc_init().
    } else {
        // Strip S_MOD_INIT/TERM_FUNC_POINTERS. We don't want dyld to call
        // our init funcs because it is too late, and we don't want anyone to
        // call our term funcs ever.
        if (segnameStartsWith(sect->segname(), "__DATA")  &&
            sectnameEquals(sect->sectname(), "__mod_init_func"))
        {
            // section type 0 is S_REGULAR
            sect->set_flags(sect->flags() & ~SECTION_TYPE);
            sect->set_sectname("__objc_init_func");
            if (debug) printf("disabled __mod_init_func section\n");
        }
        if (segnameStartsWith(sect->segname(), "__DATA")  &&
            sectnameEquals(sect->sectname(), "__mod_term_func"))
        {
            // section type 0 is S_REGULAR
            sect->set_flags(sect->flags() & ~SECTION_TYPE);
            sect->set_sectname("__objc_term_func");
            if (debug) printf("disabled __mod_term_func section\n");
        }
    }
}

template <typename P>
void doseg(uint8_t *start, macho_segment_command<P> *seg,
           bool isOldABI, bool isOSX)
{
    if (debug) printf("segment name: %.16s, nsects %u\n",
                      seg->segname(), seg->nsects());
    macho_section<P> *sect = (macho_section<P> *)(seg + 1);
    for (uint32_t i = 0; i < seg->nsects(); ++i) {
        dosect(start, &sect[i], isOldABI, isOSX);
    }
}


template<typename P>
bool parse_macho(uint8_t *buffer)
{
    macho_header<P>* mh = (macho_header<P>*)buffer;
    uint8_t *cmds;
    
    bool isOldABI = false;
    bool isOSX = false;
    cmds = (uint8_t *)(mh + 1);
    for (uint32_t c = 0; c < mh->ncmds(); c++) {
        macho_load_command<P>* cmd = (macho_load_command<P>*)cmds;
        cmds += cmd->cmdsize();
        if (cmd->cmd() == LC_SEGMENT  ||  cmd->cmd() == LC_SEGMENT_64) {
            macho_segment_command<P>* seg = (macho_segment_command<P>*)cmd;
            if (segnameEquals(seg->segname(), "__OBJC")) isOldABI = true;
        }
        else if (cmd->cmd() == LC_VERSION_MIN_MACOSX) {
            isOSX = true;
        }
    }
    
    if (debug) printf("ABI=%s, OS=%s\n",
                      isOldABI ? "old" : "new", isOSX ? "osx" : "ios");
    
    cmds = (uint8_t *)(mh + 1);
    for (uint32_t c = 0; c < mh->ncmds(); c++) {
        macho_load_command<P>* cmd = (macho_load_command<P>*)cmds;
        cmds += cmd->cmdsize();
        if (cmd->cmd() == LC_SEGMENT  ||  cmd->cmd() == LC_SEGMENT_64) {
            doseg(buffer, (macho_segment_command<P>*)cmd, isOldABI, isOSX);
        }
    }
    
    return true;
}


bool parse_macho(uint8_t *buffer)
{
    uint32_t magic = *(uint32_t *)buffer;
    
    switch (magic) {
        case MH_MAGIC_64:
            return parse_macho<Pointer64<CurrentEndian>>(buffer);
        case MH_MAGIC:
            return parse_macho<Pointer32<CurrentEndian>>(buffer);
        case MH_CIGAM_64:
            return parse_macho<Pointer64<OtherEndian>>(buffer);
        case MH_CIGAM:
            return parse_macho<Pointer32<OtherEndian>>(buffer);
        default:
            printf("file is not mach-o (magic %x)\n", magic);
            return false;
    }
}


bool parse_fat(uint8_t *buffer, size_t size)
{
    uint32_t magic;
    
    if (size < sizeof(magic)) {
        printf("file is too small\n");
        return false;
    }
    
    magic = *(uint32_t *)buffer;
    if (magic != FAT_MAGIC && magic != FAT_CIGAM) {
        /* Not a fat file */
        return parse_macho(buffer);
    } else {
        struct fat_header *fh;
        uint32_t fat_magic, fat_nfat_arch;
        struct fat_arch *archs;
        
        if (size < sizeof(struct fat_header)) {
            printf("file is too small\n");
            return false;
        }
        
        fh = (struct fat_header *)buffer;
        fat_magic = OSSwapBigToHostInt32(fh->magic);
        fat_nfat_arch = OSSwapBigToHostInt32(fh->nfat_arch);
        
        if (size < (sizeof(struct fat_header) + fat_nfat_arch * sizeof(struct fat_arch))) {
            printf("file is too small\n");
            return false;
        }
        
        archs = (struct fat_arch *)(buffer + sizeof(struct fat_header));
        
        /* Special case hidden CPU_TYPE_ARM64 */
        if (size >= (sizeof(struct fat_header) + (fat_nfat_arch + 1) * sizeof(struct fat_arch))) {
            if (fat_nfat_arch > 0
                && OSSwapBigToHostInt32(archs[fat_nfat_arch].cputype) == CPU_TYPE_ARM64) {
                fat_nfat_arch++;
            }
        }
        /* End special case hidden CPU_TYPE_ARM64 */
        
        if (debug) printf("%d fat architectures\n",
                          fat_nfat_arch);
        
        for (uint32_t i = 0; i < fat_nfat_arch; i++) {
            uint32_t arch_cputype = OSSwapBigToHostInt32(archs[i].cputype);
            uint32_t arch_cpusubtype = OSSwapBigToHostInt32(archs[i].cpusubtype);
            uint32_t arch_offset = OSSwapBigToHostInt32(archs[i].offset);
            uint32_t arch_size = OSSwapBigToHostInt32(archs[i].size);
            
            if (debug) printf("cputype %d cpusubtype %d\n",
                              arch_cputype, arch_cpusubtype);
            
            /* Check that slice data is after all fat headers and archs */
            if (arch_offset < (sizeof(struct fat_header) + fat_nfat_arch * sizeof(struct fat_arch))) {
                printf("file is badly formed\n");
                return false;
            }
            
            /* Check that the slice ends before the file does */
            if (arch_offset > size) {
                printf("file is badly formed\n");
                return false;
            }
            
            if (arch_size > size) {
                printf("file is badly formed\n");
                return false;
            }
            
            if (arch_offset > (size - arch_size)) {
                printf("file is badly formed\n");
                return false;
            }
            
            bool ok = parse_macho(buffer + arch_offset);
            if (!ok) return false;
        }
        return true;
    }
}

bool processFile(const char *filename)
{
    if (debug) printf("file %s\n", filename);
    int fd = open(filename, O_RDWR);
    if (fd < 0) {
        printf("open %s: %s\n", filename, strerror(errno));
        return false;
    }
    
    struct stat st;
    if (fstat(fd, &st) < 0) {
        printf("fstat %s: %s\n", filename, strerror(errno));
        return false;
    }
    
    void *buffer = mmap(NULL, (size_t)st.st_size, PROT_READ|PROT_WRITE, 
                        MAP_FILE|MAP_SHARED, fd, 0);
    if (buffer == MAP_FAILED) {
        printf("mmap %s: %s\n", filename, strerror(errno));
        return false;
    }
    
    bool result = parse_fat((uint8_t *)buffer, (size_t)st.st_size);
    munmap(buffer, (size_t)st.st_size);
    close(fd);
    return result;
}
