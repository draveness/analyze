#if __arm64__

#include <mach/vm_param.h>

.text

	.private_extern __a1a2_tramphead
	.private_extern __a1a2_firsttramp
	.private_extern __a1a2_trampend
	
.align PAGE_MAX_SHIFT
__a1a2_tramphead:
L_a1a2_tramphead:
	/*
	 x0  == self
	 x17 == address of called trampoline's data (1 page before its code)
	 lr  == original return address
	 */

	mov  x1, x0                  // _cmd = self
	ldr  x0, [x17]               // self = block object
	ldr  x16, [x0, #16]          // tail call block->invoke
	br   x16

	// pad up to TrampolineBlockPagePair header size
	nop
	nop
	
.macro TrampolineEntry
	// load address of trampoline data (one page before this instruction)
	adr  x17, -PAGE_MAX_SIZE
	b    L_a1a2_tramphead
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
	
.align 3
.private_extern __a1a2_firsttramp
__a1a2_firsttramp:	
	// 2048-3 trampolines to fill 16K page
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
	// TrampolineEntry
	// TrampolineEntry
	// TrampolineEntry
	
.private_extern __a1a2_trampend
__a1a2_trampend:

#endif
