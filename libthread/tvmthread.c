#include <u.h>
#include <libc.h>
#include <thread.h>
#include "/sys/src/libc/9syscall/sys.h"

int quiet;
int goal;
int buffer = 256;
int test;
int (*fn)(void(*)(void*), void*, uint) = threadcreate;
int vmthreadcreate(void (*fn)(void*), void *arg, uint stacksize);
extern u8int *vmbase;
extern int debug;

uvlong
fcall(void *ptr, uvlong a0, uvlong a1, uvlong a2, uvlong a3)
{
	uvlong fd;
	uvlong (*f)(uvlong, uvlong, uvlong, uvlong) = ptr;

	print("EFCALL:f(%#p, %#llx, %#llx, %#llx, %#llx)...", ptr, a0, a1, a2, a3);

 	fd = f(a0, a1, a2, a3);

	print("XFCALL:%lld\n", fd);

	return (uvlong)fd;
}

uvlong puts(uvlong i)
{
	char c = (char)i;
	uvlong ret;
	print("EPUTS:%#llx...", i);
	ret = write(1, &c, 1);
	print("XPUTS\n");
	return ret;
}

int
vprint(int fd, char *fmt, ...)
{
	uvlong vmcall(void *, void *, uvlong, uvlong, uvlong, uvlong);
	char buf[4096];
	va_list a;
	int len;

	memset(buf, 0, sizeof(buf));
	va_start(a, fmt);
	len = vsnprint(buf, sizeof(buf), fmt, a);
	va_end(a);

	if (len < 0) {
		memset(buf, 0, sizeof(buf));
		len = snprint(buf, sizeof(buf), "vsnprint:%r\n");
		vmcall(fcall, write, (uvlong)2, (uvlong)buf, (uvlong)len, (uvlong)0);
		return -1;
	}
	return vmcall(fcall, write, (uvlong)fd, (uvlong)buf, (uvlong)len, (uvlong)0);
}


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
	//c = (void *) 0x1000000;
	while (1) {
		p = recvul(c);
		sendul(c, p+1);
	}
}

void vhello(void *a1, void *a2, void *a3, void *a4)
{
	char hi[] = "hi from vmcall!\n"; 
	write(1,  hi, sizeof(hi)-1);
	print("arg is %p %p %p %p\n", a1, a2, a3, a4);
	// not yet ...print((char*)a1, a2, a3, a4);
}

void
setter(void *arg)
{
	extern void vmcall(uvlong, ...);
	u8int *c;
	extern u8int *vmbase, *vmend;
	uvlong *p;
	uvlong poison = 0xcafebabe;
	vmcall((uvlong)vhello, "hi %p %d", arg, 0xaa55);
	vmcall((uvlong)vhello, "hi");
	vmcall((uvlong)vhello, "hi");
	for(p = (void *)/*vmbase*/0x1000000; p < (void *)/*vmend*/0x4000000; p++)
		*p = poison;
	for (int i = 0; i < 8; i++){
		vmcall((uvlong)vhello);
		poison = poison<<8 | (uvlong)"POISON?!"[i];
	}

	c = arg;
//	c = (void *) 5; // 0x1000000;
//	c = vmbase;
	c += 0x666;
	while (1) {	*c = 1;}
}

