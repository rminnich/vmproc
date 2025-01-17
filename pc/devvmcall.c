#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"
#include "/sys/src/libc/9syscall/sys.h"

uvlong vmcall(uvlong, ...);

static int debug = 0;
#define vmdebug if(!debug) {} else print

enum
{
	Qdir=		0x8000,
};

Dirtab vmcalldir[]={
	".",	{Qdir, 0, QTDIR},	0,	DMDIR|0555,
};

// alloc and leak if it is too low.
static void *valloc(int amt) {
	void *v;
	while(PADDR(v = malloc(amt)) < 0x1000000)
		;
	vmdebug("valloc(%d): %p\n", amt, v);
	return v;
}

static void *vallocz(int amt, int zero) {
	void *v;
	while(PADDR(v = mallocz(amt, zero)) < 0x1000000)
		;
	vmdebug("vallocz(%d, %d): %p\n", amt, zero, v);
	return v;
}

static uvlong vmcallargs(uvlong *vec, uvlong scallno, int narg, ...)
{
	va_list ap;
	uvlong val;
	int i;

	vmdebug("vmcallargs: start vec %p, narg %d \n", vec, narg);
	va_start(ap, narg);
	vec[0] = scallno;
	vmdebug("vmcallargs: scallno %#llx\n", scallno);
	for(i = 1; i < narg+1; i++) {
		val = va_arg(ap, uvlong);
		vmdebug("vmcallargs: add arg %d, val %p\n", i, val);
		vec[i] = val;
	}
	va_end(ap);
	vmdebug("vmcallargs: return %p\n", PADDR(vec) | 0x8000000000000000);
	return PADDR(vec) | 0x8000000000000000;
}

static Chan*
vmcallattach(char *spec)
{
	Chan *c;
	c = devattach('V', spec);
	c->qid.path = Qdir;
	c->dev = -1;
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
	dp = valloc(128);
	vmdebug("vmcallwalk, p %s nname %d:",p, nname);
	for (j = 0; j < nname; j++){
		vmdebug("/%s", name[j]);
		fullpathlen += strlen(name[j])+1;
	}
	vmdebug("\n");
	vmdebug("again, nname %d\n", nname);
	if(nname > 0)
		isdir(c);

	vmdebug("c %p nc %p\n", c, nc);
	alloc = (nc == nil);
	vmdebug("alloc %d\n", alloc);
	wq = smalloc(sizeof(Walkqid)+nname*sizeof(Qid));
	if(waserror()){
		if(alloc && wq->clone != nil)
			cclose(wq->clone);
		free(wq);
		return nil;
	}
	vmdebug("wq %p\n", wq);
	if(alloc){
		nc = devclone(c);
		nc->type = 0;	/* device doesn't know about this channel yet */
	}
	vmdebug("devcloned nname %d nc %p wq %p\n", nname, nc, wq);
	wq->clone = nc;
	vmdebug("before for\n");
	int sz = strlen(p) + 1 /* for / */ + fullpathlen + 2; // for null and fudge
	vmdebug("sz %d\n", sz);
	char *nm = vallocz(sz, 1);
	if (nm == nil)
		panic("nm is nil?");
	if (p == nil)
		panic("p is nil?");
	vmdebug("nm is %p\n", nm);
	strcat(nm, p);
	strcat(nm, "/");
	vmdebug("nm %p %s\n", nm, nm);
	for(nqid = 0; nqid < nname; nqid++) {
		vmdebug("vmstat %s\n", name[nqid]);
		if (name[nqid] == nil)
			panic("nm %s name[%d] nil", nm, nqid);
			
		strcat(nm, name[nqid]);
		if (nqid < nname-1)
			strcat(nm, "/");
		vmdebug("nm %p %s\n", nm, nm);

		uvlong ret = vmcall(vmcallargs(vec, STAT, 3, PADDR(nm), PADDR(dp), 128));
		if ((int)ret < 0)
			break;
		vmdebug("convM2d?\n");
		convM2D(dp, 128, &d, nil);
		vmdebug("%s; qid %#llx %#lx %#x\n", nm, d.qid.path, d.qid.vers, d.qid.type);
		wq->qid[nqid] = d.qid;
	}
	vmdebug("after for nqid %d nnames %d\n", nqid, nname);

	if (nc && nqid == nname) {
		nc->aux = nm;
		if (nname > 0)
			nc->qid = wq->qid[nqid-1];
		nc->dev = -1;
	} else {
		free(nm);
	}

	poperror();
	vmdebug("after poperror");
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
	void *v = vallocz(n, 1);
	vmdebug("vmcallstat name %p dp %p\n", p, dp);
	uvlong ret = vmcall(vmcallargs(vec, STAT, 3, PADDR(p), PADDR(v), n));
	vmdebug("vmcallstat %s %#llx\n", p, ret);
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
	vmdebug("Open '%s'\n", p);
	uvlong ret = vmcall(vmcallargs(vec, OPEN, 2, PADDR(p), omode));
	vmdebug("ret is %lld\n", ret);
	if ((int)ret < 0) {
		error("vmcallopen failed");
	}
	vmdebug("ret is %d\n", (int)ret);
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
	// never opened?
	if (c->dev == -1)
		return;

	vmdebug("vmcallclose fd %#ld name %s\n", c->dev, c->aux);
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
	vmdebug("vmcallread fd %ld\n", c->dev);
	v = valloc(n);
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
	void *v = valloc(n);
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
