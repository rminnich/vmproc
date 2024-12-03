.HTML "vmcreate: virtual machines as threads
.TL
vmcreate: virtual machines as threads
.AU
Ron Minnich
.sp
rminnich@gmail.com
.AB
.FS
a footnote
.I
in italics
.R
and more
.FE
On modern operating systems, virtual machines (VMs) are provided by a device abstraction. Programs open a device, and operate on it as they would a type of network card.
.LP
On the Akaros operating system, we created a new model, vmthreads, in which VMs were created, and managed, as though they were just another thread. This model provided a far more convenient abstraction for virtual machines. 
.LP
We discuss the implementation of this model on the 9front release of Plan 9. While the model is not quite as complete as the Akaros version, we take advantage of the unique properties of Plan 9 to gain other advantages.
.AE
.LP
Virtualization allows privileged software to run in an unprivileged context, a.k.a., a guest, under control of a host. The guest provides services required by applications, that might not be provided by the host (.e.g Linux running as a guest on OSX); and a security boundary for the the host, protecting it from the guest. Virtualization has been available since the 1960s on IBM mainframes. 
.LP
Until the release of VMWare several decades ago, virtualization
had been almost ignored in non-mainframe operations. 
Since then, howeve,r virtualization has become very widely used, and even taken for granted, on a wide range of systems, including inexpensive laptops such as Chromebooks, up to and including the largest cloud servers. 
.LP
Once virtualization became more popular, users  wished for
an alternative to proprietary virtualization 
software. Xen was an early open source virtualization system for commodity x86 systems, and was widely deployed on Amazon Web Services cloud. 
.LP
Xen is a kernel which runs other kernels as a VM guest, as "Domains", with one kernel ("Domain 0")
being given special priveleges to perform IO, since Xen has no drivers
of its own. 
Xen is always the host, and kernels are always the guest. In Xen, every kernel runs
at a lower privilege level than the Xen kernel. 
.LP
Following close on the heels of Xen came other systems; Linux KVM (Kernel Virtual Machine) is probably the most widely used. There are at last count eight different VMs available on Linux; one for the BSD kernels; one for Darwin; and one for Plan 9.
.LP
Unlike Xen, 
KVM, VMWare, and other VMs run as a driver in a host kernel, usually Linux.
In this model, a single general purpose host kernel is more 
privileged than the virtual machine software, which in turn is more privileged than any VM guest. 
.LP
The arguments over classifying these types of VMs may never end. But, commonly, Xen is called a Type 1 hypervisor, as it is in itself a kernel
above all other kernels; and KVM,the BSD VMs, the OSX and Plan 9 VMs;  are called a Type 2, as they are contained
in a general purpose kernel. For the rest of this paper, we restrict the discussion to Type 2 kernels. When we use the term VM, we are 
discussing a Type 2 VM.
.LP
Running a VM guest requires two software components: the VM code in the kernel; and a so-called
.I Virtual Machine Manager (VMM).
The VMM is a program that operates on the VM to load, run, and manage a guest. As the guest VM runs, it will stop with error codes, which 
must be managed by the VMM. In some cases, the VMM can be called upon to emulate some instructions. VMMs are very complex, and, consequently, can be very large. We know of one proprietary VMM which is 500 MiB; at the same time, a basic VMM, written in C, can be as small as a megabyte. Typically, the larger VMM has support for more complicated operations. 
A common open source VMM is qemu, but there are many others, e.g. the KVMTool, CrosVM, Cloud Hypervisor, and GoKVM tools for Linux, 
.LP
With few exeptions, the VM API is built around a device model, frequently
requiring special privilege to access. 
Programs which 
use the VM open the device and use a file descriptor to control it. 
The separateness of the device is always apparent. The abstraction
is complicated and not convenient.
.LP
As part of our Akaros research at Google, we developed an entirely
new VM model, by adding a new protection label we called Ring V.
When the Akaros kernel exited Ring 0 (kernel) to the program, it
checked the process structure and either did a traditional exit to Ring 3, using the saved trap context; or to Ring V, using the VM Control Structure (VMCS) context.  
. The kernel can decided, each time it resumes a process, whether to resume it in Ring 3 or Ring V. Processes can flip back and forth across the boundary at will. 
.LP
Akaros takes the model one step further: the guest physical address space is the same as process virtual address space. A VMM can start a kernel by starting a vmthread with the kernel entry point as the initial proram counter (PC). VMMs can even run user programs in Guest Ring 0, i.e. as kernels. One use of a Guest Ring 0 program would be a device driver.
.LP
How does this look in practice? 
Shown below is a function that runs in the guest. It is called
thread_entry, and is part of a single file containing both
the VMM and the guest code. They can be compiled into one unit
because the guest physical addresses and the host virtual addresses
are the same; in fact, the guest physical memory is provided
directly from the host virtual memroy.
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
guest. The parameters to vmcall are placed in registers, following
the 64-bit x86 calling convention. There are two standard vmcalls used, VTH_VMCALL_PRINTC and VTH_VMCALL_EXIT; VTH_VMCALL_TEST1 is a custom 
vmcall implemented in this same program.
.LP
Below we show show the custom vmcall handler code.
.P1
enum {
	MY_VMCALL_TEST1 = VTH_VMCALL_NEXT,
	MY_VMCALL_TEST2,
};

