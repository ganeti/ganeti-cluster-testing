# Ganeti Test Environment

These scripts and Ansible playbooks/roles allow you to setup a N-node Ganeti cluster for testing purposes. It uses libvirt/KVM as a virtualisiation layer, qemu-utils, debootstrap and apt-cacher-ng to setup VMs and Ansible to provision different kinds of Ganeti clusters. As of now it supports creating these cluster types:
- DRBD disks, bridged networking, fully virtualised KVM instances (e.g. running their own kernel)

## How to use

- install/configure all required dependencies:
  - libvirt-clients
  - libvirt-daemon-system
  - qemu-kvm
  - netcat-openbsd
  - dnsmasq
  - debootstrap
  - parted
  - qemu-utils
  - apt-cacher-ng
  - ansible
- run the bash script to kick of the build process: `run-cluster-test.sh -c [your-cluster-scenario]` This will create the required VMs, boot them and also kick of the Ansible playbook (named your-cluster-scenario.yml) to do the final setup and initialise the Ganeti cluster, add nodes etc.

## How to extend

If you want to create a new flavor of ganeti cluster setup (e.g. using a central shared storage or glusterfs) write a playbook, name it accordingly and extend the `run-cluster-test.sh` to support your new playbook (e.g. extend the usage() function, set the number of required VMs etc.). The current logic allows to create up to nine VMs (named gnt-test01...gnt-test09 with ip addresses 192.168.122.11..19). DNS resolution (via `/etc/hosts`) for inter-vm communication will be set up and an SSH public key will be added to allow for easy access from the management host.

## How fast is this?

It takes about 10 minutes to create the required VMs and setup a three-node Ganeti cluster with DRBD/KVM configured (but no instances) on an older Dell R610 with spinning disks (10k SAS RAID1). Things should look better on more recent hardware, especially with flash disks in place.

## TODOs

### Improvements
- better logging in shell scripts
- better error handling in shell scripts (traps etc.)
- better error recovery (detect/cleanup a previous failed run)
- [*done*] add locking (and stale lock detection)
- speed up the creation of N similar VMs (e.g. run debootstrap only once & duplicate images)
- [*done*] use a single shell script with parameters as an entry point (instead of one shell script & one playbook per cluster type) to avoid lots of duplicated code
- check if it's possible to run as non-root user

### Missing / New Features
- [*done*] build Ganeti test suite to run actual tests (check the ganeti repository, there's something already there)
- find a way to capture/save/provide the output/results of the build/test process
- find a way to provision operating systems on instances in the currently existing DRBD cluster scenario for actual tests

### Playbooks for other cluster types:
- DRBD disks with different variants of networking and/or different OS providers
- flatfile / shared file clusters
- other hypervisors (as long as they are usable within KVM)
- you name it

### Failing QA tests
Following is a list of tests from the ganeti QA testsuite which currently fail (possibly due to a broken test)
- cluster-modify: 'user-shutdown' test fails
- os: operation system definition tests fail on kvm-enabled hosts because it seems to assume xen and sets an invalid/non-existant kernel_path variable
- alternative SSH port: the tests run a few iptables commands to "fake" SSH running on a different port. something with these tests fails and needs to be investigated. Probably related to the current test environment and not to the test itself.
- instance export: needs more space on the root FS
- instance reinstall: does not work with the noop OS provider
- disk template 'plain': complains about to few spindles/PVs(?). need to understand how plain is exactly supposed to work and prepare/alter the test environment accordingly
- instance-remove-drbd-offline: test fails while setting the node back online. The command `gnt-node modify --offline no gnt-test02` comes back with an interactive question and suggests using --readd instead.
