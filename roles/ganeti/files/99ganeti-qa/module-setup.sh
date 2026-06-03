#!/bin/bash
# Dracut module for the Ganeti QA guest initramfs.
#
# Produces a minimal initramfs that starts acpid to handle power-button
# events and then blocks forever. The actual PID 1 is our own
# /sbin/qa-init (selected via rdinit=/sbin/qa-init on the kernel cmdline),
# not dracut's stock /init — see qa-init.sh for the reasoning.
#
# Deliberately no udev and no virtio class drivers — see installkernel().

check() {
	require_binaries acpid || return 1
	return 0
}

depends() {
	# base only: dracut's minimal init + busybox-style utilities. We
	# explicitly do NOT pull udev-rules: we don't want udev autoloading
	# class drivers for hot-added PCI devices (see installkernel()).
	echo "base"
	return 0
}

install() {
	inst_multiple acpid sleep mount mkdir modprobe

	inst_simple "$moddir/acpi-power.conf" "/etc/acpi/events/power"
	inst_simple "$moddir/acpi-handler.sh" "/etc/acpi/handler.sh"

	# Our replacement PID 1. The QA cluster boots its instances with
	# rdinit=/sbin/qa-init so dracut's stock pipeline (which would stall
	# in initqueue waiting for the non-existent /dev/vda1 that ganeti
	# auto-appends as root=) is bypassed.
	inst_simple "$moddir/qa-init.sh" "/sbin/qa-init"
}

installkernel() {
	# PCI hotplug controllers. These are CONFIG_HOTPLUG_PCI_*=y on stock
	# Debian kernels so instmods is usually a no-op; list them for kernels
	# that ship them as modules.
	instmods acpiphp pciehp shpchp || :

	# Power button + input event delivery so acpid sees the shutdown event.
	instmods button evdev

	# Virtio bus transport + the always-present devices Ganeti wires up
	# at instance start (balloon, virtio-serial for the spice agent).
	# We deliberately do NOT install the class drivers for the devices
	# that the hotplug test adds and removes (virtio_net, virtio_blk,
	# virtio_scsi, virtio_rng): the Ganeti QA hotplug test only checks
	# QEMU-side state (query-pci before/after device_add/device_del)
	# and never uses the hot-added device from inside the guest. Leaving
	# it unbound makes ACPI hot-unplug on pc-i440fx-* complete in one
	# tick instead of racing against driver probe — the latter takes
	# >5s on linux 6.1 / qemu 7.2 and blows ganeti's hotplug
	# verification budget. This matches what the pre-dracut busybox
	# initrd did (only modprobe virtio_pci + virtio_balloon, no udev).
	instmods virtio_pci virtio_balloon virtio_console

	# Xen PV guest drivers (Xen-PVM recipe). Xen PV does not use ACPI
	# hotplug, so the "no class driver" reasoning above does not apply.
	instmods xen-evtchn xen-acpi-processor || :
}