uvlong
syscall(uvlong callno, uvlong a0, uvlong a1, uvlong a2, uvlong a3)
{
	uvlong ret = (uvlong)-1;
	int i;
	print("ESYSCALL:");
	switch(callno) {
		case OPEN:
			print("open %s %lld\n", (void *)a0, a1);
			i = open((void *)a0, (int)a1);
			print("XSYSCALL:fd %d\n", i);
			ret = (uvlong)i;
			break;
		case _READ:
			print("read(%d, %p,%d)\n", (int)a0, (void *)a1, (int)a2);
			i = read((int)a0, (void *)a1, (int)a2);
			print("XSYSCALL:fd %d\n", i);
			ret = (uvlong)i;
			break;
		case _WRITE:
			print("write(%d, %p,%d)\n", (int)a0, (void *)a1, (int)a2);
			i = write((int)a0, (void *)a1, (int)a2);
			print("XSYSCALL:fd %d\n", i);
			ret = (uvlong)i;
			break;

		case SYSR1:
		case _ERRSTR:
		case BIND:
		case CHDIR:
		case CLOSE:
		case DUP:
		case ALARM:
		case EXEC:
		case EXITS:
		case _FSESSION:
		case FAUTH:
		case _FSTAT:
		case SEGBRK:
		case _MOUNT:
		case OSEEK:
		case SLEEP:
		case _STAT:
		case RFORK:
		case PIPE:
		case CREATE:
		case FD2PATH:
		case BRK_:
		case REMOVE:
		case _WSTAT:
		case _FWSTAT:
		case NOTIFY:
		case NOTED:
		case SEGATTACH:
		case SEGDETACH:
		case SEGFREE:
		case SEGFLUSH:
		case RENDEZVOUS:
		case UNMOUNT:
		case _WAIT:
		case SEMACQUIRE:
		case SEMRELEASE:
		case SEEK:
		case FVERSION:
		case ERRSTR:
		case STAT:
		case FSTAT:
		case WSTAT:
		case FWSTAT:
		case MOUNT:
		case AWAIT:
		case PREAD:
		case PWRITE:
		case TSEMACQUIRE:
		case _NSEC:
		default:
			print("XSYSCALL:bad syscall(%#llx, %#llx, %#llx, %#llx, %#llx)\n", callno, a0, a1, a2, a3);
	}

	return ret;
}

void
network(void *arg)
{
	USED(arg);
	extern uvlong vmcall(uvlong,uvlong,void *,uvlong,uvlong, uvlong);
	int fd, cfd;
	char *addr = "icmp!127.1!1";
	char buf[256], cmd[256], id[256], clone[256];
	static uvlong amt;
	vprint(1, "addr is %s\n", addr);
	vmcall((uvlong)fcall,(uvlong)print, "let's go, addr %p!\n", (uvlong)addr, 0, 0);
	fd = vmcall((uvlong)syscall,OPEN, "/net/cs", 2, 0, 0);
	vmcall((uvlong)fcall,(uvlong)print, "fd is %p\n", (uvlong)fd, 0, 0);
	amt = vmcall((uvlong)syscall,_WRITE, (void *)fd, (uvlong)addr, strlen(addr),  0);
	vmcall((uvlong)fcall,(uvlong)print, "amt is %p\n", (uvlong)amt, 0, 0);
	memset(buf, 0, sizeof(buf));
	amt = vmcall((uvlong)syscall,_READ, (void *)fd, (uvlong)buf, sizeof(buf)-1, 0);
	vmcall((uvlong)fcall,(uvlong)print, "amt is %p buf is %s\n", (uvlong)amt, (uvlong)buf, 0);
	fd = (int)vmcall((uvlong)syscall, OPEN, "/net/icmp/clone", (uvlong)ORDWR,(uvlong) 0, 0);
	vmcall((uvlong)fcall, (uvlong)print,"NOTDIRECT:fd is %lld\n", fd, 0, 0);
	vmcall((uvlong)print, (uvlong)"DIRECT: fd is %lld\n", (void *)fd, 0, 0, 0);
	memset(id, 0, sizeof(id));
	vmcall((uvlong)syscall,_READ, (void *)fd, (uvlong)id, sizeof(id)-1, 0);
	vmcall((uvlong)print, (uvlong)"id %s\n", cmd, (uvlong)id, 0, 0);
	sprint(cmd, "connect %s", buf);
	amt = vmcall((uvlong)syscall,_WRITE, (void *)fd, (uvlong)cmd, strlen(cmd),  0);
	vmcall((uvlong)print, (uvlong)"cmd:%s, clone %s, cmd write %d\n", cmd, (uvlong)clone, amt, 0);


	while (1);
}

void
date(void *arg)
{
	USED(arg);
 	char buf[256];
	int fd, amt;
	extern uvlong vmcall(uvlong,uvlong,void *,uvlong,uvlong, uvlong);
	vmcall((uvlong)fcall,(uvlong)print, "date! %p!\n", (uvlong)buf, 0, 0);
	fd = vmcall((uvlong)syscall,OPEN, "/env/timezone", 0, 0, 0);
	vmcall((uvlong)fcall,(uvlong)print, "fd is %p\n", (uvlong)fd, 0, 0);
	amt = vmcall((uvlong)syscall,_READ, (void *)fd, (uvlong)buf, strlen(buf),  0);
	vmcall((uvlong)fcall,(uvlong)print, "amt is %p\n", (uvlong)amt, 0, 0);
	amt = vmcall((uvlong)syscall,_WRITE, (void *)1, (uvlong)buf, sizeof(buf)-1, 0);
	vmcall((uvlong)fcall,(uvlong)print, "amt is %p buf is %s\n", (uvlong)amt, (uvlong)buf, 0);
	while (1);
}

