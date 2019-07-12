#!/bin/bash

TMPFILE=$(mktemp)
CLUSTERTYPE=""

usage() {
	echo "This script sets up an environment to test different ganeti cluster configurations"
	echo
	echo "Parameters:"
	echo
	echo "-c [clustertype]	Type of cluster to create (see below)"
	echo
	echo "Currently known cluster types:"
	echo " kvm-drbd-bridged"
	echo
	exit 1
}



killVms() {
	echo "* Destroying all running VMs (if any)..."
	echo
	for dom in $(virsh --quiet list --all|grep running | awk '{ print $2 }'); do
		virsh destroy "${dom}"
	done
	echo
	echo "* Finished destroying VMs"
	echo
}

createVms() {
	numVMs=$1
	echo "* Creating VM images..."
	echo
	for i in `seq 1 ${numVMs}`; do
		./create-image.sh -H gnt-test0${i} -m "192.168.122.1:3142" -i 192.168.122.1${i} -n 255.255.255.0 -g 192.168.122.1 -s 27G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test0${i}.img -f
	done
	echo
	echo "* Finished creating VM images"
	echo
}

bootVms() {
	numVMs=$1
	echo "* Creating / booting VMs"
	echo
	for i in `seq 1 ${numVMs}`; do
		sed "s/__VM_NAME__/gnt-test0${i}/" vm-template.xml > $TMPFILE
		virsh create ${TMPFILE}
	done
	echo "* Finished creating / booting VMs"
	echo
}

runPlaybook() {
	play=$1
	echo "* Prepare VMs/initialise ganeti cluster"
	ansible-playbook -i inventory ${play}.yml
}

while getopts "hc:" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		c)
			CLUSTERTYPE=$OPTARG
			;;
	esac
done

if [ -z "$CLUSTERTYPE" ]; then
	echo "Please specify cluster type to build/test"
	exit 1
fi

case $CLUSTERTYPE in
	kvm-drbd-bridged)
		NUMBER_OF_VMS=3
		;;
	*)
		echo "Unknown/unsupported cluster type '${CLUSTERTYPE}'"
		exit 1
		;;
esac

killVms
createVms 3
bootVms 3
runPlaybook $CLUSTERTYPE


