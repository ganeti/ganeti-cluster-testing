#!/bin/sh
# Custom PID 1 for the ganeti QA guest initramfs.
#
# Ganeti's kvm hypervisor appends root=/dev/vda1 to the kernel cmdline
# automatically, but the QA instances' virtio disks are unformatted, so
# /dev/vda1 never appears and dracut's stock /init sits forever in
# initqueue. To avoid that, we boot the kernel with rdinit=/sbin/qa-init —
# rdinit= (not init=) is the knob that picks an alternative PID 1 inside
# the initramfs — and take over directly: mount the basic pseudo-
# filesystems and start acpid (so qemu's system_powerdown ACPI event
# triggers a clean SysRq-poweroff).
#
# Note: we deliberately do NOT start udev. The Ganeti QA hotplug test
# only checks QEMU-side state and never uses hot-added devices from
# inside the guest; leaving them with no class driver bound is what
# lets ACPI hot-unplug on pc-i440fx-* finish within ganeti's
# verification budget (see module-setup.sh installkernel()).

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc     -o nosuid,nodev,noexec proc     /proc
mount -t sysfs    -o nosuid,nodev,noexec sysfs    /sys
mount -t devtmpfs -o nosuid,mode=0755    devtmpfs /dev
mkdir -p /dev/pts /run
mount -t devpts -o nosuid,noexec,gid=5,mode=0620 devpts /dev/pts
mount -t tmpfs  -o nosuid,nodev,mode=0755        tmpfs  /run

echo "ganeti-qa: qa-init starting" > /dev/kmsg

# Load drivers for the devices Ganeti wires up at instance start. We
# explicitly modprobe these (instead of letting udev autoload via
# modalias) because we deliberately do not run udev — see the rationale
# in module-setup.sh installkernel().
modprobe virtio_pci
modprobe virtio_balloon
modprobe virtio_console

acpid -f -l /dev/null </dev/null >/dev/null 2>&1 &
echo "ganeti-qa: acpid pid=$!" > /dev/kmsg

# PID 1 must never exit (kernel panics otherwise).
while :; do
	sleep 86400
done