void
message(void *arg)
{
	USED(arg);
	extern uvlong vmcall(uvlong,uvlong,uvlong,uvlong,uvlong, uvlong);
	int i;
	char msg[] = "hi there\n";
	vmcall((uvlong)fcall,(uvlong)print, (uvlong)"let's go, addr %p :%s:!\n", (uvlong)msg, (uvlong)msg,  0);
	if (0)for(i = 0; i < 26; i++)
		vmcall((uvlong)puts, (uvlong)('A'+i), 0, 0, 0, 0);
	for(i = 0; i < sizeof("hi there\n")-1; i++)
		vmcall((uvlong)fcall, (uvlong)puts, (uvlong)(msg[i]), 0, 0, 0);
	while (1);
}

/*
1004 ping Open 209c8f 0x401718/"/dev/bintime" 0x20 = 3 "" 1735334648612860694 1735334648613596096
1004 ping Pread 205d95 3 0x7fffffffee60 8 0 0x7fffffffee60/"..%.1..." 8 0 = 8 "" 1735334648614354588 1735334648614359063
1004 ping Notify 209c9e 0x200059 = 0 "" 1735334648615758638 1735334648615759756
1004 ping Open 209c8f 0x7fffffffec68/"/net/cs" 0x2 = 4 "" 1735334648616963690 1735334648617119799
1004 ping Pwrite 205d86 4  0x7fffffffec68/ 12 -1 = 12 "" 1735334648618245881 1735334648618339584
1004 ping Seek 205d77 0x7fffffffea98 4 0x0 0 = 0 "" 1735334648619659993 1735334648619662667
1004 ping Pread 205d95 4 0x7fffffffec68 127 -1 0x7fffffffec68/"/net/icmp/clone.127.0.0.1!1" 127 -1 = 27 "" 1735334648620970080 1735334648621019088
1004 ping Open 209c8f 0x7fffffffe994/"/net/icmp/clone" 0x2 = 5 "" 1735334648622173597 1735334648622233892
1004 ping Pread 205d95 5 0x7fffffffe894 255 -1 0x7fffffffe894/"0" 255 -1 = 1 "" 1735334650308164124 1735334650308176544
1004 ping Pwrite 205d86 5  0x7fffffffe894/"connect.127.0.0.1!1" 19 -1 = 19 "" 1735334650309797343 1735334650309829501
1004 ping Open 209c8f 0x7fffffffe794/"/net/icmp/0/data" 0x2 = 6 "" 1735334650311204678 1735334650311273505
1004 ping Close 209cbc 5 = 0 "" 1735334650312544420 1735334650312555069
1004 ping Close 209cbc 4 = 0 "" 1735334650313500964 1735334650313560461
1004 ping Fd2path 205da4 6 0x7fffffffedd0 128"" 128 = 0  1735334650314679832 1735334650314683945
1004 ping Brk 205dc2 0x403878 = 0 "" 1735334650315731640 1735334650315734449
1004 ping Stat 205d68 0x4028e8/"/net/icmp/0" 0x4029b8 115 = 68 "" 1735334650316927418 1735334650316992458
1004 ping Open 209c8f 0x7fffffffec88/"/net/icmp/0/local" 0x20 = 4 "" 1735334650318235457 1735334650318288343
1004 ping Pread 205d95 4 0x7fffffffec88 127 -1 0x7fffffffec88/"127.0.0.1!61144." 127 -1 = 16 "" 1735334650319576664 1735334650319590148
1004 ping Close 209cbc 4 = 0 "" 1735334650320709489 1735334650320719616
1004 ping Open 209c8f 0x7fffffffec88/"/net/icmp/0/remote" 0x20 = 4 "" 1735334652774375445 1735334652774453612
1004 ping Pread 205d95 4 0x7fffffffec88 127 -1 0x7fffffffec88/"127.0.0.1!1." 127 -1 = 12 "" 1735334652776324753 1735334652776340760
1004 ping Close 209cbc 4 = 0 "" 1735334652777877994 1735334652777889004
1004 ping Pwrite 205d86 1  0x7fffffffecd8/"sending.32.64.byte.messages.1000.ms.apart.to.icmp!127.0.0.1!1." 62 -1sending 32 64 byte messages 1000 ms apart to icmp!127.0.0.1!1
 = 62 "" 1735334652779089818 1735334652780566417
*/
void directcall(void *arg)
{
	extern uvlong vmcall(void*,void*,uvlong,uvlong,uvlong);
	static int fd;	
	char *addr = "icmp!127.1!1";
	char buf[256];
	static uvlong amt;
	USED(arg);
	vmcall(print, "let's go, addr %p!\n", (uvlong)addr, 0, 0);
	fd = vmcall(open, "/net/cs", 2, 0, 0);
	vmcall(print, "fd is %d\n", fd, 0, 0);
	amt = vmcall(write, addr, sizeof(addr)-1, 0, 0);
	vmcall(print, "amt is %d\n", amt, 0, 0);
	memset(buf, 0, sizeof(buf));
	amt = vmcall(read, buf, sizeof(buf)-1, 0, 0);
	vmcall(print, "amt is %d buf is %s\n", amt, (uvlong)buf, 0);
	vmcall(print, "direct call\n", 0, 0, 0);
	fd = (int) vmcall(open, "/net/icmp/clone", ORDWR, 0, 0);
	vmcall(print, "fd is %d\n", fd, 0, 0);
	while(1);
}

