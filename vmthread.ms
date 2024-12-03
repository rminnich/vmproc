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
threads can call host functions with the vmcall. 

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
