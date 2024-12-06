.HTML "VMThreds: virtual machines as threads in libthread"
.TL
VMThreads: virtual machines as threads
.FS
License: CC-BY-ND-SA
.FE
.AU
Ron Minnich
.sp
rminnich@gmail.com
.AB
Virtualization is a capability that allows privileged code to run in a less-privileged context, i.e. a virtual machine (VM).
VMs require a virtual machine manager, or VMM. 
On modern operating systems, virtual machines (VMs) are supported by hardware, and  are managed by kernels, and presented to VMMs,
as a device. 
VMMs open a device, and operate on it as they would any other real device, such as a network card. This interface is difficult enough that,
17 years after virtualization came to Linux, there are only a handful of commonly used VMMs.
.LP
On the Akaros operating system, we created a new model, vmthreads, in which VMs were created, and managed, as though they were just another thread. 
This model provided a far more convenient abstraction for virtual machines: 
it was no longer necessary to write VMMs; a VM was created and control as a thread in a multithreaded program.
.LP
Adding a VM to a program is as easy as adding a thread; adding more cores just needs more threads.
Creating and using a VMM is no more exotic than file I/O.
.LP
We discuss the implementation of this model on the 9front release of Plan 9. While the model is not quite as complete as the Akaros version, 
we take advantage of the unique properties of Plan 9 to gain other advantages.
.AE
.SH
Introduction
.LP
Virtualization, once limited to the exotic domain of IBM mainframes,  
is ubiquotous on commodity client and server systems, running on everything from phones to cloud servers.
Chip vendors have made significant changes over the last 20 years to make virtualization efficient.
A guest VM, as measured on cloud servers, can achieve aboout 91% of the throughput of running on host; 
in some cases, it can even run faster.
.LP
While virtualization is common, it is not easy to write code for. 
The device model provided by most kernels (e.g. Linux) is tricky and easy to get wrong, with 
difficult to understand failures. 
It is also large :
Virtualization software for, e.g., Linux, is considered compact if it only requires a few thousands of lines of code to run. 
Virtual Machine Managers (VMMs) can be very large, with a memory footprint of 10 MiB to 500 MiB. 
.LP
In this paper we introduce 
.I VMThreads,
a virtualization model which is incorporated into the Plan 9 thread library. 
VMThreads, as the name implies, allows users to create and run VMs as a thread in a process.
For example, this code starts an infinite loop as a VM thread, running in guest ring 0 on an x86.
.P1
extern void *vmbase;
static u8int brdot[] = {0xeb, 0xfe}; // 1: jmp 1b
vmthreadcreate((void *)brdot, vmbase, 1024);
.P2
The API is identical to the threadcreate API from libthread.
.LP
The rest of this paper is organized as follows: we provided an overview of virtualization; discuss
the akaros vmthread virtualization model; discuss the implementation of this model in Plan 9
.I libthread,
and then show examples of its use.
.SH
Virtualization
.LP
Virtualization allows privileged software to run in an unprivileged context, a.k.a., a guest, under control of a host. 
Virtualization provides services required by applications, that might not be provided by the host (.e.g Linux running as a guest on OSX); 
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
software. Xen was an early open source virtualization system for commodity x86 systems, and was widely deployed on Amazon Web Services. 
.LP
Xen is a kernel which runs other kernels as a VM guest, i.e. "Domains", with one kernel ("Domain 0")
being given special priveleges to perform IO, since Xen has no drivers
of its own. 
Xen is always the host, and kernels are always the guest. In Xen, every kernel runs
at a lower privilege level than the Xen kernel. 
.LP
Following close on the heels of Xen came other systems; Linux KVM (Kernel Virtual Machine) is probably the most widely used. 
There are at last count eight different VMs available on Linux; one for the BSD kernels; one for Darwin; and one for Plan 9.
.LP
Unlike Xen, 
KVM, VMWare, and other VMs run as a driver in a host kernel, usually Linux.
In this model, a single general purpose host kernel is more 
privileged than the virtual machine software, which in turn is more privileged than any VM guest. 
The driver manages architectural features that enable and control virtualization. 
.LP
Xen and KVM are structurally very different systems. 
The arguments over classifying these types of VMs may never end, but, commonly, Xen is called a Type 1 hypervisor, as it is in itself a kernel
above all other kernels; and KVM,the BSD VMs, the OSX and Plan 9 VMs;  are called a Type 2, as they are contained
in a general purpose kernel. For the rest of this paper, we restrict the discussion to Type 2 kernels. When we use the term VM, we are 
discussing a Type 2 VM.
.LP
Running a VM guest requires two software components: the VM code in the kernel; and a so-called
Virtual Machine Manager (VMM).
The VMM is a program that operates on the VM to load, run, and manage a guest. As the guest VM runs, it will stop with error codes, interrupts,
or by the guest itself requesting services;  which 
must be managed by the VMM. 
In some cases, the VMM can be called upon to emulate some instructions. 
VMMs can be very complex, and, consequently, can be very large. 
We know of one proprietary VMM which is a 500 MiB binary; 
at the same time, a basic VMM, written in C, can be as small as a megabyte. 
Typically, samller VMMs can not handle the varying demands of guests; the larger VMM has support for more complicated operations. 
A common open source VMM is qemu, but there are many others, e.g. the KVMTool, CrosVM, Cloud Hypervisor, and GoKVM tools for Linux. 
.LP
With few exeptions, the VM API is built around a device model, frequently
requiring special privilege to access. 
Programs which 
use the VM open the device and use a file descriptor to control it. 
The separateness of the device is always apparent. The abstraction
is complicated and not convenient.
.SH
Akaros virtualization: VMs as threads
.FS
https://github.com/brho/akaros. See the patches starting at ddb9fa78b5d97e4107a9404f4146140ef8bf9a5a from 
April 1, 2015 and on (yes, April Fool's day!).
.FE
.LP
As part of our Akaros research at Google, we developed an entirely
new VM model, by adding a new program protection level we called Ring V.
Ring V is identical to the X86 Ring 3, a.k.a user mode, save that it is a VM.
When the Akaros kernel exits Ring 0 (kernel) to the program, it
checks a flag in
the process structure and either does
a traditional exit to Ring 3, using the saved trap context and RETI (return from interrupt) instruction;
or to Ring V, using the VM Control Structure (VMCS) context and a VMRESUME instruction.  
Akaros can decide, each time it resumes a process, whether to resume it in Ring 3 or Ring V. 
Processes can flip back and forth between the two modes at will. 
.LP
Akaros takes the model one step further: the guest physical address space is the same as process virtual address space. 
A VMM can start a kernel by starting a vmthread with the kernel entry point as the initial program counter (PC). 
VMMs can even run user programs in Guest Ring 0, i.e. as kernels. One use of a Guest Ring 0 program would be a device driver, which could safely
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
Below we show show the custom vmcall handler code.
.P1
enum {
	MY_VMCALL_TEST1 = VTH_VMCALL_NEXT,
	MY_VMCALL_TEST2,
};

/* Here's how you can make your own vmcalls and still 
 * use the standard vthread vmcalls for
 * standard operations. You also have the option
 * to replace or extend the standard operations. */
static bool extended_handle_vmcall(struct guest_thread *gth,
                                   struct vm_trapframe *vm_tf)
{
	switch (vm_tf->tf_rax) {
	case MY_VMCALL_TEST1:
		goto out_ok;
	}
	// call this for standard vmcalls.
	return vth_handle_vmcall(gth, vm_tf);
out_ok:
	vm_tf->tf_rip += 3;
	return TRUE;
};

/* Structure to define a virtual machine.
 * In this example, we tell Akaros that we have
 * a custom vmcall handler, and initialize the
 * mutex (.mtx) structure member.
 */
static struct virtual_machine vm = {.vmcall = extended_handle_vmcall,
                                    .mtx = UTH_MUTEX_INIT};
.P2
There is an enum, which defines several test vmcalls; and a function, 
extended_handle_vmcall, which implements the vmcall itself. 
If the vmcall is not handled by this function, as determined by the
switch, then the standard vth_handle_vmcall function is used.
If the .vmcall structure member in the virtual_machine struct is left
unset, then the Akaros libraries provide a default handler.
.FS
I no longer remember why we coded it this way, instead of using 
a default in the switch. It may be because of the needed manipulation
of the return address (tf_rip).
.FE
.LP
Finally, we can show the VMM itself. This examples runs 5 VMs simultaneously, i.e. on 5 cores.
This is a multi-threaded program running several VMs on several cores at once. This is the
technique we use to start an SMP kernel such as Linux.
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

	/* Tests reuse / GPC leakage */
	for (long i = 0; i < NR_VTHS * 2; i++) {
		vths[0] = vthread_create(&vm, thread_entry, (void*)i);
		vthread_join(vths[0], &retvals[0]);
		assert(retvals[0] == (void*)i);
	}
	assert(vm.nr_gpcs == NR_VTHS);

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
it uses a fork/join model. The only difference, not really visible
at first, is that all the threads run in a VM.
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
is a very fast reset/reboot. Further, they do add complexity to the kernel.
.LP
Second is the code to implement host process virtual and guest physical identity mapping.
In Akaros, this is achieved by having every host page table page paired with a guest page table page -- i.e., every page table page is now 8k, not 4k. 
People tend to worry when they hear this, but the actual impact is quite minor: 
on an 8 GiB machine the memory for page table pages increases by 16 MiB. 
We have implemented this change, with a boot time command line argument. I.e., it does
not require recompiling the kernel.
.FS
Code avaliable at shithub.us.
.FE
.LP
Nevertheless, before making such far reaching changes, we decided to take a less
impactful approach, levering the way that Plan 9 threads and the 9front vmx device work.
.SH 
A quick review of Plan 9 libthread
.LP
Plan 9 threads are lightweight, non-preemptive coroutines, running in one or more
processes which share memory.
The model also allows creation of processes which do not share memory, if required;
these share the process code image and also run their own threads. We will not consider that additional
external process model here, as it has no bearing on VMThreads.
.LP
In libthread,
a single thread in the same process is created by 
.CW threadcreate.
We follow this naming convention: VMThreads are created with vmthreadcreate.
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
The device presents VMs as files:
.P1
          #X/clone
          #X/n
          #X/n/ctl
          #X/n/fpregs
          #X/n/map
          #X/n/regs
          #X/n/status
          #X/n/wait
.P2
 Control of VMs is via commands written to the ctl file. 
.LP 
In the next section, we describe how we implement VMThreads with libthread and devvmx.
.SH
VMThreads on 9front
.LP
As mentioned, on Akaros, the guest physical address space is mapped 1:1 with the process virtual address space.
On Akaros, we call the guest-host mapping EPT=KTP, meaning that guest mappings (EPT) and the host mappings (KPT) all point to the same memory. To keep it shorter, we will call this ID, meaning Identity mapped host virtual and guest physical memory. 
All that it means is that a guest physical address and a host virtual address point to the same thing; 
hosts and guests can communicate pointers to each other without having to translate 
them.
.LP
We have not imlemented ID mapping for guest to host. However, most of the effect can be obtained, as 
the 9front vmx command does, by using segattach. The VMM creates a global segment, then directs the VM instance, 
via the  ctl file, to use that segment for part of its memory. The result is that the
VMM and the VM are using a common memory segment. 
.LP
Vmthreadcreate maps a large middle data area via segattach, and maps it at 0x1000000 (16 MiB). 
It creates another segment for the low 16 MiB of memory.
This is enough to allow 1 MiB for low guest physical memory; 1 MiB for the
shared frame buffer, and a large shared ID area for the guest and host.
Host software can not use the memory range from 0 to 2 MiB, but the guest can use physical memory from 0 to 
2 MiB, so this works fine.
The memory from 2 MiB to 16 MiB is copied, not shared, between host and guest. Any new guest code, such
as a kernel,  must
be loaded at 16 MiB, and be able to function with a 15 MiB hole starting at 1 MiB. 
Fortunately, modern kernels, including Plan 9, work fine with this hole. The days of
having to load at the 1 MiB boundary are long gone.
.FS
To have 9front boot at 16 MiB requires a 3-line change to the kernel mkfile:
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
The result is that a large fraction of the memory is shared between guest and host: starting at the 16 MiB boundary, and up to the size of the VM, all memory is shared
and all pointers are interchangeable. This is particularly useful for virtio, since
that uses ring buffers to pass pointers.
Process stack is not accessible from the guest. The guest has a copy of the host text,
data, and BSS at the time of process creation, but that is not shared.
.LP
Limiting the programs to low 16 MiB might seem to be a problem. 
For non-Plan 9 systems, fitting a full VMM in 14 MiB would be very difficult. Plan 9 programs
tend to be compact. The 
9front VMM, called vmx, is only 512 KiB, which is anywhere from 10 to 100 times smaller
than many Linux VMMs. 14 MiB is more than enough. 
However, should the day come when more is needed, it is easy enough to load the kernel at a much
higher address. The decision on where to split the shared and unshared memory is easy to change.
.SH
Code
.LP
Below we present some examples of the threading in action.
.LP
The first example shows an infinite loop. 
.P1
	vmthreadinit(16*1024*1024, 64*1024*1024);
	static u8int brdot[] = {0xeb, 0xfe};

	if (vmthreadcreate(brdot, (void *)0x1000000, 1024) < 0) {
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
References
.LP
[Bac86] Maurice J. Bach,
.I "The Design of the UNIX Operating System,
Prentice-Hall,
Englewood Cliffs,
1986.
.LP
[Dij72] Edsger W. Dijkstra,
``The Humble Programmer \- 1972 Turing Award Lecture'',
.I "Comm. ACM,
15(10), pp. 859-866, 
October 1972.
.LP
[Hol91] Gerard J. Holzmann,
.I "Design and Validation of Computer Protocols,
Prentice-Hall,
Englewood Cliffs,
1991.
.LP
[Pik90]
Rob Pike,
Dave Presotto,
Ken Thompson,
Howard Trickey,
``Plan 9 from Bell Labs'',
.I "Proceedings of the Summer 1990 UKUUG Conference,
pp. 1-9,
London,
July, 1990.
.LP
[Sal66] Jerome H. Saltzer,
.I "Traffic Control in a Multiplexed Computer System
MIT,
Cambridge, Mass.,
1966.
