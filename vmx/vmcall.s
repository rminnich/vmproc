TEXT vmcall(SB), $0
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET

TEXT to64(SB), $0
	MOVL $48, BP
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	HLT
	RET
