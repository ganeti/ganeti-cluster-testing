#!/bin/bash

set -e -u
tmp="$(mktemp -d)"
mkdir --parents ${tmp}/{bin,dev/input,etc/acpi/PWRF,lib,lib64,proc,root,sbin,sys,usr/bin,usr/sbin,modules}

echo '#!/bin/busybox sh
poweroff -f' > ${tmp}/etc/acpi/PWRF/00000080

chmod +x ${tmp}/etc/acpi/PWRF/00000080
cp --archive /dev/{null,console,tty} ${tmp}/dev/
cp --archive /dev/input/event* ${tmp}/dev/input
cp --archive /bin/busybox ${tmp}/bin/

for MODULE in $(find /lib/modules -name 'button.ko' -or -name 'evdev.ko'); do
	cp $MODULE ${tmp}/modules/;
done

echo '#!/bin/busybox sh
/bin/busybox --install 
mount -t proc none /proc
mount -t sysfs none /sys
insmod /modules/button.ko
insmod /modules/evdev.ko
acpid -d' > ${tmp}/init

chmod +x ${tmp}/init
cd ${tmp}
find . -print0 | cpio --null --create --verbose --format=newc | gzip --best > /boot/ganeti_busybox_initrd
cd -
rm -rf ${tmp}
