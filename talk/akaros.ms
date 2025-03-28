Akaros Virtualization
VMs as threads
Akaros team

Some numbers
Kernel code: we think it’s about an additional 5? KLOC
Hard to tell any more, as it is integrated so completely into the process
model
But our vmx directory is 2KLOC so I multiplied by 2.5; almost certainly too
high
User libraries: about 12 KLOC
Includes user mode scheduler for VM threads
VMM: 690 LOC (not K)
This is sufficient to boot full prodkernel, run borglet, run apps, use
local disk
Have a gvisor-equivalent prototype that can support GR3 sentry
Boot to single user in well under one second
So fast we sometimes think it failed and returned to an akaros shell prompt

Akaros
Research kernel from Berkeley
Lots of new ideas but we will focus on one: “multi core process”
Key to understanding the new Virtual Machine Model
Multi Core Process (MCP) can be thought of as a set of cores assigned as an
entity to a program
Has the flavor of gang scheduling
An MCP manages scheduling of its cores in a “2LS”
Second level scheduler, a.k.a. User level thread scheduling
Thread scheduling is managed in the process, i.e. this is M:N system

MCP
Treat parallel processes as a single entity
Gang scheduled, no kernel thread per “pthread”/core
Single address space
The process is aware of its state
Number of cores, which ones are running, etc
Virtual machine work builds on this model

Virtual Machine support
First, what’s a VM?
Is it an instance of opening a device in /dev?
No: that’s one way of implementing VMs
How do VMs fit into the Akaros model?
We decided to take nothing for granted
A look back is useful
A VM could be kind of a process
How did we used to start processes?

Start process: HP MPE
Using CREATEPROCESS
Your program can call the CREATEPROCESS intrinsic to create a child
process.  Your program can control the creation of the child process with
the optional parameters itemnums and items.  The information you can pass
to MPE XL through itemnums/items parameter pairs include:
 *  The names of the files to be used as $STDIN and $STDLIST for the
    child process.
 *  An option that indicates if the child process is to be activated
    immediately after it is created, and if the parent process should be
    suspended automatically when the child process is activated.

 *
  A list of user-named executable libraries to be searched at load time
    for required external references.

 *  A user-created UNSAT procedure, to which all unsatisfied load-time
    external references may be directed.

This is an example of a CREATEPROCESS intrinsic call:

          .
          .
          .

ERRORCODE := 0;
     PIN := 0;
     BNAME := 'MYPROG.PUB.MYACCT';
     ITEMNUMS[1] := 3;
     ITEMNUMS[2] := 0;
     ITEMS[1] := 1;
     CREATEPROCESS (ERRORCODE,PIN,BNAME,ITEMNUMS,ITEMS);




Start a job: IBM
//CONCATEX JOB CLASS=6,NOTIFY=&SYSUID
//* Example 1:
//STEP10 EXEC PGM=MYPROG
//IN1    DD DSN=SAMPLE.INPUT1,DISP=SHR
//OUT1   DD DSN=SAMPLE.OUTPUT1,DISP=(,CATLG,DELETE),
//       LRECL=50,RECFM=FB
//SYSIN  DD *
//CUST1  1000
//CUST2  1001


Start a job on CDC
   /JOB
   COPYBR,INPUT,INPUT1.
   COPYBR,INPUT,INPUT2.
   REWIND,INPUT1,INPUT2.
   * RUN CHECKPOINT JOB
   LINK1,INPUT1,OUTPUT,PUNCH1,UT1.
   * MANIPULATE FILES
   PACK,PUNCH1.
   REWIND,PUNCH1.
   RETURN,POOL.
   RENAME,OPTP=NPTP.

 * RUN RESTART JOB
   LINK1,INPUT2,OUTPUT,PUNCH2,UT1.
   /EOR
   NASTRAN FILES=NPTP
    .
    . (Data for Checkpoint Job)
    .
   /EOR

NASTRAN FILES=OPTP
    .
   $ READ THE RESTART DICTIONARY
   READFILE PUNCH1
    .
   CEND
    .
    . (Data for Restart Job)
    .
   /EOF




On newer mainframes
 <devices>
    <redirdev bus='usb' type='tcp'>
      <source mode='connect' host='localhost' service='4000'/>
      <boot order='1'/>
    </redirdev>
    <redirfilter>
      <usbdev class='0x08' vendor='0x1234' product='0xbeef' version='2.56'
allow='yes'/>
      <usbdev allow='no'/>
    </redirfilter>
  </devices>


On Unix, in 1972
fork();
Starting a process was ugly before this
Unix made it easy and clean
It was also controversial because it encouraged people to use it
I.e. that one could, in DMR’s words, be “profligate” with processes
Forking a process to list files was considered ridiculous in many places

Virtualization today
Remember that “newer mainframes” slide?
That’s from libvirt
It’s a tiny fraction of the total giant pile of XML for one VM
Far more complex than the 1970s mainframe JCL example!
To start a virtual machine on linux requires
Daemons
Special user ids
Batch scheduling
Gigantic XML files
Mountains of code
We’ve recreated batch systems from mainframes for VMs
What’s going on here?