void
watcher(void *arg)
{
	uvlong *c;

	c = arg;
	print("watcher: arg is %p *c is %#llx\n", arg, *c);
	while (! *c){
		if (debug > 2) print(".%#llx.", *c);
		sleep(1000);
		yield();
	}
	write(1, "WX\n", 3);
	threadexits(nil);
}

void
threadmain(int argc, char **argv)
{
	static u8int brdot[] = {0xeb, 0xfe};
	int i, j;
	Channel *c;
	uvlong forever = 0;
	extern void to64(void);

	test = 9;
	ARGBEGIN{
	case 'q':
		quiet = 1;
		break;
	case 'b':
		buffer = atoi(ARGF());
		break;
	case 'd':
		debug = atoi(ARGF());
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
	vmthreadinit(14*1024*1024, 64*1024*1024);
	memmove(vmbase+0x200000, (void*)0x200000, (uvlong)sbrk(0) - 0x200000);

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
		case 2:
			threadcreate(watcher, &forever, 1024);
			print("now run setter @%p \n",(u8int*)vmbase+(uvlong)setter);
			if (vmthreadcreate((void *)((u8int*)vmbase+(uvlong)setter), (void *)9, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			print("setter created\n");

			print("ran setter, *vmbase is %lld\n", *(uvlong*)vmbase);
			break;
		// This test will not work until we get KPT=EPT. 		
		case 3:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate((void *)(void *)((u8int*)vmbase+(uvlong)brdot), (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			break;
		case 4:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate((void *)(void *)((u8int*)vmbase+(uvlong)network), (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			break;
		case 5:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate((void *)(void *)((u8int*)vmbase+(uvlong)directcall), (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			break;
		case 6:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate ((void *)((u8int*)vmbase+(uvlong)message), (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			break;
		case 7:
			// test to64
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate ((void *)to64, (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			if (vmthreadcreate ((void *)((u8int*)vmbase+(uvlong)message), (void *)0x1000000, 1024) < 0) {
				exits("second vmthreadcreate failed");
			}
			break;

		case 8:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate ((void *)to64, (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			if (vmthreadcreate ((void *)((u8int*)vmbase+(uvlong)network), (void *)0x1000000, 1024) < 0) {
				exits("second vmthreadcreate failed");
			}
			break;

		case 9:
			threadcreate(watcher, &forever, 1024);
			if (vmthreadcreate ((void *)to64, (void *)0x1000000, 1024) < 0) {
				exits("vmthreadcreate failed");
			}
			if (vmthreadcreate ((void *)((u8int*)vmbase+(uvlong)date), (void *)0x1000000, 1024) < 0) {
				exits("second vmthreadcreate failed");
			}
			break;

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
			for(i=2;i<20; i++)
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
