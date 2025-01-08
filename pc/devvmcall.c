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
// We will only walk one component at a time, and let the code in chan.c pick
// up the mess.
static Walkqid*
vmcallwalk(Chan *c, Chan *nc, char **name, int nname)
{
	int alloc;
	Walkqid *wq;
	char *dp[128]; // for now.
	Dir *d;

	print("vmcallwalk, nname %d\n", nname);
	if(nname > 0)
		isdir(c);

	alloc = (nc == nil);
	wq = smalloc(sizeof(Walkqid)+nname*sizeof(Qid));
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
	for(j = 0; j < nnames; j++) {
	uvlong ret = vmcall(STAT, names[j], dp, sizeof(dp));
	convM2D(dp, sizeof(dp), &d, nil);
	pull out the dir info and set the qid. then move on.

	/* We store the full path in q->qid->path, if it is empty, this is our
	 * first time.
	 */
	char *p = (void *)c->qid.path;
	
	int sz = ((p != nil) ? strlen(p): 0) + strlen(name[1]) + 2;
	char *nm = mallocz(sz, 1);
	strcpy(nm, p);
	strcat(nm, "/");
	strcat(nm, name[0]);

	print("nm %p %s\n", nm, nm);
	poperror();

	wq->nqid = 1;
	wq->qid[0].path = (uvlong) nm;
	print("qid is %p path is %p\n", &wq->qid[0], nm);
	if(wq->clone != nil){
		/* attach cloned channel to same device */
		wq->clone->type = c->type;
	}
	return wq;
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
	print("vmcallstat chan %p qid %p, c->qid.path %p", c, &c->qid, c->qid.path);
	error("fuck");
	void *p = (void*)c->qid.path;
	if (p == nil)
		error("vmcallstat: nil");
	if ((uvlong)p < 0x2000000) {
		print("p %p\n", p);
		error("bad p");
	}
	print("vmcallstat name %p\n", p);
	uvlong ret = vmcall(STAT, p, dp, n);
	print("vmcallstat %s %#llx\n", p, ret);
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
	print("vmcallclose\n");
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
