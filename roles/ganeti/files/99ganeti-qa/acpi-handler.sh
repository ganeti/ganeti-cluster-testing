#!/bin/sh
# Power off via the kernel SysRq interface — independent of which
# poweroff/reboot binaries (sysvinit, systemd shim, busybox) happen to be
# wired up in the dracut initramfs.

echo "ganeti-qa: acpi power-button event received" > /dev/kmsg
echo 1 > /proc/sys/kernel/sysrq
echo o > /proc/sysrq-trigger
