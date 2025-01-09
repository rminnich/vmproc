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

static uvlong vmcallargs(uvlong *vec, uvlong scallno, ...)
{
	va_list ap;
	uvlong val;
	int i = 1;

	va_start(ap, scallno);
	vec[0] = scallno;
	while ((val = va_arg(ap, uvlong)) != 0) {
		vec[i++] = val;
	}
	va_end(ap);
	return PADDR(vec) | 0x8000000000000000;
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

// stateless walk.
// We will only walk one component at a time, and let the code in chan.c pick
// up the mess.
static Walkqid*
vmcallwalk(Chan *c, Chan *nc, char **name, int nname)
{
	int alloc;
	Walkqid *wq;
	uchar dp[128]; // for now.
	Dir d;
	int nqid, j;
	int fullpathlen = 2;
	uvlong vec[8];

	print("vmcallwalk, nname %d:", nname);
	for (j = 0; j < nname; j++){
		print("/%s", name[j]);
		fullpathlen += strlen(name[j])+1;
	}
	print("\n");
	print("again, nname %d\n", nname);
	if(nname > 0)
		isdir(c);

	print("nc %p\n", nc);
	if (nname>0) error("fuck");
	alloc = (nc == nil);
	print("alloc %d\n", alloc);
	wq = smalloc(sizeof(Walkqid)+nname*sizeof(Qid));
	if(waserror()){
		if(0)
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		if(0)
		free(wq);
		return nil;
	}
	print("wq %p\n", wq);
	if(alloc){
		nc = devclone(c);
		nc->type = 0;	/* device doesn't know about this channel yet */
	}
	print("devcloned nname %d nc %p wq %p\n", nname, nc, wq);
	if (nname>0) error("fuck");
	wq->clone = nc;
	print("before for\n");
	for(nqid = 0; nqid < nname; nqid++) {
		print("vmstat %s\n", name[j]);
		uvlong ret = vmcall(vmcallargs(vec, STAT, PADDR(name[j]), PADDR(dp), sizeof(dp)));
		if ((int)ret < 0)
			break;
		print("convM2d?\n");
		convM2D(dp, sizeof(dp), &d, nil);
		wq->qid[nqid] = d.qid;
	}
	print("after for nqid %d\n", nqid);
	if (nname > 0)
	error("fuck");
	int sz = 1 /* for / */ + fullpathlen + 2;
	print("sz %d\n", sz);
	char *nm = mallocz(sz, 1);
	print("nm is %p\n", nm);
	strcat(nm, "/");
	for(j = 0; j < nname; j++)
		strcat(nm, name[j]);

	print("nm %p %s\n", nm, nm);
	poperror();
	print("after poperror");
	wq->nqid = nqid;
	//wq->qid[0].path = (uvlong) nm;
	if(wq->clone != nil){
		/* attach cloned channel to same device */
		wq->clone->type = c->type;
	}
	return wq;
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
	char *p = "/";
	uvlong vec[8];
	print("vmcallstat name %p\n", p);
	uvlong ret = vmcall(vmcallargs(vec, STAT, PADDR(p), PADDR(dp), n));
	print("vmcallstat %s %#llx\n", p, ret);
	return (int)ret;
}

static Chan*
vmcallopen(Chan *c, int omode)
{
	error("vmcallopen");
	uvlong vec[8];
	uvlong ret = vmcall(vmcallargs(vec, OPEN, PADDR(c->path->s), omode));
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
	uvlong vec[8];
	int ret = (int)vmcall(vmcallargs(vec, CLOSE, c->dev));
	if (ret < 0) {
		error("vmcallclose");
	}
}

static long
vmcallread(Chan *c, void *a, long n, vlong off)
{
	error("vmcallread");
	uvlong vec[8];
	uvlong ret = vmcall(vmcallargs(vec, PREAD, c->dev, PADDR(a), n, off));
	return (long)ret;
}

static long
vmcallwrite(Chan *c, void *a, long n, vlong off)
{
	uvlong vec[8];
	error("vmcallwrite");
	uvlong ret = vmcall(vmcallargs(vec, PWRITE, c->dev, PADDR(a), n, off));
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
