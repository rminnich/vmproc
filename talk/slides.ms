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
box wid 2i ht 1.3i "memory" "Registers" "Proc" with .nw at P.se +(.2i,-.1i)
K: box "Kernel" with .n at P.s + (0,-2i)
arrow "trap/syscall" "RETQ" <-> from P.s to K.n
V: box "VM" with .w at P.e + (3i,0)
L: box "Kernel" with .n at V.s + (0,-2i)
arrow "vmexit" "vmresume" <-> from V.s to L.n
box wid 2i ht 2i "Memory" "Registers" "VMCS" "Guest page table" with .nw at V.se +(.2i,-.1i)
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
Simply put, VMs can do things kernels can, with restrictions, e.g. on page tables
.IT
And even some things kernels can not do
.SS "Can VMs just do this?
.PS
K: box  wid 1i "kernel"
P: box wid 1i "process"  with .s at K.n+(0,1i)
L: box  wid 1i "kernel" "page" "tables" ht 1.5i with .w at K.e +(1, 0)
Q: box  wid 1i "process" " page" "tables" ht 1.5i with .w at P.e +(1,0)
V: box  wid 1i "VM" with .s at P.n+(0,1i)
M: box  wid 1i "memory" ht 1i with .nw at V.ne + (4i,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" "" from L.e to M.w
arrow "physical" from Q.e to M.w


arrow "guest physical" "" from V.e to M.w

.PE
.IT
If VMs could do this, protection would end
.IT
VMs must have a map from guest physical to host physical
.SS "How it really looks
.PS
K: box  wid 1i "kernel"
P: box wid 1i "process"  with .s at K.n+(0,1i)
L: box  wid 1i "kernel" "page" "tables" ht 1.5i with .w at K.e +(1, 0)
Q: box  wid 1i "process" " page" "tables" ht 1.5i with .w at P.e +(1,0)
V: box  wid 1i "VM" with .s at P.n+(0,1i)
W: box  wid 1i "VM" "external" "page" "tables" ht 1.5i with .w at V.e +(1,0)
M: box  wid 1i "memory" ht 1i with .nw at V.ne + (4i,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" "" from L.e to M.w
arrow "physical" from Q.e to M.w


arrow "guest" "" "physical" "" from V.e to W.w
arrow "physical" "" from W.e to M.w

.PE
.SS "When VM paging is enabled ...
.PS
K: box  wid 1i "kernel"
P: box wid 1i "process"  with .s at K.n+(0,1i)
L: box  wid 1i "kernel" "page" "tables" ht 1.5i with .w at K.e +(1, 0)
Q: box  wid 1i "process" " page" "tables" ht 1.5i with .w at P.e +(1,0)
V: box  wid 1i "VM" with .s at P.n+(0,1i)
W: box wid 1i "VM" "page" "table" ht 1.5i with .w at V.e +(1,0)
X: box  wid 1i "VM" "external" "page" "tables" ht 1.5i with .w at W.e +(1,0)
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
There are page tables in the VM
.IT
and outside the vm
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
.SS "Problems with Linux model
.IT
Virtual machine is a distinct device
.IT
Communicates with host via IO/memory operations
.IT
Every distinct device type requires another emulator (which is why QEMU STILL has NE2000 support)
.IT
Which must be intercepted and interpreted
.IT
Or, must implement IOSRV / IOMMU, which gets very complex
.PS
V: box wid 3i "KVM/Beehive device"
P: box wid 2i "Process" with .e at V.w+(-1,0)
K: box wid 1i "Kernel" with .n at P.s+(0,-2)
N: box wid 1i "network"
U: box wid 1i "uart"
D: box wid 1i "disk"
G: box wid 1i "graphics"
B: box wid 1i "USB"
arrow "ioctl" from P.s to K.n
arrow "bit twiddling" from K.n to V.s
arrow from N.n to V.s
arrow from U.n to V.s
arrow from D.n to V.s
arrow from G.n to V.s
arrow from B.n to V.s
.PE
.SS "Linux/BSD Virtual Machine model
.IT
First, what's a VM?
.IT
Is it an instance of opening a device in /dev?
.IT
No: that's one way of implementing VMs
.IT
How do VMs fit into the Akaros model?
.IT
We decided to take nothing for granted
.IT
A look back is useful
.IT
A VM could be kind of a process
.IT
How did we used to start processes?
.SS "Start a job: IBM
.IT
//CONCATEX JOB CLASS=6,NOTIFY=&SYSUID
.IT
//* Example 1:
.IT
//STEP10 EXEC PGM=MYPROG
.IT
//IN1    DD DSN=SAMPLE.INPUT1,DISP=SHR
.IT
//OUT1   DD DSN=SAMPLE.OUTPUT1,DISP=(,CATLG,DELETE),
.IT
//       LRECL=50,RECFM=FB
.IT
//SYSIN  DD *
.IT
//CUST1  1000
.IT
//CUST2  1001
.SS "On newer mainframes
.IT
 <devices>
.IT
    <redirdev bus='usb' type='tcp'>
.IT
      <source mode='connect' host='localhost' service='4000'/>
.IT
      <boot order='1'/>
.IT
    </redirdev>
.IT
    <redirfilter>
.IT
      <usbdev class='0x08' vendor='0x1234' product='0xbeef' version='2.56'allow='yes'/>
.IT
      <usbdev allow='no'/>
.IT
    </redirfilter>
.IT
  </devices>
.SS "On Unix, in 1972
.IT
fork();
.IT
Starting a process was ugly before this
.IT
Unix made it easy and clean
.IT
It was also controversial because it encouraged people to use it
.IT
I.e. that one could, in DMR's words, be “profligate” with processes
.IT
Forking a process to list files was considered ridiculous in many places
.SS "Virtualization today
.IT
Remember that “newer mainframes” slide?
.IT
That's from libvirt on Linux
.IT
It's a tiny fraction of the total giant pile of XML for one VM
.IT
Far more complex than the 1970s mainframe JCL example!
.IT
To start a virtual machine on linux requires
.IT
Daemons
.IT
Special user ids
.IT
Batch scheduling
.IT
Gigantic XML files
.IT
Mountains of code
.IT
We've recreated batch systems from mainframes for VMs!
.IT
What's going on here?
.SS "Virtualization model
For Akaros, we did not want anything like Linux/BSD approach
.IT
We ported five different VMs to Akaros while evaluating them
.IT
Gvisor, KVM, Dune, Bhyve, two others you never heard of
.IT
Then, one day, during a discussion, I noticed something
.SS "How VM page tables are done
.PS
PL: box ht 1i wid 2i "Page" "table" "lock"
P4: box "pml4" with .w at last box.e
P3:box "pml3" at last box+(1,0)
P2:box "pml2" at last box+(1,0)
P1:box "pml1" at last box+(1,0)
P0: box "page" at last box+(1,-1)
arrow from P4.e to P3.w
arrow from P3.e to P2.w
arrow from P2.e to P1.w
arrow from P1.e to P0.w
Vl: box ht 1i wid 2i "Virtual" "page table" "lock" with .n at PL.s + (0,-1)
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
.SS "And from there
.IT
If the page tables are shared that way, what's the difference between a VM and Ring 3?
.IT
nothing more than RETQ vs VMRESUME
.IT
as long as you have the state set up, you can return to either one
.IT
Even better, you can jump back and forth!
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
.SS "Bringing this model to Plan 9
.TS
c	c
l	l.
Task	Files	Status
Implement double-pages	/sys/src/9/pc64/
	main.c,mmu.c,mem.h
Implement shared thread/VM
guest address space
add vmcall support
to vmx command	/sys/src/cmd/vmx
	ksetup.c,main.c
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
.PP "Double Page Support
.IT

