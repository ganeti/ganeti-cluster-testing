= Ganeti Test Environment =

These scripts and Ansible playbooks/roles allow you to setup a N-node Ganeti cluster for testing purposes. It uses libvirt/KVM as a virtualisiation layer, qemu-utils, debootstrap and apt-cacher-ng to setup VMs and Ansible to provision different kinds of Ganeti clusters. As of now it supports creating these cluster types:
- DRBD disks, bridged networking, fully virtualised KVM instances (e.g. running their own kernel)

Todo-Cluster-Types:
- DRBD disks with different variants of networking and/or different OS providers
- flatfile / shared file clusters
- other hypervisors (as long as they are usable within KVM)
- you name it

