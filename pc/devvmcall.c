#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"
#include "/sys/src/libc/9syscall/sys.h"

uvlong vmcall(uvlong, ...);

enum
{
	Qdir=		0x8000,
};

Dirtab vmcalldir[]={
	".",	{Qdir, 0, QTDIR},	0,	DMDIR|0555,
};

static int
vmcallgen(Chan *c, char*, Dirtab *tab, int ntab, int i, Dir *dp)
{
	Qid qid;

	if(i == DEVDOTDOT){
		mkqid(&qid, Qdir, 0, QTDIR);
		devdir(c, qid, ".", 0, eve, 0555, dp);
		return 1;
	}
	return 1;
}

static Chan*
vmcallattach(char *spec)
{
	Chan *c;
	int i  = (spec && *spec) ? strtol(spec, 0, 0) : 1;
	c = devattach('V', spec);
	c->qid.path = Qdir;
	c->dev = i;
	return c;
}

static Walkqid*
vmcallwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, vmcalldir, nelem(vmcalldir), vmcallgen);
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
	uvlong ret = vmcall(STAT, c->path->s, dp, n);
	return (int)ret;
}

static Chan*
vmcallopen(Chan *c, int omode)
{
	uvlong ret = vmcall(OPEN, c->path->s, omode);
	if (ret < 0) {
		error("vmcallopen failed");
	}
	c->dev = ret;
	return c;
}

static Chan*
vmcallcreate(Chan*, char*, int, ulong)
{
	error(Eperm);
}

static void
vmcallclose(Chan *c)
{
	int ret = (int)vmcall(CLOSE, c->dev);
	if (ret < 0) {
		error("vmcallclose");
	}
}

static long
vmcallread(Chan *c, void *a, long n, vlong off)
{
	uvlong ret = vmcall(PREAD, c->dev, a, n, off);
	return (long)ret;
}

static long
vmcallwrite(Chan *c, void *a, long n, vlong off)
{
	uvlong ret = vmcall(PWRITE, c->dev, a, n, off);
	return (long)ret;
}

static void
outch(int c)
{
	vmcall((uvlong)(char)c);
}

Dev vmcalldevtab = {
	'L',
	"vmcall",

	devreset,
	devinit,
	devshutdown,
	vmcallattach,
	vmcallwalk,
	vmcallstat,
	vmcallopen,
	vmcallcreate,
	vmcallclose,
	vmcallread,
	devbread,
	vmcallwrite,
	devbwrite,
	devremove,
	devwstat,
};
