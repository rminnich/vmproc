#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"
#include "/sys/src/libc/9syscall/sys.h"

uvlong vmcall(uvlong, ...);

static int vvdebug = 0;
#define vmdebug if(!vvdebug) {} else print

static int vdebug = 0;

enum
{
	Qdir=		0x8000,
};

Dirtab vmcalldir[]={
	".",	{Qdir, 0, QTDIR},	0,	DMDIR|0555,
};

// alloc and leak if it is too low.
static void *valloc(char *who, int amt) {
	void *v;
	while(PADDR(v = malloc(amt)) < 0x1000000)
		;
	if (vdebug) print("%s:valloc(%d): %p\n", who, amt, v);
	return v;
}

static void *vallocz(char *who,int amt, int zero) {
	void *v;
	while(PADDR(v = mallocz(amt, zero)) < 0x1000000)
		;
	if (vdebug) print("%s:vallocz(%d, %d): %p\n", who,amt, zero, v);
	return v;
}

static void vfree(char *who, void *p)
{
	free(p);
	if (vdebug) print("%s:free %p\n", who, p);
}

static uvlong vmcallargs(uvlong *vec, uvlong scallno, char *err, int nerr, int narg, ...)
{
	va_list ap;
	uvlong val;
	int i;

	vmdebug("vmcallargs: start vec %p, narg %d \n", vec, narg);
	va_start(ap, narg);
	vec[0] = scallno;
	vec[1] = PADDR(err);
	vec[2] = (uvlong)nerr;
	vmdebug("vmcallargs: scallno %#llx\n", scallno);
	for(i = 0; i < narg; i++) {
		val = va_arg(ap, uvlong);
		vmdebug("vmcallargs: add arg %d, val %p\n", i, val);
		vec[i+3] = val;
	}
	va_end(ap);
	vmdebug("vmcallargs: return %p\n", PADDR(vec) | 0x8000000000000000);
	return PADDR(vec) | 0x8000000000000000;
}

static Chan*
vmcallattach(char *spec)
{
	Chan *c;
	c = devattach('Z', spec);
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
	char *err;
	char *p = c->aux ? c->aux : "/";
	vmdebug("vmcallwalk, c %p, c->aux %p, p %s nname %d:, name'", c, c->aux, p, nname);
	for (j = 0; j < nname; j++){
		vmdebug("/%s", name[j]);
		fullpathlen += strlen(name[j])+1;
	}
	vmdebug("'\n");
	dp = valloc("walk dp", 128);
	err = valloc("walk err", ERRMAX);
	if (waserror()) {
		free(dp);
		vmdebug("Walk returns nil after errors\n");
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("walk err", err);
		return nil;
	}
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
		nexterror();
	}
	vmdebug("wq %p\n", wq);
	if(alloc){
		nc = devclone(c);
		nc->aux = nil; // we do not clone the name.
		nc->type = 0;	/* device doesn't know about this channel yet */
	}
	vmdebug("devcloned nname %d nc %p wq %p\n", nname, nc, wq);
	wq->clone = nc;
	vmdebug("before for\n");
	int sz = strlen(p) + 1 /* for / */ + fullpathlen + 2; // for null and fudge
	vmdebug("sz %d\n", sz);
	char *nm = vallocz("walk name", sz, 1);
	if (waserror()) {
		free(nm);
		nexterror();
	}
	if (nm == nil)
		panic("nm is nil?");
	if (p == nil)
		panic("p is nil?");
	vmdebug("nm is %p\n", nm);
	strcat(nm, p);
	strcat(nm, "/");
	vmdebug("before for nm %p %s\n", nm, nm);
	for(nqid = 0; nqid < nname; nqid++) {
		vmdebug("vmstat %s\n", name[nqid]);
		if (name[nqid] == nil)
			panic("nm %s name[%d] nil", nm, nqid);
			
		strcat(nm, name[nqid]);
		if (nqid < nname-1)
			strcat(nm, "/");
		vmdebug("nm %p %s\n", nm, nm);

		uvlong ret = vmcall(vmcallargs(vec, STAT, err, ERRMAX, 3, PADDR(nm), PADDR(dp), 128));
		if ((int)ret < 0) {
			vmdebug("%s: not found\n", nm);
			error(err);
		}
		vmdebug("convM2d?\n");
		convM2D(dp, 128, &d, nil);
		vmdebug("%s; qid %#llx %#lx %#x\n", nm, d.qid.path, d.qid.vers, d.qid.type);
		wq->qid[nqid] = d.qid;
	}
	vmdebug("after for nqid %d nnames %d\n", nqid, nname);

	if (nc && nqid == nname) {
		nc->aux = nm;
		if (nname > 0){
			nc->qid = wq->qid[nqid-1];
			nc->path = newpath(name[nname-1]);
		} else {
			incref(c->path);
			nc->path = c->path;
		}
		nc->dev = -1;
	}
	poperror();
	poperror();
	poperror();
	vmdebug("after poperror");
	vfree("walk err", err);
	vfree("walk dp", dp);
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
	char *err;
	char *p = c->aux;
	if (!c->aux)
		error("c->aux is nil");
	uvlong *vec = vallocz("vmcallstat vec", 8*sizeof(uvlong), 1);
	void *v = vallocz("vmcallstat err", n, 1);
	vmdebug("vmcallstat name %s addr %p dp %p\n", p, p, dp);
	err = valloc("vmcallread error", ERRMAX);
	if (waserror()) {
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("vmcallstat", v);
		vfree("vmcallstat vec", vec);
		vfree("vmcallstat err", err);
	}
	uvlong ret = vmcall(vmcallargs(vec, STAT, err, ERRMAX, 3, PADDR(p), PADDR(v), n));
	vmdebug("vmcallstat %s returns %#llx, want %d\n", p, ret, n);
	if ((int)ret < 0)
		error("vmcallstat");
	poperror();
	memmove(dp, v, n);
	vfree("vmcallstat", v);
	vfree("vmcallstat vec", vec);
	vfree("vmcallstat err", err);
	return (int)ret;
}

