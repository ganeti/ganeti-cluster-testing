#!/bin/bash

PIDFILE="/run/ganeti-cluster-testing.pid"
CLUSTERTYPE=""
DEBIANRELEASE="stable"
GANETIVERSION="latest"
LOGBASE="/var/log/ganeti-cluster-testing/"
LOGPATH=${LOGBASE}

usage() {
	echo "This script sets up an environment to test different ganeti cluster configurations"
	echo
	echo "Parameters:"
	echo
	echo "-c [clustertype]	Type of cluster to create (see below)"
	echo "-r [releasename]  Debian release to use (default: stable)"
	echo "-g [version]      Version of the Ganeti Debian packages to install"
	echo "                  When this parameter is set, the playbooks try to"
	echo "                  force-install this version of the Ganeti Debian packages"
	echo "                  If unset, it will just use the latest version available"
	echo "-l [path]		Base directory for logging (default: /var/log/ganeti-cluster-testing)"
	echo
	echo "Currently known cluster types:"
	echo " kvm-drbd-bridged"
	echo
	exit 1
}

echoAndLog() {
	logLine=$@
	echo "${logLine}" | tee -a "${LOGPATH}/main.log"
}

checkLock() {
	if ! [ -f ${PIDFILE} ]; then
		return 0
	else
		FOUNDPID=$(cat ${PIDFILE}|grep -oE "[0-9]+")
		if [ -z "${FOUNDPID}" ]; then
			echoAndLog "* Found lockfile with invalid content, removed"
			rm ${PIDFILE}
			return 0
		else
			if [ -d "/proc/${FOUNDPID}" ]; then
				echoAndLog "* This script is already running as PID ${FOUNDPID}"
				return 1
			else
				rm ${PIDFILE}
				echoAndLog "* Found stale lock file, removed"
				return 0
			fi
		fi
	fi
}

acquireLock() {
	if echo $$ > ${PIDFILE}; then
		echoAndLog "* Successfully acquired lock"
		return 0
	else
		echoAndLog "* Failed to acquire lock"
		return 1
	fi
}

cleanupLock() {
	rm ${PIDFILE}
	echoAndLog "* Released lock"
}

killVms() {
	echoAndLog "* Destroying all running VMs (if any)..."
	echoAndLog
	for dom in $(virsh --quiet list --all|grep running | awk '{ print $2 }'); do
		virsh destroy "${dom}"
	done
	echoAndLog
	echoAndLog "* Finished destroying VMs"
	echoAndLog
}

createVms() {
	numVMs=$1
	echoAndLog "* Creating VM images..."
	echoAndLog
	if [ ! -f "/root/.ssh/id_rsa_ganeti_testing.pub" ]; then
		echoAndLog "* There is no SSH key yet for VM communication - creating one..."
		echoAndLog
		ssh-keygen -b 2048 -f /root/.ssh/id_rsa_ganeti_testing -q -N ""
	fi
	for i in `seq 1 ${numVMs}`; do
		./create-image.sh -H gnt-test0${i} -r ${DEBIANRELEASE} -m "192.168.122.1:3142" -i 192.168.122.1${i} -n 255.255.255.0 -g 192.168.122.1 -s 27G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test0${i}.img -l ${LOGPATH} -f 
	done
	echoAndLog
	echoAndLog "* Finished creating VM images"
	echoAndLog
}

bootVms() {
	numVMs=$1
	TMPFILE=$(mktemp)
	echoAndLog "* Creating / booting VMs"
	echoAndLog
	for i in `seq 1 ${numVMs}`; do
		sed "s/__VM_NAME__/gnt-test0${i}/" vm-template.xml > $TMPFILE
		virsh create ${TMPFILE} | tee -a "${LOGPATH}/main.log"
	done
	rm $TMPFILE
	echoAndLog "* Finished creating / booting VMs"
	echoAndLog
}

runPlaybook() {
	play=$1
	echoAndLog "* Prepare VMs/initialise ganeti cluster"
	if ! ansible-playbook -i inventory ${play}.yml -e ganeti_version=${GANETIVERSION} | tee -a "${LOGPATH}/ansible-cluster-setup.log"; then
		echoAndLog "* Preparing the VMs/initialising ganeti cluster failed"
		exit 1
	fi

}

runQaScript() {
    recipe=$1
    tmpkey=$(mktemp)
    cp roles/ganeti/files/ssh_private_key "${tmpkey}"
    chmod 600 "${tmpkey}"
    scp -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" qa-configs/${recipe}.json 192.168.122.11:/tmp/
    ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" -t 192.168.122.11 "export PYTHONPATH=\"/usr/share/ganeti/default\"; cd /usr/share/ganeti/testsuite/qa; ./ganeti-qa.py --yes-do-it /tmp/${recipe}.json" | tee "${LOGPATH}/qa-script.output"
    qaScriptReturnCode=$?
    scp -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" 192.168.122.11:/var/log/ganeti/qa-output.log "${LOGPATH}/qa-script.log
    "rm "${tmpkey}"
    return $qaScriptReturnCode
}

while getopts "hc:r:g:" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		c)
			CLUSTERTYPE=$OPTARG
			;;
		r)
			DEBIANRELEASE=$OPTARG
			;;
		g)
			GANETIVERSION=$OPTARG
			;;
	esac
done

if [ -z "$CLUSTERTYPE" ]; then
	echoAndLog "Please specify cluster type to build/test"
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

LOGPATH=${LOGBASE}/${CLUSTERTYPE}/$(date --utc +%F_%H-%M-%S)/
mkdir -p "${LOGPATH}"

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
QA_RESULT=$(runQaScript $CLUSTERTYPE)
SCRIPT_FINISH_QA=`date +%s`

SCRIPT_VMS_RUNTIME=$((SCRIPT_FINISH_VMS - SCRIPT_START_VMS))
SCRIPT_VMS_RUNTIME_M=$((SCRIPT_VMS_RUNTIME / 60))

SCRIPT_QA_RUNTIME=$((SCRIPT_FINISH_QA - SCRIPT_START_QA))
SCRIPT_QA_RUNTIME_M=$((SCRIPT_QA_RUNTIME / 60))

echoAndLog "* Script execution time (VM building): ${SCRIPT_VMS_RUNTIME}s (~${SCRIPT_VMS_RUNTIME_M}m)"
echoAndLog "* Script execution time (QA scripts): ${SCRIPT_QA_RUNTIME}s (~${SCRIPT_QA_RUNTIME_M}m)"

cleanupLock

exit $QA_RESULT
