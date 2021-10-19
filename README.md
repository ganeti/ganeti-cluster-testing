# Ganeti Test Environment

This repository allows to run automated Ganeti tests using the built-in Ganeti QA suite directly off a given git repository/branch. It will create a three-node cluster with the following scenario:
- DRBD, file, plain and sharedfile (via NFS) storage options enabled
- QEMU/KVM or Xen PVM/HVM virtualisation
- simple instances which only boot a kernel with an initrd (which starts busybox-acpid to shutdown the instance on request)
- bridged networking

All interaction is done using the `run-cluster-test.py` script. Ganeti nodes will be created using the debootstrap OS provider.

## How to use

- A full Ganeti environment with a working debootstrap OS provider is required. Currently it runs on Ganeti 3.0.1 on Debian Bullseye.
- The `kvm_amd|kvm_intel` kernel module needs to be loaded with the `nested=1` parameter to allow for nested virtualisation.
- There are some third party tools in place to make the whole process smooth (dnsmasq, SSH CA, Ganeti hook scripts) - The entire setup can be re-created using [this repository](https://github.com/sipgate/ansible-ganeti-community-servers).
- Run the script to kick off the entire process:
```shell
python3 -u run-cluster-test.py run-test --os-version bullseye --recipe kvm-drbd_file_sharedfile-bridged --source rbott/ganeti --branch assess_hv_params
```
- This will run the test on three Debian Bullseye instances. Ganeti Nodes will be set up according to the playbook named `$recipe.yml` and the QA suite will be run according to `qa-configs/$recipe.json`.
- If instance creation, node setup or QA suite fail, the runner will return with an exit code > 0

## How to cleanup older runs

If you cannot start a new QA run due to insufficent resources (e.g. instances from previous tests have not been removed), you can enumerate previous test-runs and cleanup leftovers:
```shell
python3 -u run-cluster-test.py list-tests
Listing all instances grouped by tag
{'drunk-frink': ['bumble-bee-man.staging.ganeti.org', 'major-quimby.staging.ganeti.org', 'rod-flanders.staging.ganeti.org']}

python3 -u run-cluster-test.py remove-tests --tag drunk-frink
```

Please refer to [this manual](CREATE_NEW_RECIPE.md) to learn how to create your own recipes/testing scenarios.

## How to extend

If you need a different Ganeti environment (e.g. different storage or network options), create a new "recipe" (e.g. a playbook with new/reused roles and a QA config). 

## How fast is this?

The QA Suite usually takes around an hour to finish. Building/configuring of the Instances and Ganeti itself depends vastly on the hardware used and ranges between 5 and 10 minutes.