static Chan*
vmcallopen(Chan *c, int omode)
{
	char *err;
	char *p = c->aux;
	static 	uvlong vec[8];
	if (! p)
		error("vmcallopen:no path");
	vmdebug("Open '%s'\n", p);
	err = valloc("open err", ERRMAX);
	if (waserror()) {
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("open err", err);
		error(up->errstr);
	}
	uvlong ret = vmcall(vmcallargs(vec, OPEN, err, ERRMAX, 2, PADDR(p), (uvlong)omode));
	vmdebug("ret is %lld\n", ret);
	if ((int)ret == -1) {
		error("vmcallopen thread error");
	}
	while(!(vec[0] & (1ull << 62)))
		sched();

	if ((vlong)vec[0] == -1) {
		error("syscall error");
	}
	poperror();
	ret = (u32int) vec[0];
	vmdebug("ret is %d\n", (int)ret);
	c->dev = ret;
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	vmdebug("open: set c %p c->dev %ld c->mode %d\n", c, c->dev, c->mode);
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
	char *err;
	static 	uvlong vec[8];
	// this is called right before the channel is freed.
	// freeing aux is safe.
	err = valloc("close err", ERRMAX);
	vmdebug("vmcallclose c %p c->aux %p\n", c, c->aux);
	vfree("vmcallclose", c->aux);
	c->aux = nil;
	// never opened?
	if (c->dev == -1)
		return;

	vmdebug("vmcallclose fd %#ld name %s\n", c->dev, c->aux);
	int ret = (int)vmcall(vmcallargs(vec, CLOSE, err, ERRMAX, 1, c->dev));
	if (ret < 0) {
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("close err", err);
		error("vmcall close");
	}
	vfree("close err", err);
}

static long
vmcallread(Chan *c, void *a, long n, vlong off)
{
	char *err;
	void *v;
	static 	uvlong vec[8];
	vmdebug("vmcallread c %p fd %lud a %p n %ld off %lld\n", c, c->dev, a, n, off);
	v = valloc("vmcallread", n);
	err = valloc("vmcallread error", ERRMAX);
	if (waserror()) {
		vfree("vmcallread", v);
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("vmcallread error", err);
		return -1;
	}
	int ret = (int)vmcall(vmcallargs(vec, PREAD, err, ERRMAX, (uvlong)4, (uvlong)c->dev, PADDR(v), (uvlong)n, (uvlong)off));
	vmdebug("ret is %d\n", ret);
	if ((int)ret == -1) {
		error("read"); 
	}
	vmdebug("Spin on vec[0] %#llx\n", vec[0]);
	while(!(vec[0] & (1ull << 62)))
		sched();
	vmdebug(" done Spin on vec[0] %#llx\n", vec[0]);

	if ((vlong)vec[0] == -1) {
		error("read");
	}
	ret = (u32int) vec[0];
	vmdebug("ret is %d\n", (int)ret);
	memmove(a, v, n);
	poperror();
	vfree("vmcallread", v);
	vfree("vmcallread error", err);
	return (long)ret;
}

static long
vmcallwrite(Chan *c, void *a, long n, vlong off)
{
	char *err;
	static 	uvlong vec[8];
	void *v = valloc("vmcallwrite", n);
	err = valloc("vmcallwrite error", ERRMAX);
	vmdebug("vmcallwrite: c %p fd %lud a %p n %ld off %lld\n", c, c->dev, a, n, off);
	if (waserror()) {
		vfree("vmcallread", v);
		kstrcpy(up->errstr, err, ERRMAX);
		vfree("vmcallwrite error", err);
		return -1;
	}
	memmove(v, a, n);
	int ret = (int)vmcall(vmcallargs(vec, PWRITE, err, ERRMAX, 4, c->dev, PADDR(v), n, off));
	if (ret < 0)
		error(err);
	poperror();
	vfree("vmcallwrite", v);
	vfree("vmcallwrite error", err);
	return (long)ret;
}


Dev vmcalldevtab = {
	'Z',
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
