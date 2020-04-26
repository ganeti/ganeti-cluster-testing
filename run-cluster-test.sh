#!/bin/bash

PIDFILE="/run/ganeti-cluster-testing.pid"
MODE="run_and_build"
CLUSTERTYPE=""
OS_FLAVOR="debian"
OS_RELEASE="stable"
ANSIBLE_PYTHON_INTERPRETER="/usr/bin/python3"
GANETIVERSION="latest"
LOGBASE="/var/log/ganeti-cluster-testing/"
LOGPATH=${LOGBASE}
MACHINETYPE="q35"

usage() {
	echo "This script sets up an environment to test different ganeti cluster configurations"
	echo
	echo "Parameters:"
	echo
	echo "-c [clustertype]  Type of cluster to create (see below)"
	echo "-f [osflavor]     Set the OS flavor to use (default: debian)"
	echo "-r [releasename]  OS release to use (default: stable)"
	echo "-g [version]      Version of the Ganeti Debian packages to install"
	echo "                  When this parameter is set, the playbooks try to"
	echo "                  force-install this version of the Ganeti Debian packages"
	echo "                  If unset, it will just use the latest version available"
	echo "-l [path]         Base directory for logging (default: /var/log/ganeti-cluster-testing)"
	echo "-b		Build-only mode - do not run any QA tests, just set up the cluster"
	echo "-p		Switch to legacy 'pc' machine type for QEMU/KVM (default: q35)"
	echo
	echo "Currently known cluster types:"
	echo " kvm-drbd_file_sharedfile-bridged"
	echo
	exit 1
}

prepareLogDirectory() {
	LOGPATH=${LOGBASE}/${CLUSTERTYPE}/$(date --utc +%F_%H-%M-%S)/
	mkdir -p "${LOGPATH}"
	rm -f "${LOGBASE}/${CLUSTERTYPE}/latest"
	ln -s "${LOGPATH}" "${LOGBASE}/${CLUSTERTYPE}/latest"
}

echoAndLog() {
	local logLine=$@
	echo "${logLine}" | tee -a "${LOGPATH}main.log"
}

checkTheForce() {
	if [[ $EUID -ne 0 ]]; then
		echo "This script must be run as root"
		exit 1
	fi
}

checkLock() {
	if ! [ -f ${PIDFILE} ]; then
		return 0
	else
		local FOUNDPID=$(cat ${PIDFILE}|grep -oE "[0-9]+")
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
	for dom in $(virsh --quiet list --all|grep -E "(running|shut off)" | awk '{ print $2 }'); do
		virsh destroy "${dom}"
	done
	echoAndLog
	echoAndLog "* Finished destroying VMs"
	echoAndLog
}

createVms() {
	local numVMs=$1
	echoAndLog "* Creating VM images..."
	echoAndLog
	if [ ! -f "/root/.ssh/id_rsa_ganeti_testing.pub" ]; then
		echoAndLog "* There is no SSH key yet for VM communication - creating one..."
		echoAndLog
		ssh-keygen -b 2048 -f /root/.ssh/id_rsa_ganeti_testing -q -N ""
	fi
	mkdir -p /tmp/create-image-cache
	for i in `seq 1 ${numVMs}`; do
		if [ -e /tmp/create-image-cache/${OS_FLAVOR}_${OS_RELEASE}_gnt-test0${i}.img -a "$(find /tmp/create-image-cache/${OS_FLAVOR}_${OS_RELEASE}_gnt-test0${i}.img -mmin -180 2>/dev/null)" ]; then
			echoAndLog "* Found a cached image in '/tmp/create-image-cache/${OS_FLAVOR}_${OS_RELEASE}_gnt-test0${i}.img' which is less than 180 minutes old, using this for now."
			cp /tmp/create-image-cache/${OS_FLAVOR}_${OS_RELEASE}_gnt-test0${i}.img /var/lib/libvirt/images/gnt-test0${i}.img
		else
			set -e
			./create-image.sh -H gnt-test0${i} -t ${OS_FLAVOR} -r ${OS_RELEASE} -m "192.168.122.1:3142" -i 192.168.122.1${i} -n 255.255.255.0 -g 192.168.122.1 -s 40G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test0${i}.img -l ${LOGPATH} -f
			set +e
			cp /var/lib/libvirt/images/gnt-test0${i}.img /tmp/create-image-cache/${OS_FLAVOR}_${OS_RELEASE}_gnt-test0${i}.img
		fi
	done
	echoAndLog
	echoAndLog "* Finished creating VM images"
	echoAndLog
}