/* Here's how you can make your own vmcalls and still use the vth vmcalls for
 * the stuff you don't want to reimplement. */
static bool extended_handle_vmcall(struct guest_thread *gth,
                                   struct vm_trapframe *vm_tf)
{
	switch (vm_tf->tf_rax) {
	case MY_VMCALL_TEST1:
		goto out_ok;
	}
	return vth_handle_vmcall(gth, vm_tf);
out_ok:
	vm_tf->tf_rip += 3;
	return TRUE;
};

static struct virtual_machine vm = {.vmcall = extended_handle_vmcall,
                                    .mtx = UTH_MUTEX_INIT};
.P2
There is an enum, which defines several test vmcalls; and a function, 
extended_handle_vmcall, which implements the vmcall itself. 
If the vmcall is not handled by this function, as determined by the
switch, then the standard vth_handle_vmcall function is used.
.FS
I no longer remember why we coded it this way, instead of using 
a default in the switch.
.FE
.LP
Finally, we can show the VMM itself.
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
To reiterate, all the code we are showing is in the same file.
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
are hard to get right. They add complexity to the kernel.
.LP
Second is the code to implement host process virtual and guest physical identity mapping.
In Akaros, this is achieved by having every host page table page paired with a guest page table page -- i.e., every page table page is now 8k, not 4k. 
People tend to worry when they hear this, but the actual impact is quite minor: 
on an 8 GiB machine the memory for page table pages increases by 16 MiB. 
We have implemented this change, with a boot time command line argument. I.e., it does
not require recompiling the kernel.
.LP
Nevertheless, before making such far reaching changes, we decided to take a less
impactful approach, levering the way that Plan 9 threads work.
.SH 
A quick review of Plan 9 libthread
.LP
Plan 9 threads are lightweight, non-preemptive coroutines, running in one or more
processes which share memory; and processes which do not share memory
but share the process code image and run threads. 
A single thead in the same process is created by 
.CW threadcreate.
A thread in a new process is created by 
.CW procrfork.
An independent process which begins with a copy of the process is calle 
.CW proccreate.
.LP
To these we add vmcreate.
vmcreate is a mixture of proccreate and procrfork, because we can not completely
share all the memory until we implement Akaros-style guest/host memory sharing. 
That said, we can get close.
.LP
On Akaros, we call the guest-host mapping EPT=KTP, meaning that guest mappings (EPT) and the host mappings (KPT) all point to the same memory. To keep it shorter, we will call this ID, meaning Identity mapped host virtual and guest physical memory. All that it means is that a guest physical address and a host virtual address point to the same thing; 
hosts and guests can communicate pointers to each other without having to translate 
them.
.LP
For Plan 9, vmcreate maps a large middle data area via segattach, and maps it at 0xe00000 (14 MiB). This is enough to allow 1 MiB for low guest physical memory; 1 MiB for the
shared frame buffer, and a large shared ID area for the guest and host.
The memory from 2 MiB to 14 MiB is not shared between host and guest. The kernel must
be loaded at 16 MiB, and be able to function with a 15 MiB hole starting at 1 MiB. 
Fortunately, modren kernels, including Plan 9, work fine with this hole. The days of
having to load at the 1 MiB boundary are long gone.
.LP
The result is that a large fraction of the memory is shared between guest and host: starting at the 16 MiB boundary, and up to the size of the VM, all memory is shared
and all pointers are interchangeable. This is particularly useful for virtio, since
that uses ring buffers to pass pointers.
Process stack is not accessible from the guest. The guest has a copy of the host text,
data, and BSS at the time of process creation, but that is not shared.
.LP
For non-Plan 9 systems, fitting a full VMM in 14 MiB would be very difficult. The 
9front VMM, called vmx, is only 512 KiB, which is anywhere from 10 to 100 times smaller
than many Linux VMMs. 14 MiB is more than enough.
.SH
Code
.LP

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
