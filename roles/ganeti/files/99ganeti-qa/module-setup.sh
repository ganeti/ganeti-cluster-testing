#!/bin/bash
# Dracut module for the Ganeti QA guest initramfs.
#
# Produces an initramfs that boots, lets udev autoload virtio + PCIe hotplug
# drivers, starts acpid to handle power-button events, and then blocks forever
# (the QA instance has no root filesystem to pivot onto).

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
	inst_multiple acpid sleep

	inst_simple "$moddir/acpi-power.conf" "/etc/acpi/events/power"
	inst_simple "$moddir/acpi-handler.sh" "/etc/acpi/handler.sh"

	# These guests are booted without a root= kernel arg, so dracut's normal
	# pipeline stalls in initqueue waiting for a root device that never
	# appears. Install the stay-hook in both pre-mount (in case initqueue
	# settles anyway) and emergency (the path dracut takes once it gives up
	# looking for root). Whichever fires first wins; the other is a no-op
	# because the script blocks forever.
	inst_hook pre-mount 99 "$moddir/ganeti-qa-stay.sh"
	inst_hook emergency 99 "$moddir/ganeti-qa-stay.sh"
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
