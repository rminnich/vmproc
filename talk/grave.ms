.SS "The Linux model
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
.SS "Virtualization model
.IT
For Akaros, we did not want anything like Linux/BSD approach
.IT
We ported five different VMs to Akaros while evaluating them
.IT
Gvisor, KVM, Dune, Bhyve, two others you never heard of
.IT
Then, one day, during a discussion, I noticed something
