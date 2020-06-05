# How to create a new Recipe (Test Scenario)

This document explains how to create a new recipe for Ganeti QA testing. First things first, here are some terms and definitions:

## Recipe

A recipe describes the whole test scenario and is distributed over several files which follow the same naming convention. The main parts are:
1. An Ansible playbook located in the top folder which is named `$recipe.yml`
2. A Ganeti QA suite configuration in the folder `qa-configs` which is named `$recipe.json`

## Files and Folders

### inventory

This folder belongs to Ansible and lists the available Ganeti test VMs. Currently we run all tests on three VMs which are reachable on the internal network as 192.168.122.11 - .13.

### roles

This folder belongs to Ansible and contains any roles which might be used to setup Ganeti nodes and related services such as DRBD, NFS etc. Try to group your tasks in roles focused on a specific topic so others might be able to re-use them in different recipes.

### qa-configs

The Ganeti QA suite runs off a JSON based configuration file which tells it what (and what not) to check. Each recipe has its own configuration using `$recipe.json`.

### create-image.sh

This is a helper script which creates and boots a QEMU VM using libvirt (yes, shame on me) and debootstrap. It takes a whole bunch of parameters, please use `-h` to get an overview. Usually you do not need to call this script directly.

### run-cluster-test.sh

This is the main entry point to run a QA test. It will take care of locking (currently the setup does not support parallel tests), setting up the VMs (VM creation and triggering Ansible), copy QA configuration into the VM, run the QA and also fetch and archive Ganeti logs from the VMs afterwards. These logs will be archived as job artifacts. The return code of this script will reflect the result of the QA suite.

# Create a new Recipe

## Choose a good Name

First of all, think of a good name that represents what actually happens/gets tested. You could use something like `$hypervisor-$disktype(s)-$networktype` (e.g. `kvm_drbd_openvswitch`). For our example, we will create an easy setup: three nodes, but using the `fake` hypervisor and `diskless`-type instances to get quick results. Hence we will use the name `fake_diskless_bridged`.

## Create an Ansible Playbook

We will start with an Ansible playbook named `fake_diskless_bridged.yml`. On each run, this will be used to setup the actual Ganeti cluster and everything required to test it:

```yaml
---

- hosts: ganeti_nodes
  user: root
  gather_facts: False
  tasks:
    - name: Wait for SSH
      local_action: "wait_for port=22 host={{ inventory_hostname }}"

- hosts: ganeti_nodes
  user: root
  roles:
    - bridge_networking
    - ganeti

- hosts: 192.168.122.11
  user: root
  tasks:
    - name: Initialise cluster
      command: "gnt-cluster init --master-netdev eth0 --master-netmask 24 --enabled-hypervisors fake --nic-parameters mode=bridged,link=virt-bridge --enabled-disk-templates=diskless --default-iallocator hail --ipolicy-bounds-specs min:nic-count=0,cpu-count=1,disk-count=0,spindle-use=0,disk-size=512M,memory-size=128M/max:nic-count=8,cpu-count=48,disk-count=8,spindle-use=8,disk-size=1TB,memory-size=1TB --ipolicy-disk-templates=diskless staging-cluster.ganeti.org"
    - name: Add node
      command: gnt-node add --no-ssh-key-check gnt-test02
    - name: Add node
      command: gnt-node add --no-ssh-key-check gnt-test03
    - name: Set valid XEN hypervisor parameters (the QA suite will fail with the default parameters)
      command: "gnt-cluster modify --hypervisor-parameters xen-pvm:kernel_path={{ ansible_cmdline.BOOT_IMAGE }},initrd_path=/boot/ganeti_busybox_initrd,kernel_args=init=/init"

```

This playbook will wait until all of the newly created VMs have finished booting (e.g. are offering the SSH service). After that, it will install/configure Ganeti through Debian Packages and setup bridged networking. Last but not least it will initialise the cluster on the first node and subsequently add the two other nodes.

## Create the QA Configuration

The Ganeti sources contain an [example QA configuration file](https://github.com/ganeti/ganeti/blob/master/qa/qa-sample.json). Save it as `qa-configs/fake_diskless_bridged.json` and start editing. Some of the tests are known to be broken in this environment for one reason or another, please refer to the [README.md](README.md) for more details. Please remember that the `JSON` format does **not** support comments. If you want to add some, use this form:

```json
{
    "# this is just a comment": null,
    "this-is-a-setting": true,
    "# this is also a comment": null
}
```

Since the cluster has already been created by Ansible, we should set `create-cluster` to `false` - but please make sure other information in the JSON matches your selected cluster configuration, e.g. `enabled-hypervisors`, `vg-name`, `name` and others.

## Run the Recipe

Once everything is in place, you can run your recipe:
```
./run-cluster-test.sh -c fake-diskless-bridged -f debian -r buster
```

## Testing & Building Playbooks

You can instruct the `run-cluster-test.sh` script to only (re-) build the VMs and trigger Ansible manually to build and test playbooks and roles:

```
./run-cluster-test.sh -c fake-diskless-bridged -f debian -r buster -b
ansible-playbook -i inventory fake-diskless-bridged.yml
```

You might need to pass some extra-variables to Ansible using `-e "name=value name=value ..."` if required by any roles. The `ganeti` role currently uses this to detect what kind of Ganeti Packages to install (or rather: from what source they should come).
