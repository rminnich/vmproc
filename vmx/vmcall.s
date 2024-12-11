TEXT vmcall(SB), $0
//	MOVL $32, AX
//	MOVL (AX), AX
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET
