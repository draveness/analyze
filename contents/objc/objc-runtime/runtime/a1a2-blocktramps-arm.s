#if __arm__
	
#include <arm/arch.h>
#include <mach/vm_param.h>

.syntax unified

.text

	.private_extern __a1a2_tramphead
	.private_extern __a1a2_firsttramp
	.private_extern __a1a2_trampend

// Trampoline machinery assumes the trampolines are Thumb function pointers
#if !__thumb2__
#   error sorry
#endif

.thumb
.thumb_func __a1a2_tramphead
.thumb_func __a1a2_firsttramp
.thumb_func __a1a2_trampend

.align PAGE_MAX_SHIFT
__a1a2_tramphead:
	/*
	 r0 == self
	 r12 == pc of trampoline's first instruction + PC bias
	 lr == original return address
	 */

	mov  r1, r0                   // _cmd = self

	// Trampoline's data is one page before the trampoline text.
	// Also correct PC bias of 4 bytes.
	sub  r12, #PAGE_MAX_SIZE
	ldr  r0, [r12, #-4]          // self = block object
	ldr  pc, [r0, #12]           // tail call block->invoke
	// not reached

	// Align trampolines to 8 bytes
.align 3
	
.macro TrampolineEntry
	mov r12, pc
	b __a1a2_tramphead
.align 3
.endmacro

.macro TrampolineEntryX16
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
.endmacro

.macro TrampolineEntryX256
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
.endmacro

.private_extern __a1a2_firsttramp
__a1a2_firsttramp:
	// 2048-2 trampolines to fill 16K page
	TrampolineEntryX256
	TrampolineEntryX256
	TrampolineEntryX256
	TrampolineEntryX256

	TrampolineEntryX256
	TrampolineEntryX256
	TrampolineEntryX256

	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16

	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16

	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16

	TrampolineEntryX16
	TrampolineEntryX16
	TrampolineEntryX16

	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry

	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry

	TrampolineEntry
	TrampolineEntry
	TrampolineEntry
	TrampolineEntry

	TrampolineEntry
	TrampolineEntry
	// TrampolineEntry
	// TrampolineEntry

.private_extern __a1a2_trampend
__a1a2_trampend:

#endif
