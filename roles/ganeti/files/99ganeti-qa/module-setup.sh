#!/bin/bash
# Dracut module for the Ganeti QA guest initramfs.
#
# Produces an initramfs that lets udev autoload virtio + PCIe hotplug
# drivers and starts acpid to handle power-button events. The actual PID 1
# is our own /sbin/qa-init (selected via init=/sbin/qa-init on the kernel
# cmdline), not dracut's stock /init — see qa-init.sh for the reasoning.

check() {
	require_binaries acpid || return 1
	return 0
}

depends() {
	# base: dracut's minimal init + busybox-style utilities
	# udev-rules: real udev with the standard module-autoload + hotplug rules
	echo "base udev-rules"
	return 0
}

install() {
	inst_multiple acpid sleep mount mkdir udevadm

	inst_simple "$moddir/acpi-power.conf" "/etc/acpi/events/power"
	inst_simple "$moddir/acpi-handler.sh" "/etc/acpi/handler.sh"

	# Our replacement PID 1. The QA cluster boots its instances with
	# init=/sbin/qa-init so dracut's stock pipeline (which would stall in
	# initqueue waiting for a non-existent root device) is bypassed.
	inst_simple "$moddir/qa-init.sh" "/sbin/qa-init"
}

installkernel() {
	# Q35 PCIe / ACPI hotplug controllers — without these, hot-added NICs and
	# disks never get a slot to bind to.
	instmods pciehp acpiphp shpchp

	# Power button + input event delivery so acpid sees the shutdown event.
	instmods button evdev

	# Virtio transport + common device drivers.
	instmods virtio_pci virtio_blk virtio_net virtio_scsi
	instmods virtio_balloon virtio_console virtio_rng

	# Xen PV guest drivers (Xen-PVM recipe).
	instmods xen-evtchn xen-acpi-processor || :
}