bootVms() {
	local numVMs=$1
	local TMPFILE=$(mktemp)
	echoAndLog "* Creating / booting VMs"
	echoAndLog
	for i in `seq 1 ${numVMs}`; do
		sed "s/__VM_NAME__/gnt-test0${i}/" vm-template-${MACHINETYPE}.xml > ${TMPFILE}
		virsh create ${TMPFILE} | tee -a "${LOGPATH}main.log"
	done
	rm ${TMPFILE}
	echoAndLog "* Finished creating / booting VMs"
	echoAndLog
}

runPlaybook() {
	local play=$1
	echoAndLog "* Prepare VMs/initialise ganeti cluster"
	ansible-playbook -i inventory ${play}.yml -e "ganeti_version=${GANETIVERSION} target_release=${OS_RELEASE} ansible_python_interpreter=${ANSIBLE_PYTHON_INTERPRETER}" | tee -a "${LOGPATH}ansible-cluster-setup.log"
	if [ "${PIPESTATUS[0]}" -ne "0" ]; then
		echoAndLog "* Preparing the VMs/initialising ganeti cluster failed"
		exit 1
	fi

}

runQaScript() {
    local recipe=$1
    local tmpkey=$(mktemp)
    cp roles/ganeti/files/ssh_private_key "${tmpkey}"
    chmod 600 "${tmpkey}"
    scp -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" qa-configs/${recipe}.json 192.168.122.11:/tmp/
    ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" -t 192.168.122.11 "export PYTHONPATH=\"/usr/share/ganeti/testsuite/:/usr/share/ganeti/default\"; cd /usr/share/ganeti/testsuite/qa; ./ganeti-qa.py --yes-do-it /tmp/${recipe}.json"
    qaScriptReturnCode=$?
    scp -r -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i "${tmpkey}" 192.168.122.11:/var/log/ganeti "${LOGPATH}" > /dev/null
    chmod a+x "${LOGPATH}ganeti"
    chmod -R a+r "${LOGPATH}"
    rm "${tmpkey}"
    return $qaScriptReturnCode
}

while getopts "hbpc:f:r:g:" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		b)
			MODE="buildonly"
			;;
		c)
			CLUSTERTYPE=$OPTARG
			;;
		f)
			OS_FLAVOR=$OPTARG
			;;
		r)
			OS_RELEASE=$OPTARG
			;;
		g)
			GANETIVERSION=$OPTARG
			;;
		p)
			MACHINETYPE="pc"
			;;
	esac
done

checkTheForce

if [ -z "$CLUSTERTYPE" ]; then
	echoAndLog "Please specify cluster type to build/test"
	exit 1
fi

case $CLUSTERTYPE in
	kvm-drbd_file_sharedfile-bridged)
		NUMBER_OF_VMS=3
		;;
	*)
		echo "Unknown/unsupported cluster type '${CLUSTERTYPE}'"
		exit 1
		;;
esac

# use legacy ansible interpreter on older releases
case "$OS_RELEASE" in
	jessie|stretch|buster)
		ANSIBLE_PYTHON_INTERPRETER="/usr/bin/python"
		;;
	bionic|cosmic|disco|eoan)
		ANSIBLE_PYTHON_INTERPRETER="/usr/bin/python"
		;;
esac

prepareLogDirectory

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

if [ "$MODE" = "buildonly" ]; then
	echoAndLog "* Finished setting up the cluster. Exiting now as requested (build-only mode)"
	exit
fi

SCRIPT_FINISH_VMS=`date +%s`
SCRIPT_START_QA=`date +%s`
runQaScript $CLUSTERTYPE
QA_RESULT=$?
SCRIPT_FINISH_QA=`date +%s`

SCRIPT_VMS_RUNTIME=$((SCRIPT_FINISH_VMS - SCRIPT_START_VMS))
SCRIPT_VMS_RUNTIME_M=$((SCRIPT_VMS_RUNTIME / 60))

SCRIPT_QA_RUNTIME=$((SCRIPT_FINISH_QA - SCRIPT_START_QA))
SCRIPT_QA_RUNTIME_M=$((SCRIPT_QA_RUNTIME / 60))

echoAndLog "* Script execution time (VM building): ${SCRIPT_VMS_RUNTIME}s (~${SCRIPT_VMS_RUNTIME_M}m)"
echoAndLog "* Script execution time (QA scripts): ${SCRIPT_QA_RUNTIME}s (~${SCRIPT_QA_RUNTIME_M}m)"

cleanupLock

exit $QA_RESULT
