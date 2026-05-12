#!/bin/sh
# Start acpid (in the background) so ACPI power-button events trigger a clean
# poweroff, then block this hook forever. udev keeps running in its own
# process, so hot-added PCIe devices still get bound.

acpid -d &

while :; do
	sleep 86400
done
