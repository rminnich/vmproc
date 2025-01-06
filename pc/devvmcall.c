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
	int i, j, alloc;
	Walkqid *wq;
	char *n;
	Dir dir;

	if(nname > 0)
		isdir(c);

	alloc = (nc == nil);
	wq = smalloc(sizeof(Walkqid)+(nname-1)*sizeof(Qid));
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

	// The vmcall support is doing all the checking. We just let it
	// do all the parsing. We'll preserve the component-at-a-time
	// walk for now.
	for(j=0; j<nname; j++){
		STAT
		CONVM2D
		figure out qid
		add it to array
		continue.

		if(!(nc->qid.type&QTDIR)){
			if(j==0)
				error(Enotdir);
			goto Done;
		}
		n = name[j];
		if(strcmp(n, ".") == 0){
    Accept:
			wq->qid[wq->nqid++] = nc->qid;
			continue;
		}
		if(strcmp(n, "..") == 0){
			if((*gen)(nc, nil, tab, ntab, DEVDOTDOT, &dir) != 1){
				print("devgen walk .. in dev%s %llux broken\n",
					devtab[c->type]->name, c->qid.path);
				error("broken devgen");
			}
			nc->qid = dir.qid;
			goto Accept;
		}
		/*
		 * Ugly problem: If we're using devgen, make sure we're
		 * walking the directory itself, represented by the first
		 * entry in the table, and not trying to step into a sub-
		 * directory of the table, e.g. /net/net. Devgen itself
		 * should take care of the problem, but it doesn't have
		 * the necessary information (that we're doing a walk).
		 */
		if(gen==devgen && nc->qid.path!=tab[0].qid.path)
			goto Notfound;
		for(i=0;; i++) {
			switch((*gen)(nc, n, tab, ntab, i, &dir)){
			case -1:
			Notfound:
				if(j == 0)
					error(Enonexist);
				kstrcpy(up->errstr, Enonexist, ERRMAX);
				goto Done;
			case 0:
				continue;
			case 1:
				if(strcmp(n, dir.name) == 0){
					nc->qid = dir.qid;
					goto Accept;
				}
				continue;
			}
		}
	}
	/*
	 * We processed at least one name, so will return some data.
	 * If we didn't process all nname entries succesfully, we drop
	 * the cloned channel and return just the Qids of the walks.
	 */
Done:
	poperror();
	if(wq->nqid < nname){
		if(alloc)
			cclose(wq->clone);
		wq->clone = nil;
	}else if(wq->clone != nil){
		/* attach cloned channel to same device */
		wq->clone->type = c->type;
	}
	return wq;
}

static int
vmcallstat(Chan *c, uchar *dp, int n)
{
call DIRSTAT here -- make it 120
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