Virtualization model
Virtualization on Linux/BSD/Unix requires a device
Was not possible to go deeper, i.e. rework task and vm structures
Device access requires privileges (usually root)
But simple setuid approaches are dangerous
So we have daemons we talk to to do it for us
We did not want to assume current practice was the right approach
We ported several different VMs to Akaros while evaluating them
Gvisor, KVM, Dune, Bhyve, two others you never heard of
We did not have restrictions on how much we could change
We did not want to recreate a batch system for VMs
So, question, what keeps VMs just being another thread in our process?

VMs as threads
struct virtual_machine vm;
static int count;

int main(int argc, char **argv)
{
int  attrs = 0;
vthread_attr_init(&vm, attrs);
vthread_create(&vm, 0, vmcall, NULL);

        while(atomic_read(count) < 100000) {
        }

        return 0;
}

static void vmcall(void *a)
{
        while (atomic_add(count, 1) < 1000000) {
                __asm__ __volatile__("vmcall\n\t");
        }
        __asm__ __volatile__("hlt\n\t");
}

Thread
Virtual Machine Thread

In Akaros, VMs are threads
Recap:
Akaros processes and threads are somewhat different than you’re used to
Akaros schedules sets of cores (1 or more), not processes
And schedules entities called ‘multi core processes’ onto those cores
Threads are scheduled at user level onto cores
We have extended the thread model to include Virtual Machine Threads
Virtual Machine Threads (vthreads) can run:
Linux 4.8 (with 12 lines of patches so that we can tell it clock rates via
cmdline)
Any code that shares the Host Ring 3 address space (equivalent to Guest
Ring 0)
Gvisor


VMs and threads as part of an MCP
Ring V
Kernel (Ring 0)
Ring 3
Ring V
Ring 3
Ring V
Ring 3
Ring V
Ring 3
Ring V
Ring 3
Single Akaros Process, which owns cores, and runs threads. Some threads run
in Ring 3 (normal user mode) and some run in Ring V (VMX mode). They can
flip modes, i.e., a thread can alternate between Ring 3 and Ring V.  They
share an address space, and can communicate through memory or virtio.

Process address space (x86)
Ring 3 and Ring V share an address space
Ring V is limited to 2^46 bytes
If we are concerned about what’s in the VM we can use this limit
Run VMM starting at 2^46
Only leave stuff in the “low” memory that is for the guest
Currently due to gcc limits we also enforce only Ring 3 can access to low
16 MiB (save for first 1 MiB -- 8086 XXX)
Ring 3 address space -- 2^47 bytes
Ring V address space -- enforced to a measly 2^46 bytes
Forbidden to VMs
Shared between Ring 3 and Ring V
Here is first riscv question

We integrate VM Threads tightly into the kernel
Paging
Page table pages become double-wide (x86-specific, more on this later)
Entering the kernel
Previously, there’s only IRQs, Traps, SYSENTER/SYSCALL
Added a handler for VMEXIT, treat it like a fault
Return to user, whether VM or Ring 3
OS knew how to run a “context” for IRQs/Traps or SYSENTER
Added a handler to run a “VM context”
No arch-independent changes to scheduler or process management code
Added a user-level scheduler for VMs
Application specific scheduling, where the application is a VMM
454 lines

Paging in Linux for virtual machines
PML4
PML3
PML2
PML1
Process root (cr3)
EPT4
EPT3
EPT2
EPT1
Guest root
(EPT root)
Independent structures with their own locks, traversal functions,
allocators, and theme parks …



Akaros paging on x86
PML4
PML3
PML2
PML1
Process root (cr3)
EPT4
EPT3
EPT2
EPT1
Guest root
(EPT root)
Page table roots are paired, as are page table pages (PTP)
PTP are 2 * 4K pages
Process PTP is lower (“even”) 4k
VM PTP is upper (“odd”) 4k
Lower half is for thread in Ring 3
Upper half is for thread in Ring V
Threads can jump back and forth between those modes
VMM/VM duality
Code for VM page fault and process page fault is the same code
Can always see PTP for VM given a process, or process given a VM
EPT fault looks like a normal page fault, ugly details buried in HAL (not
much code)

Entering kernel from ring 3/ring V
The basic API is the same in each case
And utterly different from, say, /dev/kvm
In KVM, vmexit is the return value of an ioctl to start a vm
VMM is responsible for resolving the problem, changing VM state
In Akaros, vmexit is like any other case where ring 3 drops to ring 0 for
services
Ring 3: traps, system call, page fault
vmexits: vmcall, EPT fault, MSR access, IO, etc
Same style of handling in the kernel for vmexits as faults:
Kernel tries to resolve the fault without blocking (e.g. page fault, lookup
in page cache)
If the kernel fails, the faulting context is reflected to the user-level
scheduler (2LS)
For userspace, a VM fault is just another reflected fault


