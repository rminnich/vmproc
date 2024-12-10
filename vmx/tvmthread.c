#include <u.h>
#include <libc.h>
#include <thread.h>

int quiet;
int goal;
int buffer = 256;
int test;
int (*fn)(void(*)(void*), void*, uint) = threadcreate;
int vmthreadcreate(void (*fn)(void*), void *arg, uint stacksize);
extern u8int *vmbase;

Channel*vmthreadchan(int elemsize, int elemcnt);
void
primethread(void *arg)
{
	Channel *c, *nc;
	int p, i;

	c = arg;
	p = recvul(c);
	if(p > goal)
		threadexitsall(nil);
	if(!quiet)
		print("%d\n", p);
	nc = vmthreadchan(sizeof(ulong), buffer);
	(*fn)(primethread, nc, 1024);
	for(;;){
		i = recvul(c);
		if(i%p)
			sendul(nc, i);
	}
}

void
pong(void *arg)
{
	Channel *c;
	extern void *vmbase;
	int p;

	c = arg;
	c = (void *) 0x1000000;
	while (1) {
		p = recvul(c);
		sendul(c, p+1);
	}
}

void
setter(void *arg)
{
	u8int *c;
	extern u8int *vmbase, *vmend;
	uvlong *p;
	uvlong poison;
	for (int i = 0; i < 8; i++)
		poison = poison<<8 | (uvlong)"POISON?!"[i];

	c = arg;
//	c = (void *) 5; // 0x1000000;
//	c = vmbase;
	for(p = (void *)/*vmbase*/0x1000000; p < (void *)vmend; p++)
		*p = poison;
	while (1) {	*c = 1;}
}

void
watcher(void *arg)
{
	uvlong *c;

	c = arg;
	print("watcher: *c is %d\n", *c);
	while (! *c){
		print(".%d.", *c);
		sleep(1000);
		yield();
	}
}

void
threadmain(int argc, char **argv)
{
	static u8int brdot[] = {0xeb, 0xfe};
	int i, j;
	Channel *c;

	ARGBEGIN{
	case 'q':
		quiet = 1;
		break;
	case 'b':
		buffer = atoi(ARGF());
		break;
	case 't':
		test = atoi(ARGF());
		break;
	case 'p':
		fn=proccreate;
		break;
	}ARGEND

	print("Run test %d\n", test);
	if(argc>0)
		goal = atoi(argv[0]);
	else
		goal = 100;

	void vmthreadinit(uvlong lowmemsize, uvlong highmemsize);
	vmthreadinit(16*1024*1024, 64*1024*1024);

	switch (test) {
		default:
			print("%d:only valid tests are 1 to 2\n", test);
			sysfatal("bye");
			break;
		case 0:
			if (vmthreadcreate((void *)brdot, (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			break;
		case 1:
			threadcreate(watcher, vmbase, 1024);
			print("now run setter\n");
			if (vmthreadcreate(setter, (void *)9, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			print("setter created\n");

			print("ran setter, *vmbase is %lld\n", *(uvlong*)vmbase);
			break;
		// This test will not work until we get KPT=EPT. 		
		case -1:
			i = 221;
			c = vmthreadchan(sizeof(ulong), buffer);
			print("vmtheadchan@%p send ...", c);
			sendul(c, i);
			print("Sent ... recv j ...");
			j = recvul(c);
			print("sent %d got %d\n", i, j);
			i ++;
			print("Send i ...");
			nbsendul(c, i);
			print("Sent ... recv j ...");
			j = recvul(c);
			print("sent %d got %d\n", i, j);
			print("now run pong\n");
			if (vmthreadcreate(pong, c, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			while(1) {
				print("Send i ...");
				sendul(c, i);
				print("Sent ... recv j ...");
				j = recvul(c);
				print("sent %d got %d\n", i, j);
				i = j;
			}	
			break;
		case -2:
			c = vmthreadchan(sizeof(ulong), buffer);
			print("now run primethread\n");
			if (vmthreadcreate(primethread, c, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			for(i=2;; i++)
				sendul(c, i);

			print("ran primethread\n");
			break;

	}

	/*
	threadexits("ok");
	c = chancreate(sizeof(ulong), buffer);
	threadcreate(primethread, (void*)0xcafebabe, 1024);
	for(i=2;; i++)
		sendul(c, i);
	*/
}
