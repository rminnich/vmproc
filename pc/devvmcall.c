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

static uvlong vmcallargs(uvlong *vec, uvlong scallno, int narg, ...)
{
	va_list ap;
	uvlong val;
	int i;

	print("vmcallargs: start vec %p, narg %d \n", vec, narg);
	va_start(ap, narg);
	vec[0] = scallno;
	print("vmcallargs: scallno %#llx\n", scallno);
	for(i = 1; i < narg+1; i++) {
		val = va_arg(ap, uvlong);
		print("vmcallargs: add arg %d, val %p\n", i, val);
		vec[i] = val;
	}
	va_end(ap);
	print("vmcallargs: return %p\n", PADDR(vec) | 0x8000000000000000);
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
	uchar *dp;
	Dir d;
	int nqid, j;
	int fullpathlen = 2;
	static 	uvlong vec[8];
	char *p = c->aux ? c->aux : "/";
	dp = malloc(128);
	print("vmcallwalk, p %s nname %d:",p, nname);
	for (j = 0; j < nname; j++){
		print("/%s", name[j]);
		fullpathlen += strlen(name[j])+1;
	}
	print("\n");
	print("again, nname %d\n", nname);
	if(nname > 0)
		isdir(c);

	print("c %p nc %p\n", c, nc);
	alloc = (nc == nil);
	print("alloc %d\n", alloc);
	wq = smalloc(sizeof(Walkqid)+nname*sizeof(Qid));
	if(waserror()){
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		free(wq);
		return nil;
	}
	print("wq %p\n", wq);
	if(alloc){
		nc = devclone(c);
		nc->type = 0;	/* device doesn't know about this channel yet */
	}
	print("devcloned nname %d nc %p wq %p\n", nname, nc, wq);
	wq->clone = nc;
	print("before for\n");
	int sz = strlen(p) + 1 /* for / */ + fullpathlen + 2; // for null and fudge
	print("sz %d\n", sz);
	char *nm = mallocz(sz, 1);
	print("nm is %p\n", nm);
	strcat(nm, p);
	strcat(nm, "/");
	print("nm %p %s\n", nm, nm);
	for(nqid = 0; nqid < nname; nqid++) {
		print("vmstat %s\n", name[nqid]);
		strcat(nm, name[nqid]);
		if (nqid < nname-1)
			strcat(nm, "/");
		print("nm %p %s\n", nm, nm);

		uvlong ret = vmcall(vmcallargs(vec, STAT, 3, PADDR(nm), PADDR(dp), 128));
		if ((int)ret < 0)
			break;
		print("convM2d?\n");
		convM2D(dp, 128, &d, nil);
		print("%s; qid %#llx %#llx %x\n", nm, d.qid.path, d.qid.vers, d.qid.type);
		wq->qid[nqid] = d.qid;
	}
	print("after for nqid %d nnames %d\n", nqid, nname);
	if (nc && nqid == nname) {
		nc->aux = nm;
		nc->qid = wq->qid[nqid-1];
	} else {
		free(nm);
	}

	poperror();
	print("after poperror");
	wq->nqid = nqid;
	if(wq->clone != nil){
		/* attach cloned channel to same device */
		wq->clone->type = c->type;
	}
	return wq;
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
	char *p = c->aux;
	if (!c->aux)
		error("c->aux is nil");
	static 	uvlong vec[8];
	void *v = mallocz(n, 1);
	print("vmcallstat name %p dp %p\n", p, dp);
	uvlong ret = vmcall(vmcallargs(vec, STAT, 3, PADDR(p), PADDR(v), n));
	print("vmcallstat %s %#llx\n", p, ret);
	memmove(dp, v, n);
	free(v);
	return (int)ret;
}

static Chan*
vmcallopen(Chan *c, int omode)
{
	char *p = c->aux;
	static 	uvlong vec[8];
	if (! p)
		error("vmcallopen:no path");
	print("Open '%s'\n", p);
	uvlong ret = vmcall(vmcallargs(vec, OPEN, 2, PADDR(p), omode));
	print("ret is %lld\n", ret);
	if ((int)ret < 0) {
		error("vmcallopen failed");
	}
	print("ret is %d\n", (int)ret);
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
	static 	uvlong vec[8];
	print("vmcallclose fd %#ld\n", c->dev);
	int ret = (int)vmcall(vmcallargs(vec, CLOSE, 1, c->dev));
	if (ret < 0) {
		error("vmcallclose");
	}
}

static long
vmcallread(Chan *c, void *a, long n, vlong off)
{
	void *v;
	static 	uvlong vec[8];
	print("vmcallread fd %ld\n", c->dev);
	v = malloc(n);
	if (waserror()) {
		free(v);
	}
	uvlong ret = vmcall(vmcallargs(vec, PREAD, (uvlong)4, (uvlong)c->dev, PADDR(v), (uvlong)n, (uvlong)off));
	if ((int)ret < 0)
		error("vmcallread");
	memmove(a, v, n);
	poperror();
	free(v);
	return (long)ret;
}

static long
vmcallwrite(Chan *c, void *a, long n, vlong off)
{
	static 	uvlong vec[8];
	void *v = malloc(n);
	memmove(v, a, n);
	uvlong ret = vmcall(vmcallargs(vec, PWRITE, 4, c->dev, PADDR(v), n, off));
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
