#!/bin/bash

NET_NAME=auto-vm
DEBIANVERSION=stable
DEBOOTSTRAP_PATH=$(mktemp -d debootstrap.XXXXX)
QCOW_IMG_PATH=""
QCOW_IMG_SIZE=2G
FORCE_OVERWRITE=false
AUTHORIZED_KEY=false
DEB_MIRROR="127.0.0.1:3142"
NET_IP=dhcp
DEFAULT_PACKAGES="less,vim,sudo,openssh-server,acpid,man-db,curl,haveged,python,python3"

usage() {
	echo "This script prepares a qcow2 image with a debian installation"
	echo "You should run an apt-cacher-ng on localhost to speed up things"
	echo
	echo "Parameters:"
	echo
	echo "-p [path]		Absolute path/filename of the qemu image to create"
	echo "-f		Force overwriting the qemu image if it exists"
	echo "-H [string]	Hostname of the VM (default: auto-vm)"
	echo "-i [ip]		IP address of the VM (default: dhcp)"
	echo "-n [netmask]	Netmask of the VM (default: dhcp)"
	echo "-g [ip]		Gateway of the VM (default: dhcp)"
	echo "-s [int]M|G|T	Maximum size of the qcow2 image (default: 2G)"
	echo "-r [string]	Debian release to install (default: stable)"
	echo "-m [ip]:[port]	IP/Port of the Debian mirror/proxy (default: 127.0.0.1:3142)"
	echo "-a [string]	Install authorized key from given file into /root/.sshd/authorized_keys"
	echo
	exit 1
}

cleanup() {
	# the great cleanup
	chroot ${DEBOOTSTRAP_PATH} umount /proc/ /sys/ /dev/
	sleep 1
	umount ${DEBOOTSTRAP_PATH}
	sleep 1
	qemu-nbd -d /dev/nbd0
	sleep 1
	rmmod nbd
	rm -rf ${DEBOOTSTRAP_PATH}
}

while getopts "hfp:i:n:g:s:r:H:a:m:" opt; do
	case $opt in
		h)
			usage
			exit 0
			;;
		f)
			FORCE_OVERWRITE="true"
			;;
		p)
			QCOW_IMG_PATH=$OPTARG
			;;
		H)
			NET_NAME=$OPTARG
			;;
		i)
			NET_IP=$OPTARG
			;;
		n)
			NET_MASK=$OPTARG
			;;
		g)
			NET_GW=$OPTARG
			;;
		s)
			QCOW_IMG_SIZE=$OPTARG
			;;
		r)
			DEBIANVERSION=$OPTARG
			;;
		a)
			AUTHORIZED_KEY=$OPTARG
			;;
		m)
			DEB_MIRROR=$OPTARG
			;;
	esac
done

if [ -z "$QCOW_IMG_PATH" ]; then
	echo "Error: please provide the path to the qemu image (-p /path/to/vm.img)"
	exit 1
fi

if [ -f "$QCOW_IMG_PATH" ]; then
	if ! [ "$FORCE_OVERWRITE" = "true" ]; then
		echo "Error: Destination file already exists. Please use -f to force overwrite"
		exit 1
	fi
fi

if [ -z "$DEBOOTSTRAP_PATH" ]; then
	echo "Error: Could not create temp directory for debootstrap"
	exit 1
fi

# preperations
if ! modprobe nbd; then
	echo "Error: Could not load nbd module (required for qemu-nbd)"
	exit 1
fi

rm -f "${QCOW_IMG_PATH}"

LOGFILE=$(mktemp ${NET_NAME}.XXXXX)
echo "Logging the process to ${LOGFILE}"

# create and mount the image
set -e
qemu-img create -f qcow2 ${QCOW_IMG_PATH} ${QCOW_IMG_SIZE} &>> ${LOGFILE}
qemu-nbd -c /dev/nbd0 ${QCOW_IMG_PATH} &>> ${LOGFILE}
# TODO: find best partition alignments (remove -s param to see parted error message)
parted -s /dev/nbd0 mktable msdos &>> ${LOGFILE}
parted -s /dev/nbd0 mkpart primary 0% 1024MB &>> ${LOGFILE}
parted -s /dev/nbd0 mkpart primary 1026MB 4096MB &>> ${LOGFILE}
parted -s /dev/nbd0 mkpart primary 4098MB 100% &>> ${LOGFILE}
mkswap /dev/nbd0p1 &>> ${LOGFILE}
mkfs.ext4 /dev/nbd0p2 &>> ${LOGFILE}
mount /dev/nbd0p2 ${DEBOOTSTRAP_PATH} &>> ${LOGFILE}
set +e

