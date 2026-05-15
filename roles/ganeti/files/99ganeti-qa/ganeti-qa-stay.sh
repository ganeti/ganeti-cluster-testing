#!/bin/sh
# Start acpid so qemu's system_powerdown (ACPI power button) reaches the
# SysRq-poweroff handler, then block forever. udev was started in
# pre-trigger and keeps running, so hot-added PCIe devices still get bound.
#
# The kmsg markers are diagnostic — they're the only way to see what
# happens inside the initramfs, because these guests have no console=
# kernel arg and dracut runs silently by default.

echo "ganeti-qa: stay hook reached" > /dev/kmsg

acpid -f -l /dev/null </dev/null >/dev/null 2>&1 &
echo "ganeti-qa: acpid started pid=$!" > /dev/kmsg

while :; do
	sleep 86400
done
