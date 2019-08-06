#!/bin/bash

PIDFILE="/run/ganeti-cluster-testing.pid"
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

checkLock() {
	if ! [ -f ${PIDFILE} ]; then
		return 0
	else
		FOUNDPID=$(cat ${PIDFILE}|grep -oE "[0-9]+")
		if [ -z "${FOUNDPID}" ]; then
			echo "* Found lockfile with invalid content, removed"
			rm ${PIDFILE}
			return 0
		else
			if [ -d "/proc/${FOUNDPID}" ]; then
				echo "* This script is already running as PID ${FOUNDPID}"
				return 1
			else
				rm ${PIDFILE}
				echo "* Found stale lock file, removed"
				return 0
			fi
		fi
	fi
}

acquireLock() {
	if echo $$ > ${PIDFILE}; then
		echo "* Successfully acquired lock"
		return 0
	else
		echo "* Failed to acquire lock"
		return 1
	fi
}

cleanupLock() {
	rm ${PIDFILE}
	echo "* Released lock"
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
	TMPFILE=$(mktemp)
	echo "* Creating / booting VMs"
	echo
	for i in `seq 1 ${numVMs}`; do
		sed "s/__VM_NAME__/gnt-test0${i}/" vm-template.xml > $TMPFILE
		virsh create ${TMPFILE}
	done
	rm $TMPFILE
	echo "* Finished creating / booting VMs"
	echo
}

runPlaybook() {
	play=$1
	echo "* Prepare VMs/initialise ganeti cluster"
	ansible-playbook -i inventory ${play}.yml
}

runQaScript() {
    recipe=$1
    tmpkey=$(mktemp)
    cp roles/ganeti/files/ssh_private_key "${tmpkey}"
    chmod 600 "${tmpkey}"
    scp -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" qa-configs/${recipe}.json 192.168.122.11:/tmp/
    ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" -t 192.168.122.11 "export PYTHONPATH=\"/usr/share/ganeti/default\"; cd /usr/share/ganeti/testsuite/qa; ./ganeti-qa.py --yes-do-it /tmp/${recipe}.json"
    rm "${tmpkey}"
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

if checkLock; then
	if ! acquireLock; then exit 1; fi
else
	exit 1
fi


killVms
SCRIPT_START_VMS=`date +%s`
createVms 3
bootVms 3
runPlaybook $CLUSTERTYPE
SCRIPT_FINISH_VMS=`date +%s`
SCRIPT_START_QA=`date +%s`
runQaScript $CLUSTERTYPE
SCRIPT_FINISH_QA=`date +%s`

SCRIPT_VMS_RUNTIME=$((SCRIPT_FINISH_VMS - SCRIPT_START_VMS))
SCRIPT_VMS_RUNTIME_M=$((SCRIPT_VMS_RUNTIME / 60))

SCRIPT_QA_RUNTIME=$((SCRIPT_FINISH_QA - SCRIPT_START_QA))
SCRIPT_QA_RUNTIME_M=$((SCRIPT_QA_RUNTIME / 60))

echo "* Script execution time (VM building): ${SCRIPT_VMS_RUNTIME}s (~${SCRIPT_VMS_RUNTIME_M}m)"
echo "* Script execution time (QA scripts): ${SCRIPT_QA_RUNTIME}s (~${SCRIPT_QA_RUNTIME_M}m)"

cleanupLock


