#if __arm__
	
#include <arm/arch.h>
#include <mach/vm_param.h>

.syntax unified

.text

	.private_extern __a2a3_tramphead
	.private_extern __a2a3_firsttramp
	.private_extern __a2a3_trampend

// Trampoline machinery assumes the trampolines are Thumb function pointers
#if !__thumb2__
#   error sorry
#endif

.thumb
.thumb_func __a2a3_tramphead
.thumb_func __a2a3_firsttramp
.thumb_func __a2a3_trampend

.align PAGE_MAX_SHIFT
__a2a3_tramphead:
	/*
	 r1 == self
	 r12 == pc of trampoline's first instruction + PC bias
	 lr == original return address
	 */

	mov  r2, r1                   // _cmd = self

	// Trampoline's data is one page before the trampoline text.
	// Also correct PC bias of 4 bytes.
	sub  r12, #PAGE_MAX_SIZE
	ldr  r1, [r12, #-4]          // self = block object
	ldr  pc, [r1, #12]           // tail call block->invoke
	// not reached

	// Align trampolines to 8 bytes
.align 3
	
.macro TrampolineEntry
	mov r12, pc
	b __a2a3_tramphead
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

.private_extern __a2a3_firsttramp
__a2a3_firsttramp:
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

.private_extern __a2a3_trampend
__a2a3_trampend:

#endif
