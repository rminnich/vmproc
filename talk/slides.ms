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

.SS "VMs as threads
.IT
Until now, VMs have been treated as devices
e.g. /dev/kvm, /dev/vmx, whatever
.IT
Leads to really awkward abstraction
.IT
Makes a local resource (a core) look like a remote batch device
.IT
On Akaros, we developed a new model
.IT
VM is just a thread in a new protection ring -- Ring V
.IT
Kernel exits to Ring 3 (User Mode) or Ring V (VM)
.SS "Get the abstraction right and all else follows
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
.SS "Akaros
.IT
Research kernel from Berkeley
.IT
In 2013, we ported significant bits of Plan 9 to Akaros, largely automated, using INRIA Coccinelle
.IT
TCP stack, name spaces, drivers, ...
.IT
This gave us a mature code base, particularly for TCP
.IT
To some extent, what we learned with Akaros virtualization can come back to Plan 9
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
.SS "Virtual machines on Linux/BSD (but not OSX!)
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
.SS "Start process: HP MPE
.IT
Using CREATEPROCESS
.IT
Your program can call the CREATEPROCESS intrinsic to create a child
process.  Your program can control the creation of the child process with
the optional parameters itemnums and items.  The information you can pass
to MPE XL through itemnums/items parameter pairs include:
.IT
The names of the files to be used as $STDIN and $STDLIST for the child process.
.IT
An option that indicates if the child process is to be activated
immediately after it is created, and if the parent process should be
suspended automatically when the child process is activated.
.IT
A list of user-named executable libraries to be searched at load time
for required external references.
.IT
A user-created UNSAT procedure, to which all unsatisfied load-time
external references may be directed.

.SS "This is an example of a CREATEPROCESS intrinsic call:      .
.IT
ERRORCODE := 0;
.IT
	PIN := 0;
.IT
     BNAME := 'MYPROG.PUB.MYACCT';
.IT
     ITEMNUMS[1] := 3;
.IT
     ITEMNUMS[2] := 0;
.IT
     ITEMS[1] := 1;
.IT
     CREATEPROCESS (ERRORCODE,PIN,BNAME,ITEMNUMS,ITEMS);
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
.SS "Start a job on CDC
.IT
   /JOB
.IT
   COPYBR,INPUT,INPUT1.
.IT
   COPYBR,INPUT,INPUT2.
.IT
   REWIND,INPUT1,INPUT2.
.IT
   * RUN CHECKPOINT JOB
.IT
   LINK1,INPUT1,OUTPUT,PUNCH1,UT1.
.IT
   * MANIPULATE FILES
.IT
   PACK,PUNCH1.
.IT
   REWIND,PUNCH1.
.IT
   RETURN,POOL.
.IT
   RENAME,OPTP=NPTP.
.IT
 * RUN RESTART JOB
.IT
   LINK1,INPUT2,OUTPUT,PUNCH2,UT1.
.IT
   /EOR
.IT
   NASTRAN FILES=NPTP
.IT
    . (Data for Checkpoint Job)
.IT
   /EOR
.IT
NASTRAN FILES=OPTP
.IT
   CEND
.IT
    Please make it stop
.IT
    . (Data for Restart Job)
