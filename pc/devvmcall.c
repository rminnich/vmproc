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

// stateless walk.
// The QID is going to be a pointer to the allocate string with the full
// name. open, and stat, etc. will just use the name. done.
static Walkqid*
vmcallwalk(Chan *c, Chan *nc, char **name, int nname)
{
	int j, alloc;
	Walkqid *wq;

	if(nname > 0)
		isdir(c);

	alloc = (nc == nil);
	wq = smalloc(sizeof(Walkqid)+1*sizeof(Qid));
	if(waserror()){
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		free(wq);
		return nil;
	}
	if(alloc){
		nc = devclone(c);
		nc->type = 0;	/* device doesn't know about this channel yet */
	}
	wq->clone = nc;

	int sz = strlen(c->path->s+2);
	for(j = 0; j<nname;j++) {
		sz += strlen(name[j])+1;
	}
	char *nm = mallocz(sz, 1);
	strcpy(nm, c->path->s);
	for(j = 0; j<nname;j++) {
		strcat(nm, name[j]);
	}

	poperror();

	wq->nqid = 0; // 1
	wq->qid[0].path = (uvlong) nm;

	if(wq->clone != nil){
		/* attach cloned channel to same device */
		wq->clone->type = c->type;
	}
	return wq;
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
	error("vmcallstat");
	uvlong ret = vmcall(STAT, c->path->s, dp, n);
	return (int)ret;
}

static Chan*
vmcallopen(Chan *c, int omode)
{
	error("vmcallopen");
	uvlong ret = vmcall(OPEN, c->path->s, omode);
	if ((int)ret < 0) {
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
	error("vmcallclose");
	int ret = (int)vmcall(CLOSE, c->dev);
	if (ret < 0) {
		error("vmcallclose");
	}
}

static long
vmcallread(Chan *c, void *a, long n, vlong off)
{
	error("vmcallread");
	uvlong ret = vmcall(PREAD, c->dev, a, n, off);
	return (long)ret;
}

static long
vmcallwrite(Chan *c, void *a, long n, vlong off)
{
	error("vmcallwrite");
	uvlong ret = vmcall(PWRITE, c->dev, a, n, off);
	return (long)ret;
}


Dev vmcalldevtab = {
	'V',
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
