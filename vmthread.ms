.HTML "VMThreds: virtual machines as threads in libthread"
.TL
VMThreads: virtual machines as threads\(dg
.FS
\(dgLicense: CC-BY-ND-SA
.FE
.AU
Ron Minnich
.sp
rminnich@gmail.com
.rm CH
.nr % 0
.de PF
..
.AB
We describe a new Virtual Machine model, VMThreads, for Plan 9, which allows Virtual Machines to be integrated into a 
program as threads.
Creating a Virtual Machine is as easy as creating a thread; the 
function call signature is identical to 
.I threadcreate(2).
Currently,
VMThreads requires no kernel changes.
.LP
Traditional virtualization systems are designed to run heavyweight guest OS images, usually a 
Linux or Windows distribution, including a disk image.
Their disk activity is visible only as a set of IO operations on a virtual disk, not 
operations on a file system.
Guest VMs are frequently accessed over an emulated network connection, as though they
were an entirely independent system.
.LP
In contrast, VMThreads allows users to run virtual machines of any size, even a single
machine instruction\(dd;
.FS
\(ddFor example, we used a single-instruction VM guest to debug our vmcall support.
.FE 
a function; a set of functions comprising a driver; or a kernel.
Because the guest VM is created as a thread, it is easy to share data structures with it.
Threads outside the VM thread can examine and control the guest behavior, allowing
a level of debugging that might otherwise require hardware support.
Because the VM is visible to the kernel as a process, standard process management
tools can be used to study its behavior. 
Further, it is possible to implement a driver-less kernel, i.e. one which uses system
calls, not low-level IO operations, and monitor the VM's use
of network, disk, and other resources 
directly, rather than trying to reconstruct its activity from its use of emulated
devices. We discuss the implementation of this model via the #Z device, which maps
driver IO functions to system calls, communicated from guest to host via vmcall
instructions. We have added this device support to the 9front vmx command.
.LP
While the VMs-as-threads model is very simple, it is as capable as more complex systems:
we first implemented VMThreads in the Akaros research kernel, and
showed that it could support the Google production kernel stack as a guest. 
.LP
We discuss the implementation of this model on the 9front release of Plan 9. 
While the implementation is not quite as complete as the Akaros version, 
it requires no kernel changes. 
.AE
.SH
Introduction
.LP
Virtualization is a hardware capability that allows privileged code to run in a less-privileged context, i.e. a virtual machine (VM).
VMs do not stand alone; they require a Virtual Machine Monitor (VMM), also known as a hypervisor, to start them,
provide services such as IO to them and, as needed, shut them down.
Virtualization, once limited to the exotic domain of IBM mainframes,  
is ubiquitous on commodity client and server systems, running on everything from phones to cloud servers.
Chip vendors have made significant changes over the last 20 years to make virtualization efficient.
A guest VM, as measured on cloud servers, can achieve about 91% of the throughput of running on host; 
in some cases, it can even run faster.
.LP
On almost all modern operating systems, virtual machines (VMs) are supported by hardware,  with low level control provided  by kernels, and presented to VMMs,
as a device. 
VMMs open a device, and operate on it as they would any other real device, such as a network card. 
.LP
While virtualization is common, and several VMMs are in wide use, 
writing a VMM is difficult. 
The device model provided by most kernels (e.g. Linux) is tricky and easy to get wrong, with 
difficult to understand failures. 
This interface is difficult enough that,
17 years after virtualization came to Linux, there are only a handful of commonly used VMMs.
The API is also broad:
virtualization software for, e.g., Linux, is considered compact if it only requires a few thousands of lines of code to run. 
Virtual Machine Managers (VMMs) can be very large, with a memory footprint of 10 MiB to 500 MiB. 
.LP
In this paper we introduce 
.I VMThreads,
a virtualization model which we have incorporated into the Plan 9 thread library. 
VMThreads, as the name implies, allows users to create and run VMs as a thread in a process.
For example, this code starts an infinite loop as a VM thread, running in guest ring 0 on an x86.
.P1
u8int brdot[] = {0xeb, 0xfe}; // infinite loop: 1: jmp 1b
// start vmthread at brdot; no argument; 1024 byte stack.
vmthreadcreate((void *)brdot, nil, 1024); 
.P2
The API is identical to the threadcreate API from libthread.
.LP
The rest of this paper is organized as follows: we provide an overview of virtualization; describe
the Akaros vmthread virtualization model which inspired this work; discuss the implementation of this model in Plan 9
.I libthread,
and show examples of its use.
We also discuss an extension of the 9front vmx command, and a new kernel device, which 
maps guest device operations such as walk, open, read, and write, to system calls, communicated
to the host via the vmcall instruction. 
.SH
Virtualization
.LP
Virtualization allows privileged software to run in an unprivileged context, a.k.a., a guest, under control of a host. 
Virtualization provides services required by applications, 
that might not be provided by the host (.e.g Linux running as a guest on OSX); 
and a security boundary for the the host, protecting it from the guest. 
Virtualization has been available since the 1960s on IBM mainframes. 
.LP
Until the release of VMWare several decades ago, virtualization
had been almost ignored in non-mainframe operations. 
Since then, however virtualization has become very widely used, and even taken for granted, on a wide range of systems, 
including inexpensive laptops such as Chromebooks, up to and including the largest cloud servers. 
.LP
Once virtualization became more popular, users  wished for
an alternative to proprietary virtualization 
software. 
Xen was an early open source virtualization system for commodity x86 systems, 
and was widely deployed on Amazon Web Services. 
.LP
Xen is a kernel which runs other kernels as a VM guest, i.e. "Domains", with one kernel ("Domain 0")
being given special privileges to perform IO, since Xen has no drivers
of its own. 
Xen is always the host, and kernels are always the guest. In Xen, every kernel runs
at a lower privilege level than the Xen kernel. 
.LP
Following close on the heels of Xen came other systems; Linux KVM (Kernel Virtual Machine) is probably the most widely used\(dg. 
.FS
\(dgThere are at last count eight different VMs available on Linux; one for the BSD kernels; one for Darwin; and one for Plan 9.
.FE
Unlike Xen, 
KVM  VMs run as a driver in Linux.
In this model, a single general purpose host kernel is more 
privileged than the virtual machine software, which in turn is more privileged than any VM guest. 
The driver manages architectural features that enable and control virtualization. 
.LP
Xen and KVM are structurally very different systems. 
The arguments over classifying these types of VMs may never end, but, commonly, Xen is called a Type 1 hypervisor, as it is in itself a kernel
above all other kernels; and KVM,the BSD VMs, the OSX and Plan 9 VMs;  are called a Type 2, as they are contained
in a general purpose kernel. For the rest of this paper, we restrict the discussion to Type 2 kernels. When we use the term VM, we are 
discussing a Type 2 VM.
.SH
Virtual Machine Memory addressing
.LP
In this section we review some basics of VM virtual address spaces.
VMs, on x86, can run in 16-, 32-, and 64-bit modes. In 16- and 32-bit modes, virtual addressing
is optional. In 64-bit mode, it is mandatory, as required by the architecture.
Recall that virtual addressing is enabled by page tables, as shown below.
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
One might wonder: when a VM is in 16- or 32-bit mode, without virtual addressing enabled, 
can it transparently reference physical
memory, as host software in those modes can?
Does the picture look like the one below?
.PS
K: box "kernel"
P: box "process" with .s at K.n+(0,.2)
L: box "kernel" "page" "tables" with .w at K.e +(.6, 0)
Q: box "process" " page" "tables" with .w at P.e +(.6,0)
V: box "VM" with .s at P.n+(0,.2)
M: box "memory" ht 1i with .nw at V.ne + (2,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" "" from L.e to M.w
arrow "physical" from Q.e to M.w


arrow "guest physical" "" from V.e to M.w

.PE
The answer, as you might guess, is "no".
Were VMs to work that way, there would be no security at all. 
Instead, there is a page-table-like structure that maps guest physical addresses to host physical
addresses. On Intel, this is called the EPT.
.PS
K: box "kernel"
P: box "process" with .s at K.n+(0,.2)
L: box "kernel" "page" "tables" with .w at K.e +(.6, 0)
Q: box "process" " page" "tables" with .w at P.e +(.6,0)
M: box "memory" ht 2i with .sw at L.se + (1,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" from L.e to M.w
arrow "physical" from Q.e to M.w

V: box "VM" with .s at P.n+(0,.2)
W: box "Extended" " page" "tables" with .w at V.e +(.6,0)
arrow "guest" "physical" from V.e to W.w
arrow "host" "physical" from W.e to M.w
.PE
What is shown will work for any 16- or 32-bit code that does not enable
virtual addressing. It will not work for 64-bit mode; that requires
virtual addressing to be enabled. Further, no 16-bit process can run with
paging enabled. The result is that there are at least 5 possible ways to run a guest.
.LP
In this paper, we are only concerned with a 64-bit guest, with virtual addressing enabled.
We show what that looks like below.
.PS
K: box "kernel"
P: box "process" with .s at K.n+(0,.2)
L: box "kernel" "page" "tables" with .w at K.e +(.5, 0)
Q: box "process" " page" "tables" with .w at P.e +(.6,0)
M: box "memory" ht 2i with .sw at L.se + (1.4,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" "" from P.e to Q.w
arrow "physical" from L.e to M.w
arrow "physical" from Q.e to M.w

V: box "VM" with .s at P.n+(-.7,.2)
X: box "VM" "page" "tables" with .w at V.e + (.6,0)
W: box "Extended" " page" "tables" with .w at X.e +(.6,0)
arrow "guest" "virtual" from V.e to X.w
arrow "guest" "physical" from X.e to W.w
arrow "host" "physical" from W.e to M.w
.PE
That may look like a lot of table walking. In fact, it is worse than it appears. 
Every guest page table walk resolves to a guest physical address.
That guest physical address must, in turn, be translated to a host physical address. 
The process is shown below.
For the guest page table, we show the page table levels as Page Map Level (PML), 
ranging from 4 to 1, since PML0 is the
guest physical page address. 
For the guest physical to host physical, we show Extended Page Table (EPT),
as levels 4 to 1, where EPT0 is the host physical page address. 
.PS

F: box "guest" "PML4"
box "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
M: box "Memory" ht 1.5i with .nw at last box.ne + (.4,0)
arrow from 2nd last box.e to M.w +(0,.1)

G:box "guest" "PML3" with .n at F.s - (0,.1)
spline -> from M.e + (0,.1) right .4 then down 3 then left 6.4 then up 2 then to G.w
box "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow from last box.e to M.w 

H:box "guest" "PML3" with .n at G.s - (0,.1)
spline -> from M.e right .3 then down 2.7 then left 6.2 then up 1.5 then to H.w
box "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow from last box.e to M.w +(0,-.1)

I:box "guest" "PML2" with .n at H.s - (0,.1)
spline  -> from M.e + (0,-.1) right .2 then down 2.4 then left 6 then up 1 then to I.w
box "EPT" "L4" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L3" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L2" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
box "EPT" "L1" with .w at last box.e + (.2,0)
arrow from 2nd last box.e to last box.w 
arrow "physical" "" "address" from last box.e to M.s +(0,-.55) then to M.s

.PE

.SH
Virtual Machine managers
.LP
Running a VM guest requires two software components: the VM code in the kernel; and a so-called
Virtual Machine Manager (VMM).
The VMM is a program that directs the kernel to
load, run, and manage a guest. As the guest VM runs, 
it will exit with error codes, interrupts,
or when the guest requests services;  
these VM exits are 
managed by the VMM. 
The VMM can be called upon to emulate some instructions; handle timer interrupts; or manage faults.
The VMM determines if the VM exit can not be handled, meaning the VM must
end; or the VM can be resumed. During the lifetime of a typical VM, millions
of VM exits are processed and millions of VM resumes are issued by the VMM.
.LP
VMMs can be very complex, and, consequently, can be very large. 
We know of one proprietary VMM which is a 500 MiB binary; 
at the same time, a basic Linux VMM, written in C, can be as small as a megabyte. 
Typically, smaller 
VMMs can not handle widely varying demands of guests; the larger VMMs have support for more complicated operations, e.g., 
BIOS interrupts needed for DOS.
A common open source VMM is qemu, but there are a few others, e.g. the KVMTool, CrosVM, Cloud Hypervisor, and GoKVM tools for Linux. 
.LP
With few exeptions, the VM API is built around a device model, frequently
requiring special privilege to access. 
VMMs 
open the VM device and use a file descriptor to control it. 
The separateness of the device is always apparent. The abstraction
is complicated and not convenient.
.SH
Akaros virtualization: VMs as threads\(dg
.FS
\(dghttps://github.com/brho/akaros. See the patches starting at ddb9fa78b5d97e4107a9404f4146140ef8bf9a5a from 
April 1, 2015 and on (yes, April Fool's day!).
.FE
.LP
As part of our Akaros research at Google, we developed an entirely
new VM model, by adding a new program protection level called Ring V.
Ring V is almost identical to the X86 Ring 3, a.k.a user mode, save that it is a VM.
When the Akaros kernel exits Ring 0 (kernel) to the program, it
checks a flag in
the process structure and either does
a traditional exit to Ring 3, using the saved trap context and RETI (return from interrupt) instruction;
or to Ring V, using the VM Control Structure (VMCS) context and a VMRESUME instruction.  
Akaros can decide, each time it resumes a process, whether to resume it in Ring 3 or Ring V. 
Processes can flip back and forth between the two modes at will. 
.LP
Akaros takes the model one step further: the guest physical address space is the same as process virtual address space, as shown below:
.PS
K: box "kernel"
P: box "process" with .s at K.n+(0,.2)
L: box "kernel" "page" "tables" with .w at K.e +(.6, 0)
Q: box "process" " page" "tables" ht .6i with .sw at P.se +(.6,0)
M: box "memory" ht 2i with .sw at L.se + (1,0)
arrow "virtual" "" from K.e to L.w
arrow "virtual" ""  from P.e to Q.w
arrow "physical" from L.e to M.w
arrow "physical" from Q.e to M.w

V: box "VM" with .s at P.n+(-1.5,.2)
X: box "VM" "page" "tables" with .w at V.e + (.6,0)
W: box "Extended" " page" "tables" ht .6i with .s at Q.n
arrow "guest" "virtual" from V.e to X.w
arrow "guest" "physical" from X.e to W.w
arrow "host" "physical" from W.e to M.w
.PE
A VMM can start a kernel by reading the kernel file into memory and 
starting a vmthread with the kernel entry point as the initial program counter (PC). 
VMMs can even run user programs in Guest Ring 0, i.e. as kernels. 
One use of a Guest Ring 0 program would be a device driver, which could safely
contain the device I/O in the VM. 
.LP
How do VMThreads look in practice? 
Shown below is a function that runs in the guest. It is called
thread_entry, and is part of a single file containing both
the VMM and the guest code. They can be compiled into one unit
because the guest physical addresses and the host virtual addresses
are the same; in fact, the guest physical memory is provided
directly from the host virtual memory.
This code also shows the use of 
.I vmcall,
an instruction which allows a guest to request system-call like operations on the host.
.LP 
.P1
static void thread_entry(void *arg)
{
	const char nums[] = "123456789";

	for (int i = 0; i < sizeof(nums); i++)
		vmcall(VTH_VMCALL_PRINTC, nums[i]);
	vmcall(MY_VMCALL_TEST1);
	vmcall(VTH_VMCALL_EXIT, arg, 0, 0, 0);
}
.P2
The function prints out several numbers, via vmcall, which exits the 
guest, and resumes in the host program vmcall handler. 
The parameters to vmcall are placed in registers, by the compiler, following
the 64-bit x86 calling convention. 
There are two standard vmcalls used in this example:
VTH_VMCALL_PRINTC and VTH_VMCALL_EXIT; VTH_VMCALL_TEST1 is a custom 
vmcall implemented in this same program.
.LP
Below we show a VMM that runs this function. 
This example runs 5 VMs simultaneously, i.e. on 5 cores.
This is a multi-threaded program running several VMs on several cores at once. 
It is the
technique we use to start a multiprocessor kernel such as Linux: 
each Linux core (VM guest) is a thread in the host.
.P1
int main(int argc, char **argv)
{
	#define NR_VTHS 5
	struct vthread *vths[NR_VTHS];
	void *retvals[NR_VTHS];

	/* Tests multiple threads at once */
	for (long i = 0; i < NR_VTHS; i++)
		vths[i] = vthread_create(&vm, thread_entry, (void*)i);
	for (long i = 0; i < NR_VTHS; i++) {
		vthread_join(vths[i], &retvals[i]);
		assert(retvals[i] == (void*)i);
	}

	return 0;
}
.P2
To reiterate, all the code we are showing is in the same file: the VMM and the guest "kernel" are 
compiled in one file, one time.
in this case, it creates 5 threads with vthread_create, using 
thread_entry as the function to activate. 
It then performs a vthread_join. Each of the threads, when it
exits with VTH_VMCALL_EXIT, will complete the join.
.LP
This API is designed to be familiar to pthreads users. There is
one compilation unit; all data and code share an address space; 
it uses a fork/join model. The only difference is that all the threads run in a VM.
Threads can call host functions with the vmcall. Interestingly enough, 
since the address space is shared, threads can call libc functions to format
strings, and then print them with the vmcall.
.SH
Moving this model to 9front
.LP
There are two aspects of Akaros virtualization model that require impactful, albeit small (2500 lines total), changes.
.LP
The first is the implementation of Ring V. Processes need to record which
ring they are returning to; they need to store extra state for Ring V (about 8k); and
they need the additional assembly support. These changes are not large, but they
are hard to get right. With VM programming on x86 processors, one symptom of incorrect setup
is a very fast reset/reboot. Further, they add complexity to the kernel.
.LP
Second is the code to implement host process virtual and guest physical identity mapping.
In Akaros, this is achieved by having every host page table page paired with a guest page table page -- 
i.e., every page table page is now 8k, not 4\(dgk. 
.FS
\(dgPeople tend to worry when they hear this, but the actual impact is quite minor: 
on an 8 GiB machine the memory for page table pages increases by 16 MiB. 
.FE
On 9front, we have implemented this "double page table page" change, and
whether it is used is controlled with a boot time command line argument. I.e., "double page page tables" do
not require recompiling the kernel\(dd.
.FS
\(ddCode avaliable at shithub.us.
.FE
.LP
Although we have part of the Akaros model working, 
before making more far reaching changes, we decided to take a less
impactful approach, leveraging the way that Plan 9 threads and the 9front vmx device work.
Before describing our implementation, we will review Plan 9 threading and the 9front VMX device.
.SH 
A quick review of Plan 9 libthread
.LP
Plan 9 threads are lightweight, non-preemptive coroutines, running in one or more
processes which share memory.
Lightweight threads can be created in the current process, via threadreate; or in an external process, 
via procrfork. Whether in the same process or a process created by procrfork, all memory is shared, including
stacks. The main purpose of procrfork is to allow calls to operations, such as file I/O, that can
block the process and hence all the threads. 
A common programming idiom is to use procrfork for each
file descriptor a program creates. 
Libthread also allows creation of processes which do not share data memory, via proccreate:
these share the process code image and also run their own threads, however, they are entirely
independent of the other processes. We will not consider that additional
external process model here, as it has no bearing on VMThreads.
.LP
As mentioned above, in libthread,
a single thread in the same process is created by 
.CW threadcreate.
We follow this naming convention: VMThreads are created with
.I vmthreadcreate.
.LP
Threads communicate via channels. A channel is an in-memory pipe which transmits
basic scalar types such as bytes, ints, and pointers. When a thread sends on a 
channel, it will usually be descheduled and another thread can run. Threads can also voluntarily
yield the processor with a yield() function.
.LP
Threads do not normally yield; sends and receives on chans cause scheduling events, which is how concurrency
is supported. For parallelism, additional processes can be added via procrfork.
For more information on Plan 9 threading, please see the documentation.
.SH
9front vmx device
.LP
From the 9front man page:
.P1
The vmx device supports "virtual CPUs" using the Intel VT-x
extension (a.k.a. VMX instruction set).  This is used by
vmx(1) to implement virtual machines.  Access to the vmx
device is restricted to the hostowner.

The top level directory contains a clone file and numbered
subdirectories representing the allocated virtual CPUs.
.P2
.LP
The device is available in #X. Initially, only a file named clone appears. 
As VMs are created, 
numbered directories appear with control files, as in this example, where the first
VM has been created. Unlike PIDs, the VM numbers are not reused; 
as new VMs are created, the number
continues to increase. 
.P1
 '#X/0'
 '#X/clone'
 '#X/0/ctl'
 '#X/0/fpregs'
 '#X/0/map'
 '#X/0/regs'
 '#X/0/status'
 '#X/0/wait'
.P2
.LP
Control of VMs is via commands written to the ctl file. Registers are available
from the fpregs and regs files. The map file shows how guest physical memory is mapped
to the segment device. Status shows the VM status. Wait can be opened and read;
the read call returns when the VM guest status changes (usually via a VMEXIT).
For further information, see the man page on 9front.
.LP
The wait file information is provided as text records, delimited by newlines.
For example, a VM that exits from a vmcall would return:
.P1
 .vmcall 0x0 pc 0x20091a sp 0x4ffefac ilen 0x3 iinfo 0x0
.P2
The wait record for vmcall provides 
the decoded instrucion (vmcall); the PC and SP, and the instruction length.
Nothing more is needed to know how to handle the vmcall; the handler need only 
extract the first parameter from RBP; and succeeding parameters from the stack\(dg. 
.FS
\(dgBy contrast, on Akaros, a VM exit causes the thread to resume in Ring 3.
.FE
.LP
The VM exit suspends the VM, and returns information about the exit via the wait file, to a
process that is reading from it. In current implementations,
following libthread convention, that function bundles up the information and writes
it to a channel, where it comes under the domain of the lightweight threads. The process
is used so that it can block on the wait file read without blocking the lightweight threads\(dd.
.FS
\(ddThis same technique is used in the Go runtime, but the process creation is managed by the Go runtime,
not by the user.
.FE
.LP
Handling of the vmexit is simple.
The line is broken into fields, and the first field is checked against a lookup table:
.P1
struct ExitType {
	char *name;
	void (*f)(ExitInfo *);
};
static ExitType etypes[] = {
	{"io", iohandler},
	{".cpuid", cpuid},
...
};
.P2
Each entry in the lookup table names a class (e.g. "io") or an instruction (.e.g ".cpuid") and a pointer
to a handler. The handler is provided with the ExitInfo. 
The handler decodes the information, implements the operation, and updates the return PC.
Here is the code for the hlt instruction:
.P1
static void
hlt(ExitInfo *ei)
{
	if(irqactive < 0)
		state = VMHALT;
	skipinstr(ei);
}
.P2
This instruction will set the VM state to VMHALT if there are no instructions active; advance the PC by calling 
skipinstr; and return.
.LP 
In the next section, we describe how we implement VMThreads with libthread and devvmx.
.SH
VMThreads on 9front
.LP
As mentioned, on Akaros, 
the guest physical address space is mapped 1:1 with the process virtual address space.
On Akaros, we call the guest-host mapping EPT=KTP, meaning that guest mappings (EPT) and the host mappings (KPT) all point to the same memory. To keep it shorter, we will call this ID, meaning Identity mapped host virtual and guest physical memory. 
All that it means is that a guest physical address and a host virtual address point to the same memory; 
hosts and guests can communicate pointers to each other without having to translate 
them.
In the examples we present below, process virtual memory addresses a 64MiB region, 0x1000000-0x5000000, 
corresponding to guest physical addresses 0x1000000-0x5000000. 
A physical guest address in this range points to the same
memory as the process virtual address.
.LP
Unlike Akaros, we have not implemented complete ID mapping for guest to host. 
Most of the effect can be obtained by using segattach, to create shared memory regions. 
The VMM creates a global segment, then directs the VM instance, 
via the  ctl file, to use that segment for part of its memory. The result is that the
VMM and the VM are using a common memory segment. 
.LP
The mapping is created by vmthreadinit.
VMthreadinit maps a data area via segattach, and maps two segments from it
as specified by two parameters: 
the size of the low, unshared memory; and the size of a high range of shared memory.
.LP
In the examples presented, the user calls vmthreadinit as follows:
.P1
vmthreadinit(16*1024*1024, 64*1024*1024);
.P2
This is enough to allow 1 MiB for low guest physical memory; 1 MiB for the
shared frame buffer, and a large shared ID area for the guest and host.
Host software can not use the memory range from 0 to 2 MiB, but the guest can use physical memory from 0 to 
2 MiB.
The memory from 2 MiB to 16 MiB is copied, not shared, between host and guest. Any new guest code, such
as a kernel,  must
be loaded at 16 MiB, and be able to function with a 15 MiB hole starting at 1 MiB. 
Fortunately, modern kernels, including Plan 9, work fine with this hole. The days of
having to load at the 1 MiB boundary are long gone\(dg.
.FS
\(dgTo have 9front boot at 16 MiB requires a 3-line change to the kernel mkfile:
.P1
-KTZERO=0xffffffff81110000
-APBOOTSTRAP=0xffffffff81007000
-REBOOTADDR=0x111000
+KTZERO=0xffffffff80110000
+APBOOTSTRAP=0xffffffff80007000
+REBOOTADDR=0x11000
.P2
.FE
.LP
The result is that a large fraction of the memory is shared between guest and host: 
starting at the 16 MiB boundary, and up to the size of the VM, all memory is shared
and all pointers are interchangeable. This is particularly useful for virtio, since
it uses ring buffers to pass pointers.
Process stack is not accessible from the guest. The guest has a copy of the host text,
data, and BSS at the time of vmthread creation, but that is not shared.
.LP
Limiting the programs to low 16 MiB might seem to be a problem. 
For non-Plan 9 systems, fitting a full VMM in 14 MiB would be very difficult. 
But Plan 9 programs
tend to be compact, and the ABI of the #X device helps:
the 
9front VMM, called vmx, is only 512 KiB, which is anywhere from 10 to 100 times smaller
than many Linux VMMs. 14 MiB is more than enough for the foreseeable future.
However, should the day come when more is needed, it is easy enough to load the kernel at a much
higher address, by adjusting the parameters to vmthreadinit. The decision on where to split the shared and unshared memory is easy to change.
In this example, the addresses from 16MiB to 80MiB are shared in in the process virtual and guest physical.
.PS
P:box "process virtual" wid 1.2i
S:box "devsegment" wid 1.2i with .w at last box.e + (1,0)
G:box "guest physical" wid 1.2i with .w at S.e + (1,0)

box "0-2MiB" ht .2i wid 1.2i with .s at P.n + (0,.2i)
box "2MiB-16MiB" ht .6i wid 1.2i with .s at last box.n

Q: box "16MiB-80MiB" ht .4i wid 1.2i with .s at last box.n
R:box "80MiB-96MiB" ht .4i wid 1.2i with .s at last box.n

T: box "0-64MiB" ht .4i wid 1.2i with .s at S.n + (0,1i)
U: box "64MiB-80MiB" ht .4i wid 1.2i with .s at last box.n

H: box "0-16MiB" ht .8i wid 1.2i with .s at G.n + (0,.2i)
I: box "16MiB-80MiB" ht .4i wid 1.2i with .s at last box.n

line from Q.ne to I.nw
line from Q.se to I.sw
arrow from R.e to U.w
spline -> from U.e right 3 then to H.e 
.PE
.SH
Code
.LP
Below we present some examples of the threading in action.
.LP
The first example shows an infinite loop. 
.P1
	vmthreadinit(16*1024*1024, 64*1024*1024);
	static u8int brdot[] = {0xeb, 0xfe};

	if (vmthreadcreate(brdot, nil, 1024) < 0) {
		exits("vmthreadcreate failed");
	}
.P2
For this first example, we show the vmthreadinit call; Since it is required setup code, we will not show it again.
VMThreads functions test whether vmthreadinit has been called and will return with an error if it has not.
.LP
Vmthreadcreate is called with pointer to brdot, which is the 2-byte infinite loop for x86.
This shows the ease with which both a VMM and a guest VM can be set up in the same program.
The VM is run by a VMM function, runloop, which starts the VM and calls yield(), allowing other threads to run while the VM runs.
.SH
Using vmcall
.LP
VMcall allows guests to call functions in the host. 
Because pointers in the VM and in the host are compatible, any pointers returned via the VM exit, from the VM
itself,
and passed back via the wait file, can be transparently used by the thread managing that exit. 
.P1
// This code runs in the host to support vmcall exits.
static void
dovmcall(ExitInfo *ei)
{
	void (*f)(void);
	uvlong *sp;
	f = (void *)rget(RBP);
	sp = (void *)rget(RSP);
	f(sp[1], sp[2], sp[3], sp[4]);
	skipinstr(ei);
}
.P2
And add that function to the set of instructions handled in vmexit:
.P1
static ExitType etypes[] = {
	{"io", iohandler},
	{".cpuid", cpuid},
...
	{".xsetbv", xsetbv},
+	{".vmcall", dovmcall},
};
.P2
.LP
Then it is just a matter of calling the vmcall instruction in the guest.
We show an example below.
.LP
First, the library provides a vmcall assembly stub, which is called in the guest:
.P1
// This code runs in the guest to implement a vmcall.
TEXT vmcall(SB), $0
	BYTE $0xf; BYTE $0x1; BYTE $0xc1
	RET
.P2
The function itself is declared in C as taking varargs:
.P1
void vmcall(uvlong, ...);
.P2
The stub need do no argument setup; the compiler does that as part of normal function calling.
.LP
We can define a simple function to be called from the vmcall handler, i.e. in the host:
.P1
// Host code, callable from the host vmcall handler.
void vhello(void){
	print("hello");
}
.P2
The guest code vmthread then becomes:
.P1
// Guest code, set up by a vmthreadcreate call:
void
setter(void *arg)
{
	vmcall((uvlong)vhello);
}
.P2 
.LP
The threadcreate is:
.P1
.P2
vmthreadcreate(setter, nil, 1024);
.LP
The VMThread is able to call, via a vmcall, a function in the host.
.SH
Extending the use of vmcall
.LP
Valid virtual user mode addresses in Plan 9 start at 2MiB and go up.
This allows us to use the addresses in the 0-2MiB range for other operations.
We currently divide this range as shown in the table below.
.TS
c s s s
c c c
l l l.
vmcall opcodes and arguments
opcode	arguments	function
0-127	None	Print the argument to stdout
0x1000	None	Print registers and the first 2MiB of page table mappings
0x2000-0x2fff	[arg0, arg1, ...]	Call syscall number (opcode-0x2000), with the args
2MiB and up	[arg0, arg1, ...]	Call function pointer in arg0 with the  args
0x80000000 | opcode	[arg0, arg1, ...]	Call syscall number ((uint32)opcode), with the args.
		Intended for guest kernel system calls
.TE
.SH
Running code in shared memory
.LP
Next we show the code which runs in the shared space.
First, support code copies the running program to the shared space,to provide
a default image:
.P1
memmove(vmbase+0x200000, (void*)0x200000, (uvlong)sbrk(0) - 0x200000);
.P2
Note that the code must copy from the start of the program, at 0x200000, to that location
offset from vmbase. In any real PC, the low 1MiB of memory has many legacy addresses that are best avoided;
further, it is best to align the destination on a 2 MiB boundary.
.LP
To call the program, for now, we must offset the addess with vmbase. 
.P1
vmthreadcreate((void *)((u8int*)vmbase+(uvlong)setter), nil, 10240;
.P2
This is what the guest code looks like in this example:
.P1
	vmcall((uvlong)vhello, "hi %p %d", arg, 0xaa55);
	vmcall((uvlong)vhello, "hi");
	vmcall((uvlong)vhello, "hi");
.P2
This code is running in the VM, calling a function in the host.
The function is being run by the thread that created the VM.
.SH
More complex guest code
.LP
Once we are able to call arbitrary code, we can implement more complex guest functions.
The function shown below is the first part of ping.
.P1
void directcall(void *arg)
{
	extern uvlong vmcall(uvlong,uvlong,uvlong,uvlong,uvlong);
	int fd;
	USED(arg);
	vmcall((uvlong)print, (uvlong)"direct call", 0, 0, 0);
	fd = (int) vmcall((uvlong)open, 
				(uvlong)"/net/icmp/clone", 
				(uvlong)ORDWR, 0, 0);
	vmcall((uvlong)print, (uvlong)"fd is %d", fd, 0, 0);
	while(1);
}
.P2
.SH
Using vmcall to implement kernel drivers in the guest
.LP
When VMThreads are being used to run a kernel, 
the common shared memory can provide a new way to implement
access to the platform.
Since all resources in Plan 9 are accessed via the file interface, it suffices to make
the file interface conveniently accessible to the guest -- which, as shown above, we have done.
The entire bottom half of the kernel can consist of calls to
functions in the low memory. 
The code is readonly, so corrupting it is not an issue. The data is writable, but it is a copy -- 
any corruption of the low data memory will result in the untimely exit of the guest.
.LP
Using host virtual addresses from the kernel requires that the kernel be linked with vmx, which is
inflexible.
Instead, we created a device, #Z, which maps device functions to system calls.
In this case, all pointers must be passed as kernel physical, not kernel virtual; 
further, data from user programs must be copied in to kernel space, to ensure it is physically contiguous
and to avoid Time Of Check/Time Of use (TOCTOU) problems.
.LP
The bounce buffer adds overhead,
but a non-bounce-buffer implementation would be far more complex, requiring breaking the
read into groups of physically contiguous pages, with the required page table walks, locking,
and bugs.
For now, the performance of the bounce buffer implementation is more than adequate.
.LP
The result is a very different model than has been used in recent virtual machine models: the guest kernel
is accessing system resources in the same way as any host process, via file operations; 
its operations are visible in the 
same way host process operations are visible. This would rememedy a common problem that comes with VMs: when
malware hides behind a virtualization wall, using the opacity of emulated device IO to hide its network
operations. 
We can easily see what is going on behind the virtualization veil. 
.SH
Comparative directory performance with du
.LP
The performance of #Z was always far superior 
in the earliest version. Using
.P1
time du -s
.P2
on different paths, it was anywhere from 2 to 10 times as fast as the virtual disk.
However, there was a problem: the IO was blocking, and programs (e.g. telnet) that forked and had several FDs active would fail, because
the entire VM was blocked on one read; the other read never had a chance
to run.
We moved to using ioprocs for IO, and that caused a dramatic
drop in performance for disk walking: that same du is ten times slower.
Ioprocs have never been a great performance win; we may bring 
virtio support over from Harvey-OS and try that.
Another option is to use blocking reads for directories.
.SH
Comparative IO performance
.LP
IO to /dev/console can be much faster, as the IO is direct, rather
than by device emulation. In this example, 4 MiB of console IO
is 700 times faster.
.P1
term% time dd -if /dev/zero -of /dev/cons -bs 4096 -count 1024
...
0.00u 0.02s 315.89r 	 dd -if /dev/zero -of '#Z'/dev/cons ...
term% time dd -if /dev/zero -of '#Z'/dev/cons -bs 4096 -count 1024
...
0.00u 0.53s 0.53r 	 dd -if /dev/zero -of #Z/dev/cons ...
term% 
.P2
.SH
An example offloading of kernel components to the host
.LP
All Plan 9 network access is effected by file I/O. By convention, the files are located
in /net or /net.alt.
One could build a kernel with no IP stack, and no network drivers, and provide network access
as follows:
.P1
bind '#Z'/net /net
.P2
At that point, all programs which use the network will transparently use the network
of the VMM. The kernel running in the guest can hence be very small.
.SH
Debugging guest kernel allocation with host kernel acid
.LP
Going beyond using external name spaces for kernel use, we can even externalize
core kernel functions to the vmm.
Consider the kernel allocator.
It is compatible with the libc calling conventions.
We could establish a memory pool in the shared area, and then outsource memory
allocation to the VMM:
.P1
void *kernelmalloc(int sz) {
	return vmcall(malloc, sz);
}

void free(void *f) {
	vmcall(free, f);
}
.P2
Once the guest kernel is using the host (VMM) allocator, we can, 
further, use the acid storage leak detector to look for kernel misbehavior.
The VMM could also look for memory corruption in the arena and notify
the user when it occurs.
This could be a useful technique for debugging very difficult memory corruption.
.LP
When starting a VM becomes equivalent to starting a thread, many possibilities
present themselves. 
The community has gotten into something of a herd mentality, where starting
a VM is a Big Deal, and naturally requires large, complex libraries and system management.
We argue the exact opposite: starting a VM should be no harder than
starting a thread.
.SH
Conclusions and future work
.LP
We have described vmthreads, an extension to the 9front libthread, which allows guest virtual machines to run 
as a thread. VMs share memory, and can call host functions directly via vmcall.
The current implementation provides most of the capability we had on Akaros: a large memory
area is shared, but the code, data and bss segmeents
are copied, not shared. Stack is never shared or copied. 
.LP
Future work includes exploring the model in its current state, to see how it might be used; and, going one step further
and enabling full sharing of the data and bss segments.
The idea of a driverless guest needs to be explored; replacing emulated devices
with system calls should allow higher perfomance.
Finally, since the Go threading model derives directly from Plan 9, we can create a
vmthreads package for Go. So much of the Plan 9 model already exists in the Go runtime,
it will mostly be a matter of adding the vmx device IO to a Go program.

