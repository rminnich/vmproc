#include "mem.h"

TEXT vmcall(SB), $0
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET
// from l.s
MODE $32
#define DELAY		BYTE $0xEB; BYTE $0x00	/* JMP .+2 */

#define pFARJMP32(s, o)	BYTE $0xea;		/* far jump to ptr32:16 */\
			LONG $o; WORD $s

#define WAVE(c) MOVL $c, BP; BYTE $0xf; BYTE $0x1; BYTE $0xc1

// This code is a bashing together of l.s, minus things we know don't matter.
// memory is zero, for example. Note: be careful about BP
TEXT to64(SB), $0
mov bp to si for pml4
do the init in c, no need to set it up here.
	WAVE('P')


/*
 * Enter here in 32-bit protected mode. Welcome to 1982.
 * Make sure the GDT is set as it should be:
 *	disable interrupts;
 *	load the GDT with the table in _gdt32p;
 *	load all the data segments
 *	load the code segment via a far jump.
 */
TEXT _protected<>(SB), 1, $-4
	// CLI
	WAVE('l')
	// We have a GDT. We are a VM.
	MOVL	$_gdtptr32p<>(SB), AX
	MOVL	(AX), GDTR
	WAVE('a')
	MOVL	$SELECTOR(2, SELGDT, 0), AX
	MOVW	AX, DS
	MOVW	AX, ES
	MOVW	AX, FS
	MOVW	AX, GS
	MOVW	AX, SS
	WAVE('n')
	pFARJMP32(SELECTOR(3, SELGDT, 0), _warp64<>(SB))

	BYTE	$0x90	/* align */
TEXT _gdt<>(SB), 1, $-4
	/* null descriptor */
	LONG	$0
	LONG	$0

	/* (KESEG) 64 bit long mode exec segment */
	LONG	$(0xFFFF)
	LONG	$(SEGL|SEGG|SEGP|(0xF<<16)|SEGPL(0)|SEGEXEC|SEGR)

	/* 32 bit data segment descriptor for 4 gigabytes (PL 0) */
	LONG	$(0xFFFF)
	LONG	$(SEGG|SEGB|(0xF<<16)|SEGP|SEGPL(0)|SEGDATA|SEGW)

	/* 32 bit exec segment descriptor for 4 gigabytes (PL 0) */
	LONG	$(0xFFFF)
	LONG	$(SEGG|SEGD|(0xF<<16)|SEGP|SEGPL(0)|SEGEXEC|SEGR)


TEXT _gdtptr32p<>(SB), 1, $-4
	WORD	$(4*8-1)
	LONG	$_gdt<>(SB)

TEXT _gdtptr64p<>(SB), 1, $-4
	WORD	$(4*8-1)
	QUAD	$_gdt<>(SB)

TEXT _gdtptr64v<>(SB), 1, $-4
	WORD	$(4*8-1)
	QUAD	$_gdt<>(SB)
/*
 * Macros for accessing page table entries; change the
 * C-style array-index macros into a page table byte offset
 */
#define PML4O(v)	((PTLX((v), 3))<<3)
#define PDPO(v)		((PTLX((v), 2))<<3)
#define PDO(v)		((PTLX((v), 1))<<3)
#define PTO(v)		((PTLX((v), 0))<<3)

TEXT _warp64<>(SB), 1, $-4
	WAVE('9')
	//HLT
	/* all clearing of memory is removed; this is a vm and memory is already zerod. */

	MOVL	$0x1000000, SI // FIXME

	MOVL	SI, AX				/* PML4 */
	MOVL	AX, DX
	ADDL	$(PTEACCESSED|PTEDIRTY|PTSZ|PTEWRITE|PTEVALID), DX	/* PDP at PML4 + PTSZ */
	MOVL	DX, PML4O(0)(AX)		/* PML4E for double-map */

	ADDL	$PTSZ, AX			/* PDP at PML4 + PTSZ */
	ADDL	$PTSZ, DX			/* PD0 at PML4 + 2*PTSZ */
	MOVL	DX, PDPO(0)(AX)			/* PDPE for double-map */

	ADDL	$PTSZ, AX			/* PD0 at PML4 + 2*PTSZ */
	MOVL	$(PTEACCESSED|PTEDIRTY|PTESIZE|PTEGLOBAL|PTEWRITE|PTEVALID), DX
	MOVL	DX, PDO(0)(AX)			/* PDE for double-map */

/*
 * Enable and activate Long Mode. From the manual:
 * 	make sure Page Size Extentions are off, and Page Global
 *	Extensions and Physical Address Extensions are on in CR4;
 *	set Long Mode Enable in the Extended Feature Enable MSR;
 *	set Paging Enable in CR0;
 *	make an inter-segment jump to the Long Mode code.
 * It's all in 32-bit mode until the jump is made.
 */
TEXT _lme<>(SB), 1, $-4
	MOVL	SI, CR3				/* load the mmu */
	DELAY
	WAVE('f')
	//HLT

	MOVL	CR4, AX
	ANDL	$~0x00000010, AX			/* Page Size */
	ORL	$0x000000A0, AX			/* Page Global, Phys. Address */
	MOVL	AX, CR4
	WAVE('r')

	MOVL	$0xc0000080, CX			/* Extended Feature Enable */
	RDMSR
	ORL	$0x00000100, AX			/* Long Mode Enable */
	WRMSR
	WAVE('o')

	MOVL	CR0, DX
	ANDL	$~0x6000000a, DX
	ORL	$0x80010000, DX			/* Paging Enable, Write Protect */
	MOVL	DX, CR0
	WAVE('m')

	pFARJMP32(SELECTOR(KESEG, SELGDT, 0), _identity<>(SB))

/*
 * Long mode. Welcome to 2003.
 * Jump out of the identity map space;
 * load a proper long mode GDT.
 */
MODE $64

TEXT _identity<>(SB), 1, $-4
	WAVE('O')
	MOVQ	$_start64v<>(SB), AX
	JMP*	AX

TEXT _start64v<>(SB), 1, $-4
	MOVQ	$_gdtptr64v<>(SB), AX
	MOVL	(AX), GDTR
	WAVE('u')

	XORQ	AX, AX
	MOVW	AX, DS				/* not used in long mode */
	MOVW	AX, ES				/* not used in long mode */
	MOVW	AX, FS
	MOVW	AX, GS
	MOVW	AX, SS				/* not used in long mode */
	WAVE('t')
	MOVW	AX, LDTR

_clearbss:
	WAVE('e')
	PUSHQ	AX				/* clear flags */
	POPFQ
	WAVE('r')
	HLT
	// vmcall
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET

	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	HLT
	RET
