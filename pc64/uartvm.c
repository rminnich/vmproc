#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "../pc/io.h"

uvlong vmcall(uvlong, ...);

extern PhysUart vmphysuart;

static Uart vmuart = {
	.name = "vmcons",
	.freq = 1843200,
	.phys = &vmphysuart,
};

struct {
	Lock txlock;
} vmcons;

/*
 * Debug print to vm "emergency console".
 * Output only appears if vm is built with verbose=y
 */
void
dprint(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	vmcall('V');
	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	for(int i = 0; i < n; i++)
		vmcall(buf[i]);
}

static void kick(Uart*);
/*
 * Emit a string to the guest OS console, bypassing the queue
 *   - before serialoq is initialised
 *   - when rdb is activated
 *   - from iprint() for messages from interrupt routines
 * If ring is full, just throw extra output away.
 */
static void
vmuartputs(char *s, int n)
{
	vmcall('V');

	ilock(&vmcons.txlock);
	while (n-- > 0)
		vmcall(*s++);
	iunlock(&vmcons.txlock);
}

/*
 * Handle channel event from console
 */
static void
interrupt(Ureg*, void*)
{
	// nothing to do.
}

static Uart*
pnp(void)
{
	return &vmuart;
}

static void
enable(Uart*, int)
{
}

static void
disable(Uart*)
{
}

/*
 * Send queued output to guest OS console
 */
static void
kick(Uart*)
{
}

static void
donothing(Uart*, int)
{
}

static int
donothingint(Uart*, int)
{
	return 0;
}

static int
baud(Uart *uart, int n)
{
	if(n <= 0)
		return -1;

	uart->baud = n;
	return 0;
}

static int
bits(Uart *uart, int n)
{
	switch(n){
	case 7:
	case 8:
		break;
	default:
		return -1;
	}

	uart->bits = n;
	return 0;
}

static int
stop(Uart *uart, int n)
{
	if(n != 1)
		return -1;
	uart->stop = n;
	return 0;
}

static int
parity(Uart *uart, int n)
{
	if(n != 'n')
		return -1;
	uart->parity = n;
	return 0;
}

void
vmputc(Uart*, int c)
{
	vmcall('V');
	vmcall(c&0x7f);
}

int
vmgetc(Uart*)
{
	return 0;
}

PhysUart vmphysuart = {
	.name		= "vmuart",

	.pnp		= pnp,
	.enable		= enable,
	.disable	= disable,
	.kick		= kick,
	.dobreak	= donothing,
	.baud		= baud,
	.bits		= bits,
	.stop		= stop,
	.parity		= parity,
	.modemctl	= donothing,
	.rts		= donothing,
	.dtr		= donothing,
	.fifo		= donothing,

	.getc		= vmgetc,
	.putc		= vmputc,
};

/* console=0 to enable */
void
vmconsinit(void)
{
	consuart = &vmuart;
	consuart->console = 1;
}

void
uartvmconsole(void)
{
	Uart *uart;

	while(1)
	vmcall('T');
	vmuartputs("VM\n", 3);
	uartputs("PUTIT\n", 7);
	// always enable.
	uart = &vmuart;

	consuart = uart;
	uart->console = 1;
}