Running a ring 3 / ring V context
Akaros has three context types:
Hardware - involuntarily created during a trap/interrupt.  Think “every
register”
Software - voluntarily created during syscalls and user-level threading.
Think “AMD SYSV ABI”
VM - involuntarily created during vmexit.  Think “every register”, plus
exit info and guest_pcoreid
Returning to userspace (Ring 3 or Ring V) is always the same: proc_pop_ctx()
Whether or not we return to a VM or not is solely dependent on the type of
context
The kernel does maintain, per process, an array of guest physical cores
Various x86 accounting not related to the running context
VMCS, certain MSRs (STAR, LSTAR, SFMASK, KERNEL_GS_BASE), other fun stuff
Userspace knows how to run contexts too!
Simply build the context as part of a struct uthread and try to run it
But on x86, it asks the kernel to run VM contexts, since vmlaunch /
vmresume is privileged

Limitations
64-bit only
Very limited 16-bit and IO emulation
It’s dumb and fragile, deliberately
Because even vendors sometimes get it wrong: “After analyzing the problem,
it’s now clear what’s happening. As incredible as it is, Ryzen has buggy
VME implementation; specifically, the INT” --
http://www.os2museum.com/wp/vme-broken-on-amd-ryzen/
But there is some … essential for some ops and physical page 0 support
Paravirt only: for now the 10x boost for virtio devices is worth it

Hardware assumptions
We’re not supporting any pre-2012 hardware
Old hardware support in, e.g., KVM makes it messy, as does their
evolutionary approach
X2APIC (and hence IOMMU)
There are three flavors of APIC virtualization and we use the one that works
That was fun … since you have to enable all three to make the good one work
Require ability to support vmexit-free interrupt injection
Add additional pages to VMCS
Fun: VMCS has a size field which I’m willing to bet will always be “4k”
So they have to add pointers to the VMCS to point to other pages
The big goal is zero vmexits

Reducing VMExits
VMExits are costly.
399 nsec per loop in kernel without vmcs unload
930 nsec per loop in kernel with vmcs unload
1766 nsec per loop to userspace without vmcs unload
Some sources of VMExits:
Device interrupts
Inter-Processor Interrupts (IPIs)
IO
Faults

Intel VM interrupts
Virtualize APIC accesses VS APIC-register Virtualization: not the same
thing.
Posted Interrupts
Allows for injection of interrupts into the guest without exiting
Requires at least EOI virtualization to not exit
Host sets a bit corresponding to the target vector in the PIR page, and
sends the Posted-interrupt notification vector as an IPI
Fun fact
The “process posted interrupts” VM-execution control requires the
“external-interrupt exiting” VM-execution control

Example: Local APIC Timer
Guest OS
MSR exit handler
MSR write to Timer Vector, Initial Count, Divide configuration register
causes exit
Timer Thread
If all required variables have been initialized:
Start a timer thread that sleeps for required time
Guest Core resumes execution after handler completes.
Core 0
Core 1
Set vector bit in PIR page and send IPI to Core 0

SMP Guest Startup



Virtual Machine AP core startup
/* Start up secondary core. */
vm_tf_ap = gth_to_vmtf(vm->gths[cur_pcores]);

/* Set CR3 */
vm_tf_ap->tf_cr3 = vm_tf->tf_cr3;

/* Starting RIP is passed in via rdi. */
vm_tf_ap->tf_rip = vm_tf->tf_rdi;

/* Starting RSP is passed in via rsi. */
vm_tf_ap->tf_rsp = vm_tf->tf_rsi;

vm->up_gpcs++;

start_guest_thread(vm->gths[cur_pcores]);



VMCALL smpboot handler
/* AKAROS VMCALL SMP */
__asm__  __volatile__(
"movq $2, %%rax\n”
“movq $secondary_startup_64, %%rdi\n”
“movq %0, %%rsi\n”
“vmcall\n"
:  : "m"(stack_start)  : "rax", "rdi", "rsi");




Summary
Akaros VMs are unlike any other VMs
Threads can easily switch from being a VM to being a host thread
We invented a new user mode, Ring V
A VM is a thread in Ring V
When a VM Thread is in Ring V, it can run as Guest Ring 0 or Guest Ring 3
Can manage its own page tables, interrupt tables, etc.
Shares memory with Host Ring 3 - easy virtio communication via shared mem!
In most ways, thread programming models can be used
Kernels also look like threads and spinning up a core looks like CPU
hotplug, accomplished by spinning up a vthread with IP at the 64-bit entry
point

Summary
Akaros VMs are nothing like existing kernels
We were able to tightly integrate VMs into process model
It’s not a configuration option
Did not need to add it as a device

go/akaros-vmm


Big picture -- example for 5 threads
Threads can see thread and VM memory
VMs only see their own memory
VMs have a Linux kernel and a single app (potentially containing many
processes)
VM
Thread
VM
VM
Thread
VM
VM
Thread

Question: can we create two barriers

Security barriers: One
Process virtual memory -- all guest requests are handled here, not in
kernel.
Addresses unavailable to the guest -- hardware limitation
Guest physical memory
Process virtual memory used only for the guest
“EPT” range
(2^46)
Memory above “EPT” range (2^53-2^46)