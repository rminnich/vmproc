#include "mem.h"

TEXT vmcall(SB), $0
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET
