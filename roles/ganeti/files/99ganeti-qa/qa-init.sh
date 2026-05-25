#!/bin/sh
# Custom PID 1 for the ganeti QA guest initramfs.
#
# Ganeti's kvm hypervisor appends root=/dev/vda1 to the kernel cmdline
# automatically, but the QA instances' virtio disks are unformatted, so
# /dev/vda1 never appears and dracut's stock /init sits forever in
# initqueue. To avoid that, we boot the kernel with rdinit=/sbin/qa-init —
# rdinit= (not init=) is the knob that picks an alternative PID 1 inside
# the initramfs — and take over directly: mount the basic pseudo-
# filesystems, bring up udev (so PCIe hotplug still works during the QA
# test), and start acpid (so qemu's system_powerdown ACPI event triggers
# a clean SysRq-poweroff).
#
# We still rely on dracut to *populate* the initramfs (busybox, udevd, the
# kernel modules listed in module-setup.sh, acpid). This script just
# orchestrates them, replacing dracut's init pipeline entirely.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc     -o nosuid,nodev,noexec proc     /proc
mount -t sysfs    -o nosuid,nodev,noexec sysfs    /sys
mount -t devtmpfs -o nosuid,mode=0755    devtmpfs /dev
mkdir -p /dev/pts /run
mount -t devpts -o nosuid,noexec,gid=5,mode=0620 devpts /dev/pts
mount -t tmpfs  -o nosuid,nodev,mode=0755        tmpfs  /run

echo "ganeti-qa: qa-init starting" > /dev/kmsg

for mod in acpiphp pciehp shpchp; do
	modprobe "$mod" 2>/dev/null && \
		echo "ganeti-qa: loaded $mod" > /dev/kmsg
done

for udevd in /lib/systemd/systemd-udevd /usr/lib/systemd/systemd-udevd /sbin/udevd; do
	if [ -x "$udevd" ]; then
		"$udevd" --daemon
		break
	fi
done

udevadm trigger --type=subsystems --action=add
udevadm trigger --type=devices --action=add
udevadm settle --timeout=30

echo "ganeti-qa: udev settled, starting acpid" > /dev/kmsg

acpid -f -l /dev/null </dev/null >/dev/null 2>&1 &
echo "ganeti-qa: acpid pid=$!" > /dev/kmsg

# PID 1 must never exit (kernel panics otherwise).
while :; do
	sleep 86400
done