.IT
   /EOF
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
.IT
Virtualization on Linux/BSD/Unix requires a device
.IT
Was not possible to go deeper, i.e. rework task and vm structures (politics)
.IT
Device access requires privileges (usually root)
.IT
But simple setuid approaches are dangerous
.IT
So we have daemons we talk to to do it for us
.IT
For Akaros, we did not want anything like Linux/BSD approach
.IT
We ported several different VMs to Akaros while evaluating them
.IT
Gvisor, KVM, Dune, Bhyve, two others you never heard of
.IT
We did not have restrictions on how much we could change
.IT
We did not want to recreate a batch system for VMs
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
On guest faulk, walk double pages and fix faults in guest from host
.IT
page table root is loaded from "doublepage+0"
.IT
guest page table root is loaded from "doublepage+4096"
.SS "And from there
.IT
If the page tables are shared that way, what's the difference between a VM and Ring 3?
.IT
nothing more than SRET vs VMRET
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
.SS "In Akaros, VMs are threads
.IT
Recap:
.IT
Akaros processes and threads are somewhat different than you're used to
.IT
Akaros schedules sets of cores (1 or more), not processes
.IT
And schedules entities called ‘multi core processes' onto those cores
.IT
Threads are scheduled at user level onto cores
.IT
We have extended the thread model to include Virtual Machine Threads
.IT
Virtual Machine Threads (vthreads) can run:
.IT
Linux 4.8 (with 12 lines of patches so that we can tell it clock rates via
.IT
cmdline)
.IT
Any code that shares the Host Ring 3 address space (equivalent to Guest
.IT
Ring 0)
.IT
Gvisor
.IT
.SS "
.IT
VMs and threads as part of an MCP
.IT
Ring V
.IT
Kernel (Ring 0)
.IT
Ring 3
.IT
Ring V
.IT
Ring 3
.IT
Ring V
.IT
Ring 3
.IT
Ring V
.IT
Ring 3
.IT
Ring V
.IT
Ring 3
.IT
Single Akaros Process, which owns cores, and runs threads. Some threads run
.IT
in Ring 3 (normal user mode) and some run in Ring V (VMX mode). They can
.IT
flip modes, i.e., a thread can alternate between Ring 3 and Ring V.  They
.IT
share an address space, and can communicate through memory or virtio.
.IT
.SS "Process address space (x86)
.IT
Ring 3 and Ring V share an address space
.IT
Ring V is limited to 2^46 bytes
.IT
If we are concerned about what's in the VM we can use this limit
.IT
Run VMM starting at 2^46
.IT
Only leave stuff in the “low” memory that is for the guest
.IT
Currently due to gcc limits we also enforce only Ring 3 can access to low
.IT
16 MiB (save for first 1 MiB -- 8086 XXX)
.IT
Ring 3 address space -- 2^47 bytes
.IT
Ring V address space -- enforced to a measly 2^46 bytes
.IT
Forbidden to VMs
.IT
Shared between Ring 3 and Ring V
.IT
Here is first riscv question
.IT
.SS "We integrate VM Threads tightly into the kernel
.IT
Paging
.IT
Page table pages become double-wide (x86-specific, more on this later)
.IT
Entering the kernel
.IT
Previously, there's only IRQs, Traps, SYSENTER/SYSCALL
.IT
Added a handler for VMEXIT, treat it like a fault
.IT
Return to user, whether VM or Ring 3
.IT
OS knew how to run a “context” for IRQs/Traps or SYSENTER
.IT
Added a handler to run a “VM context”
.IT
No arch-independent changes to scheduler or process management code
.IT
Added a user-level scheduler for VMs
.IT
Application specific scheduling, where the application is a VMM
.IT
454 lines
.IT
.SS "Paging in Linux for virtual machines
.IT
PML4
.IT
PML3
.IT
PML2
.IT
PML1
.IT
Process root (cr3)
.IT
EPT4
.IT
EPT3
.IT
EPT2
.IT
EPT1
.IT
Guest root
.IT
(EPT root)
.IT
Independent structures with their own locks, traversal functions,
.IT
allocators, and theme parks …
.IT
.SS "
.IT
.SS "Akaros paging on x86
.IT
PML4
.IT
PML3
.IT
PML2
.IT
PML1
.IT
Process root (cr3)
.IT
EPT4
.IT
EPT3
.IT
EPT2
.IT
EPT1
.IT
Guest root
.IT
(EPT root)
.IT
Page table roots are paired, as are page table pages (PTP)
.IT
PTP are 2 * 4K pages
.IT
Process PTP is lower (“even”) 4k
.IT
VM PTP is upper (“odd”) 4k
.IT
Lower half is for thread in Ring 3
.IT
Upper half is for thread in Ring V
.IT
Threads can jump back and forth between those modes
.IT
VMM/VM duality
.IT
Code for VM page fault and process page fault is the same code
.IT
Can always see PTP for VM given a process, or process given a VM
.IT
EPT fault looks like a normal page fault, ugly details buried in HAL (not
.IT
much code)
.IT
.SS "Entering kernel from ring 3/ring V
.IT
The basic API is the same in each case
.IT
And utterly different from, say, /dev/kvm
.IT
In KVM, vmexit is the return value of an ioctl to start a vm
.IT
VMM is responsible for resolving the problem, changing VM state
.IT
In Akaros, vmexit is like any other case where ring 3 drops to ring 0 for
.IT
services
.IT
Ring 3: traps, system call, page fault
.IT
vmexits: vmcall, EPT fault, MSR access, IO, etc
.IT
Same style of handling in the kernel for vmexits as faults:
.IT
Kernel tries to resolve the fault without blocking (e.g. page fault, lookup
.IT
in page cache)
.IT
If the kernel fails, the faulting context is reflected to the user-level
.IT
scheduler (2LS)
.IT
For userspace, a VM fault is just another reflected fault
.IT
.SS "
.IT
Running a ring 3 / ring V context
.IT
Akaros has three context types:
.IT
Hardware - involuntarily created during a trap/interrupt.  Think “every
.IT
register”
.IT
Software - voluntarily created during syscalls and user-level threading.
.IT
Think “AMD SYSV ABI”
.IT
VM - involuntarily created during vmexit.  Think “every register”, plus
.IT
exit info and guest_pcoreid
.IT
Returning to userspace (Ring 3 or Ring V) is always the same: proc_pop_ctx()
.IT
Whether or not we return to a VM or not is solely dependent on the type of
.IT
context
.IT
The kernel does maintain, per process, an array of guest physical cores
.IT
Various x86 accounting not related to the running context
.IT
VMCS, certain MSRs (STAR, LSTAR, SFMASK, KERNEL_GS_BASE), other fun stuff
.IT
Userspace knows how to run contexts too!
.IT
Simply build the context as part of a struct uthread and try to run it
.IT
But on x86, it asks the kernel to run VM contexts, since vmlaunch /
.IT
vmresume is privileged
.IT
.SS "Limitations
.IT
64-bit only
.IT
Very limited 16-bit and IO emulation
.IT
It's dumb and fragile, deliberately
.IT
Because even vendors sometimes get it wrong: “After analyzing the problem,
.IT
it's now clear what's happening. As incredible as it is, Ryzen has buggy
.IT
VME implementation; specifically, the INT” --
.IT
http://www.os2museum.com/wp/vme-broken-on-amd-ryzen/
.IT
But there is some … essential for some ops and physical page 0 support
.IT
Paravirt only: for now the 10x boost for virtio devices is worth it
.IT
.SS "Hardware assumptions
.IT
We're not supporting any pre-2012 hardware
.IT
Old hardware support in, e.g., KVM makes it messy, as does their
.IT
evolutionary approach
.IT
X2APIC (and hence IOMMU)
.IT
There are three flavors of APIC virtualization and we use the one that works
.IT
That was fun … since you have to enable all three to make the good one work
.IT
Require ability to support vmexit-free interrupt injection
.IT
Add additional pages to VMCS
.IT
Fun: VMCS has a size field which I'm willing to bet will always be “4k”
.IT
So they have to add pointers to the VMCS to point to other pages
.IT
The big goal is zero vmexits
.IT
.SS "Reducing VMExits
.IT
VMExits are costly.
.IT
399 nsec per loop in kernel without vmcs unload
.IT
930 nsec per loop in kernel with vmcs unload
.IT
1766 nsec per loop to userspace without vmcs unload
.IT
Some sources of VMExits:
.IT
Device interrupts
.IT
Inter-Processor Interrupts (IPIs)
.IT
IO
.IT
Faults
.IT
.SS "Intel VM interrupts
.IT
Virtualize APIC accesses VS APIC-register Virtualization: not the same
.IT
thing.
.IT
Posted Interrupts
.IT
Allows for injection of interrupts into the guest without exiting
.IT
Requires at least EOI virtualization to not exit
.IT
Host sets a bit corresponding to the target vector in the PIR page, and
.IT
sends the Posted-interrupt notification vector as an IPI
.IT
Fun fact
.IT
The “process posted interrupts” VM-execution control requires the
.IT
“external-interrupt exiting” VM-execution control
.IT
.SS "Example: Local APIC Timer
.IT
Guest OS
.IT
MSR exit handler
.IT
MSR write to Timer Vector, Initial Count, Divide configuration register
.IT
causes exit
.IT
Timer Thread
.IT
If all required variables have been initialized:
.IT
Start a timer thread that sleeps for required time
.IT
Guest Core resumes execution after handler completes.
.IT
Core 0
.IT
Core 1
.IT
Set vector bit in PIR page and send IPI to Core 0
.IT
.SS "SMP Guest Startup
.IT
.SS "
.IT
.SS "Virtual Machine AP core startup
.IT
/* Start up secondary core. */
.IT
vm_tf_ap = gth_to_vmtf(vm->gths[cur_pcores]);
.IT
.SS "/* Set CR3 */
.IT
vm_tf_ap->tf_cr3 = vm_tf->tf_cr3;
.IT
.SS "/* Starting RIP is passed in via rdi. */
.IT
vm_tf_ap->tf_rip = vm_tf->tf_rdi;
.IT
.SS "/* Starting RSP is passed in via rsi. */
.IT
vm_tf_ap->tf_rsp = vm_tf->tf_rsi;
.IT
.SS "vm->up_gpcs++;
.IT
.SS "start_guest_thread(vm->gths[cur_pcores]);
.IT
.SS "
.IT
.SS "VMCALL smpboot handler
.IT
/* AKAROS VMCALL SMP */
.IT
__asm__  __volatile__(
.IT
"movq $2, %%rax\n”
.IT
“movq $secondary_startup_64, %%rdi\n”
.IT
“movq %0, %%rsi\n”
.IT
“vmcall\n"
.IT
:  : "m"(stack_start)  : "rax", "rdi", "rsi");
.IT
.SS "
.IT
.SS "
.IT
Summary
.IT
Akaros VMs are unlike any other VMs
.IT
Threads can easily switch from being a VM to being a host thread
.IT
We invented a new user mode, Ring V
.IT
A VM is a thread in Ring V
.IT
When a VM Thread is in Ring V, it can run as Guest Ring 0 or Guest Ring 3
.IT
Can manage its own page tables, interrupt tables, etc.
.IT
Shares memory with Host Ring 3 - easy virtio communication via shared mem!
.IT
In most ways, thread programming models can be used
.IT
Kernels also look like threads and spinning up a core looks like CPU
.IT
hotplug, accomplished by spinning up a vthread with IP at the 64-bit entry
.IT
point
.IT
.SS "Summary
.IT
Akaros VMs are nothing like existing kernels
.IT
We were able to tightly integrate VMs into process model
.IT
It's not a configuration option
.IT
Did not need to add it as a device
.IT
.SS "go/akaros-vmm
.IT
.SS "
.IT
Big picture -- example for 5 threads
.IT
Threads can see thread and VM memory
.IT
VMs only see their own memory
.IT
VMs have a Linux kernel and a single app (potentially containing many
.IT
processes)
.IT
VM
.IT
Thread
.IT
VM
.IT
VM
.IT
Thread
.IT
VM
.IT
VM
.IT
Thread
.IT
.SS "Question: can we create two barriers
.IT
.SS "Security barriers: One
.IT
Process virtual memory -- all guest requests are handled here, not in
.IT
kernel.
.IT
Addresses unavailable to the guest -- hardware limitation
.IT
Guest physical memory
.IT
Process virtual memory used only for the guest
.IT
“EPT” range
.IT
(2^46)
.IT
Memory above “EPT” range (2^53-2^46)
.SS "VM virtual memory
.PS
K: box "kernel"
P: box "process" with .s at K.n+(0,.2)
L: box "kernel" "page" "tables" with .w at K.e +(.6, 0)
Q: box "process" " page" "tables" with .w at P.e +(.6,0)
M: box "memory" ht 1i with .sw at L.se + (1,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" "" from L.e to M.w
arrow "physical" "" from Q.e to M.w

.PE
