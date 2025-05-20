.\" mk slides.show
.de IT
.if !"\\$1"" .ds BX \\$1
.if "\\$1"" .ds BX \(bu
.IP \\*(BX
..
.de SS
.ds CH \s+2\f3\\$1\fP\s-2
.bp
.LP
.na
..
.nr PO 0.5i
.nr HM 1i
.nr PS 18
.nr VS 24p
.nr PD 6p
.nr LL 6.5i
.ds CH "
.pl 11i
.ds RF "
.TL
VMs as threads
.AU
Ron Minnich
.AI
where you live
.P1
vmthreadinit(16*1024*1024, 64*1024*1024);
static u8int brdot[] = {0xeb, 0xfe};
vmthreadcreate(brdot, nil, 1024);
.P2
.PP
.SS "A quick review of VMs
.PS
P: box "Process"
box wid 2i ht 1.3i "memory" "Registers" "Proc" "Page Table" with .nw at P.se +(.2i,-.1i)
K: box "Kernel" with .n at P.s + (0,-2i)
arrow "trap/syscall" "RETQ" <-> from P.s to K.n
V: box "VM" with .w at P.e + (3i,0)
L: box "Kernel" with .n at V.s + (0,-2i)
arrow "vmexit/vmcall" "vmresume" <-> from V.s to L.n
box wid 2i ht 2i "Memory" "Registers" "Proc" "Page table" "VMCS" with .nw at V.se +(.2i,-.1i)
.PE
.IT
Processes have state, VMs have state
.IT
Processes have traps (involuntary), syscalls (voluntary)
.IT
VMs have VMEXITs (involuntary), vmcalls (voluntary)
.IT 
VMs have more state, 4096 bytes or more on x86
.IT
VMs have a page table to map VM physical to host physical
.IT
Overall, however, process activation and VM activation are very similar
.IT
It's the implementations that add unnecessary complication
.SS "But what about VMs are different?
.IT
Presotto: "We have a virtual machine, it's called user mode"
.IT
That's actually kind of fair: all processes have address 0, for example
.IT
But VMs can do some special things
.IT
VMs are allowed to set up page tables
.IT
VMs can take interrupts
.IT
VMs can create and run processes
.IT
VMs can run in protection modes not allowed for kernel or user mode
.IT
Simply put, VMs can do things kernels can not do
.IT
and things kernels CAN do (with restrictions)
.SS "Restriction example: paging
.PS
K: box  wid 1i "kernel"
P: box wid 1i "process"  with .s at K.n+(0,1i)
L: box  wid 1i "kernel" "page" "tables" ht 1.5i with .w at K.e +(3, 0)
Q: box  wid 1i "process" " page" "tables" ht 1.5i with .w at P.e +(3,0)
X: box  wid 1i "VM" "external" "page" "tables" ht 1.5i with .s at Q.n+(0,1i)
W: box wid 1i "VM" "page" "table" ht 1.5i with .e at X.w +(-1,0)
V: box  wid 1i "VM" with .e at W.w +(-1,0)
M: box  wid 1i "memory" ht 1i with .nw at X.ne + (1i,-2i)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" "" from L.e to M.w
arrow "physical" from Q.e to M.w


arrow "guest" "" "virtual" "" from V.e to W.w
arrow "guest" "" "physical" "" from W.e to X.w
arrow "physical" "" from X.e to M.w

.PE
.IT
There are page tables in the VM, and outside the vm
.IT
"For any virtual memory access, the original virtual address is converted ..., into a guest physical address. The guest physical address is then converted in the second stage by guest physical address translation, ... into a physical address. "
.IT
Sounds simple!
.SS "Not as simple as docs imply
.PS

F: box ht .7i "guest" "PML4"
box ht .7i "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
M: box "Memory" ht 1.5i with .nw at last box.ne + (.4,0)
arrow from 2nd last box.e to M.w +(0,.1)

G:box ht .7i "guest" "PML3" with .n at F.s - (0,.1)
spline -> from M.e + (0,.1) right .4 then down 4 then left 6.4 then up 2 then to G.w
box ht .7i "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow from last box.e to M.w 

H:box ht .7i "guest" "PML3" with .n at G.s - (0,.1)
spline -> from M.e right .3 then down 3.7 then left 6.2 then up 1.5 then to H.w
box ht .7i "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow from last box.e to M.w +(0,-.1)

I:box ht .7i "guest" "PML2" with .n at H.s - (0,.1)
spline  -> from M.e + (0,-.1) right .2 then down 3 then left 6 then up 1 then to I.w
box ht .7i "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box ht .7i "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow "physical" "" "address" from last box.e to M.s +(0,-.55) then to M.s

.PE
.IT
Every physical address must be translated by the external page table
.IT
Page tables in the VM use physical addresses
.IT
So 4K page table pages in a VM result in a lot more memory traffic than you'd think
.IT
Pro tip: always use at least 1G pages in the guest!
.SS "In Akaros, processes and VMs are a single abstraction
.IT
Get the abstraction right and all else follows
.IT
Akaros Kernel Code: about 5KLOC
.IT
Hard to tell any more, as it is integrated so completely into the process
model
.IT
But our vmx directory is 2KLOC so I multiplied by 2.5; almost certainly too
high
.IT
User libraries: about 12 KLOC
.IT
Includes user mode scheduler for VM threads
.IT
VMM: 690 LOC (not K!)
.IT
This is sufficient to boot full Google production stack, schedule jobs, use 
local disk
.IT
Boot to single user in well under one second
.IT
So fast we sometimes think it failed and returned to an Akaros shell prompt
.IT
Comparable VMMs are far larger (100 to 1000 times)
.SS "Page tables in this model: far simpler
.PS
PL: box ht 1i wid 2i "Process" "page table" "lock"
P4: box "pml4" with .w at last box.e
P3:box "pml3" at last box+(1,0)
P2:box "pml2" at last box+(1,0)
P1:box "pml1" at last box+(1,0)
P0: box "page" at last box+(1,-1)
arrow from P4.e to P3.w
arrow from P3.e to P2.w
arrow from P2.e to P1.w
arrow from P1.e to P0.w
Vl: box ht 1i wid 2i "VM" "page table" "lock" with .n at PL.s + (0,-1)
V4: box "eptl4" with .w at last box.e
V3:box "eptl3" at last box+(1,0)
V2:box "eptl2" at last box+(1,0)
V1:box "eptl1" at last box+(1,0)
arrow from V4.e to V3.w
arrow from V3.e to V2.w
arrow from V2.e to V1.w
arrow from V1.e to P0.w
.PE
.IT
two locks, one large headache
.IT 
and then the light went on
.SS "Single page table
.PS
PL: box  ht 1i wid 2i "lock"
P4: box "pml4" with .nw at last box.ne
P3:box "pml3" at last box+(1,0)
P2:box "pml2" at last box+(1,0)
P1:box "pml1" at last box+(1,0)
P0: box "page" at last box+(1,0)
arrow from P4.e to P3.w
arrow from P3.e to P2.w
arrow from P2.e to P1.w
arrow from P1.e to P0.w
V4: box "eptl4" with .n at P4.s
V3:box "eptl3" at last box+(1,0)
V2:box "eptl2" at last box+(1,0)
V1:box "eptl1" at last box+(1,0)
arrow from V4.e to V3.w
arrow from V3.e to V2.w
arrow from V2.e to V1.w
arrow from V1.e to P0.w
.PE
.IT
One lock
.IT
host and guest page tables are paired in one 8kiB "double page"
.IT
host page table is authoritative
.IT
On guest fault, walk double pages and fix faults in guest from host
.IT
page table root is loaded from "doublepage+0"
.IT
guest page table root is loaded from "doublepage+4096"
.SS "VMs as threads
.IT
VM Manager
.br
struct virtual_machine vm;
.br
static int count;
.br
int main(int argc, char **argv)
.br
{
.br
	int  attrs = 0;
.br
	vthread_attr_init(&vm, attrs);
.br
	vthread_create(&vm, 0, vmcall, NULL);
.br
	while(atomic_read(count) < 100000) {
.br
	}
.br
	return 0;
.br
}
.IT
VM thread
.br
static void vmcall(void *a)
.br
{
.br
	while (atomic_add(count, 1) < 1000000) {
.br
			__asm__ __volatile__("vmcall\n\t");
.br
	}
.br
	__asm__ __volatile__("hlt\n\t");
.br
}
.IT
Before we go into how we get this working on Plan 9 vmx, we need to describe vmx a bit
.SS "Plan 9 VMX device
.IT
/sys/src/9/pc/devvmx.c 2260 lines (Linux is 30x more code)
.IT
Open #X/clone
.IT
Set up VM with reads/writes
.IT
Run event loop
.PS
V: circle "#X/clone" "ctl,status" "regs,fpregs" "map" "wait" radius 1i 
M: circle "vmx" "thread" radius .5i at V +(-3,0)
W: circle "wait" "proc" radius .5i at M +(1.5,-3)
spline -> from W.w then left 1i then up 2i then to M.s ".vmcall ..."
spline -> from V.e then right 2i then down 3i then to W.e ".vmcall 0x0 pc 0x3 sp 0x4 ilen 0x3"
spline <-> from V.w to M.e "commands" "status"
.PE
.PS
V: circle "#X/clone" "ctl,status" "regs,fpregs" "map" "wait" radius 1i 
M: circle "vmx" "thread" radius .5i at V +(-4,0)
spline <-> from V.w to M.e "go pc=0x6;ax=42" ""
.PE
.SS "Summary
.IT
devvmx is very much a Plan 9 approach
.IT
No special daemons, file formats, binary I/O
.IT
Open files, write commands, read status
.IT
Text-oriented
.IT
Efficiency is a secondary consideration to clean design
.IT
Capable of supporting a range of kernels and guests
.IT
We will show an easy way to optimize suppporting Plan 9 guests
.IT
E.g., we can speed up basic task such as console by 700 times with very little change
.SS "Using vmx for vmthreads
.IT
Pulled several files from vmx command into libthread
.TS
c	c
l	l.
Task	Files
Implement double-pages	/sys/src/9/pc64/
	main.c,mmu.c,mem.h
Implement shared thread/VM
guest address space
add vmcall support
to vmx command	/sys/src/cmd/vmx
	ksetup.c,main.c,exith.c
Extend libthread to
include vmthreads
Not all needed	/sys/src/libthread/
	dat.h, fns.h, mem.h, x86.h
	exith.c, io.c, ksetup.c, nanosec.c, 
	virtio.c, vmx.c, vmxgdb.c, x86.c
Implement VMCALL 
support in guest (#Z)
	/sys/src/9/pc/
	devvmcall.c, vmcall.s
.TE
.SS "Double Page Support
.IT
add a 'vmproc' argument for whether to use it or not
.IT
Define VBY2PG (vmproc*BY2PG), for use in allocations (e.g. mmu.c)
.IT
	Anywhere an allocation is done, use VBY2PG instead of BY2PG
.IT
TODO: fix mmuput: if double pages, fill in EPTE entry (easy)
.IT
TODO: stop using devsegment; just use cr3+BY2PG for guest VM root (hard)
.IT
TODO: once that works, drop vm kproc; not needed (easy)
.IT
NOTE: this same technique could support dynamic page sizes, e.g., 64K superpages
.SS "vmthread implementation in libthread
.IT
First, change how memory is shared
.IT
Instead of multiple, closely sized segments
.IT
Just two: low and high
.IT
Partly because guests can read/write address zero
.IT
Partly because it is a good idea to have "safe" memory for the VMM
.IT
Low Memory (typically 16MiB) is copied, not shared; high memory is shared
.IT
Guest can call functions in the host using physical addresses
.IT
E.g., a kernel could call the process malloc
.IT
and acid could track leaks
.PS
P:box "process virtual" wid 1.6i
box invis ht .3i wid 1.6i with .s at P.n + (0,.2i)
box "2MiB-16MiB" ht .6i wid 1.6i with .s at last box.n

Q: box "16MiB-80MiB" ht .4i wid 1.6i with .s at last box.n
R:box "80MiB-96MiB" ht .4i wid 1.6i with .s at last box.n

S:box "devsegment" wid 1.6i with .w at P.e + (1,0)

T: box "0-64MiB" ht .4i wid 1.6i with .w at Q.e + (1,0)
U: box "64MiB-80MiB" ht .4i wid 1.6i with .s at last box.n

G:box "guest physical" wid 1.6i with .w at S.e + (1,0)
H: box "0-16MiB" ht .9i wid 1.6i with .s at G.n + (0,.2i)
I: box "16MiB-80MiB" ht .4i wid 1.6i with .s at last box.n

line from Q.ne to I.nw
line from Q.se to I.sw
arrow from R.e to U.w
spline -> from U.e right 3 then to H.e 
.PE
.SS "Now that it works ...
.IT
All kinds of things are possible: here is a host thread
.P1
void
watcher(void *arg)
{
	uvlong *c;

	c = arg;
	while (! *c){
		if (debug > 2) print(".%#llx.", *c);
		sleep(1000);
		yield();
	}
	threadexits(nil);
}
.P2
.SS "Guest thread
.P1
void directcall(void *arg)
{
	static int fd;	
	char *addr = "icmp!127.1!1";
	char buf[256];
	static uvlong amt;
	USED(arg);
	vmcall(print, "let's go, addr %p!\n",
	 (uvlong)addr, 0, 0);
	fd = vmcall(open, "/net/cs", 2, 0, 0);
	vmcall(print, "fd is %d\n", fd, 0, 0);
	// and more
	done = 1;
}
.P2
.IT
The VM guest is calling functions that are part of the code
.IT
Note that the functions, strings, etc. all work in the guest
.IT
Because guest physical is the same as host virtual
.IT
It is one process, and some threads are in the VM
.IT
This is a kind of super-container
.SS "so we can contain a kernel
.IT
Can continue to use standard operations that cause exit -- outb, etc.
.IT
But since kernels can call functions in the host ...
.IT
create vmcall stub function which traps to host
.IT
There are 64 bits of possible operations
.TS
c	c
l	l.
vmcall argument	meaning
<128	print the character
0x1000	dump registers and PTEs
0x2000-0x2100	call system call, assuming ring 0 thread in guest
0x1fffff	vmexit
>=1<<63	call system call, sysno is low 8 bits
>=2M	call low 32 bits of rarg with 4 args from stack (perilous!)
.TE
.IT
The print is particularly handy in assembly
.IT
MOVB $48, AX
.IT
VMCALL
.SS "devvmcall: map device ops to vmcalls
.P1
long
vmcallreadfd(ulong fd, void *a, long n, vlong off)
{
	char *err;
	void *v;
	uvlong *vec = valloc("vmcallreadfd vec",
	 8*sizeof(uvlong));
	vmdebug("vmcallreadfd fd %lud a %p n %ld off %lld\n", fd, a, n, off);
	v = valloc("vmcallreadfd", n);
	err = valloc("vmcallreadfd error", ERRMAX);
	if (waserror()) {
		bla bla
	}
	int ret = (int)vmcall(vmcallargs(vec, 
		PREAD, err, ERRMAX,
		 (uvlong)4, (uvlong)fd,
		 PADDR(v), (uvlong)n,
		 (uvlong)off));
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
	free stuff ...
	return (long)ret;
}
.P2
.IT
I picked this function because it shows that vmcalls are async (see sched())
.IT
The guest can keep going even as the host works on the read
.SS "The config file is simple
.P1
dev
	root
	cons
	swap
	arch
	env
	pipe
	proc
	mnt
	srv
	shr
	dup
	rtc
	tls
	cap
	kprof
	fs
	uart
	
	segment
	vmcall
	vmx
	dtracy

misc
	pci		pcipc
	archgeneric	devkbd
	archacpi	mp apic squidboy ec hpet
	archmp		mp apic squidboy
	mtrr

#	uartvm
	uarti8250

	dtracysys
	dtracytimer
	dtracydev

port
	int cpuserver = 0;

bootdir
	boot
	/$objtype/bin/paqfs
	/$objtype/bin/auth/factotum
	$CONF.bootfs.paq	bootfs.paq
.P2
.SS "running the command
.P1
#!/bin/rc
vmx -w text -c /fd/0,/fd/1  -M 1G 9vmpc64 'console=0'
slay vmx | rc
.P2
.SS "bootrc
.P1
fn main{
	# authentication agent
	if(! test -f /srv/factotum){
		x=(/boot/factotum -n -sfactotum)
		if(~ $service cpu)
			x=($x -S)
		if not
			x=($x -u)
		if(! ~ $#debugfactotum 0)
			x=($x -p)
		must $x
	}

	echo TRY THIS RC ps works
	bind /$v/$cputype /$cputype
	/$cputype/bin/bind /$cputype/bin /bin
	for(i in acme adm dist lib net rc sys usr dev)
		bind /$v/$i /$i
	bind -a /rc/bin /bin
	ramfs
	/bin/rc
	echo DONE THAT RC
	exit 1

}

.P2