# install debian
echo "Running debootstrap on ${DEBOOTSTRAP_PATH}"
if ! debootstrap --include=${DEFAULT_PACKAGES} ${DEBIANVERSION} ${DEBOOTSTRAP_PATH} http://${DEB_MIRROR}/debian &>> ${LOGFILE}; then
	echo "failed... cleaning up"
	cleanup
fi

# configure stuff
echo "Adding base/network configuration to the chroot"
cat <<EOF > ${DEBOOTSTRAP_PATH}/etc/fstab
/dev/vda2  /     ext4   errors=remount-ro 0 1
/dev/vda1  none  swap   sw  0 0
EOF

echo ${NET_NAME} > ${DEBOOTSTRAP_PATH}/etc/hostname

cat <<EOF > ${DEBOOTSTRAP_PATH}/etc/hosts
127.0.0.1       localhost
${NET_IP}       ${NET_NAME}
# The following lines are desirable for IPv6 capable hosts
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

if [ "$NET_IP" = "dhcp" ]; then
	cat <<EOF > ${DEBOOTSTRAP_PATH}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

source /etc/network/interfaces.d/*.conf
EOF
else
	cat <<EOF > ${DEBOOTSTRAP_PATH}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address ${NET_IP}
	netmask ${NET_MASK}
	gateway ${NET_GW}

source /etc/network/interfaces.d/*.conf
EOF
fi

sed -i "s/#PermitRootLogin.\+/PermitRootLogin Yes/" "${DEBOOTSTRAP_PATH}/etc/ssh/sshd_config" 

if ! [ "${AUTHORIZED_KEY}" = "false" ]; then
	echo "Installing authorized SSH public key for user root"
	mkdir "${DEBOOTSTRAP_PATH}/root/.ssh/"
	cp "${AUTHORIZED_KEY}" "${DEBOOTSTRAP_PATH}/root/.ssh/authorized_keys"
	chmod 600 "${DEBOOTSTRAP_PATH}/root/.ssh/authorized_keys"
fi


# install grub
set -e
echo "Installing kernel & grub"
mount --bind /dev/ ${DEBOOTSTRAP_PATH}/dev  &>> ${LOGFILE}
chroot ${DEBOOTSTRAP_PATH} mount -t proc none /proc &>> ${LOGFILE}
chroot ${DEBOOTSTRAP_PATH} mount -t sysfs none /sys &>> ${LOGFILE}
echo root:root | chroot ${DEBOOTSTRAP_PATH} chpasswd &>> ${LOGFILE}
LANG=C DEBIAN_FRONTEND=noninteractive chroot ${DEBOOTSTRAP_PATH} apt-get install -y --force-yes -q linux-image-amd64 grub-pc &>> ${LOGFILE}
sed -i "s|^GRUB_CMDLINE_LINUX=.\+|GRUB_CMDLINE_LINUX='net.ifnames=0 biosdevname=0'|" ${DEBOOTSTRAP_PATH}/etc/default/grub &>> ${LOGFILE} 
chroot ${DEBOOTSTRAP_PATH} grub-install /dev/nbd0 &>> ${LOGFILE}
chroot ${DEBOOTSTRAP_PATH} update-grub &>> ${LOGFILE}
chroot ${DEBOOTSTRAP_PATH} apt-get clean &>> ${LOGFILE}

sed -i "s|/dev/nbd0p2|/dev/vda2|g" ${DEBOOTSTRAP_PATH}/boot/grub/grub.cfg &>> ${LOGFILE}
grub-install /dev/nbd0 --root-directory=${DEBOOTSTRAP_PATH} --modules="biosdisk part_msdos" &>> ${LOGFILE}
set +e

echo "Cleaning up"
cleanup

chown libvirt-qemu:libvirt-qemu "${QCOW_IMG_PATH}"

echo "done. You can find your new VM image here: ${QCOW_IMG_PATH}"


