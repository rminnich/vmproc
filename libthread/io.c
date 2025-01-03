#include <u.h>
#include <libc.h>
#include <thread.h>
#include <draw.h>
#include <cursor.h>
#include <mouse.h>
#include "dat.h"
#include "fns.h"

int irqactive = -1;

u32int
iowhine(int isin, u16int port, u32int val, int sz, void *mod)
{
	if(isin)
		vmdebug("%s%sread from unknown i/o port %#ux ignored (sz=%d, pc=%#ullx)", mod != nil ? mod : "", mod != nil ? ": " : "", port, sz, rget(RPC));
	else
		vmdebug("%s%swrite to unknown i/o port %#ux ignored (val=%#ux, sz=%d, pc=%#ullx)", mod != nil ? mod : "", mod != nil ? ": " : "", port, val, sz, rget(RPC));
	return -1;
}

typedef struct IOHandler IOHandler;
struct IOHandler {
	u16int lo, hi;
	u32int (*io)(int, u16int, u32int, int, void *);
	void *aux;
};
;
IOHandler handlers[1];

static u32int
io0(int dir, u16int port, u32int val, int size)
{
	IOHandler *h;
	// TODO 	extern PCIBar iobars;
	PCIBar *p;

	for(h = handlers; h < handlers + nelem(handlers); h++)
		if(port >= h->lo && port <= h->hi)
			return h->io(dir, port, val, size, h->aux);
	/*
	for(p = iobars.busnext; p != &iobars; p = p->busnext)
		if(port >= p->addr && port < p->addr + p->length)
			return p->io(dir, port - p->addr, val, size, p->aux);
	*/
	return iowhine(dir, port, val, size, nil);
}

u32int iodebug[32];

u32int
io(int isin, u16int port, u32int val, int sz)
{
	int dbg;
	
	dbg = port < 0x400 && (iodebug[port >> 5] >> (port & 31) & 1) != 0;
	if(isin){
		val = io0(isin, port, val, sz);
		if(sz == 1) val = (u8int)val;
		else if(sz == 2) val = (u16int)val;
		if(dbg)
			vmdebug("in  %#.4ux <- %#.*ux", port, sz*2, val);
		return val;
	}else{
		if(sz == 1) val = (u8int)val;
		else if(sz == 2) val = (u16int)val;
		io0(isin, port, val, sz);
		if(dbg)
			vmdebug("out %#.4ux <- %#.*ux", port, sz*2, val);
		return 0;
	}
}
