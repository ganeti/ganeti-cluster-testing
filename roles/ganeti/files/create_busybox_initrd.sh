#!/bin/bash

set -e -u
tmp="$(mktemp -d)"
mkdir --parents ${tmp}/{bin,dev/input,etc/acpi/PWRF,lib,lib64,proc,root,sbin,sys,usr/bin,usr/sbin,etc/init.d}

echo '#!/bin/busybox sh
poweroff -f' > ${tmp}/etc/acpi/PWRF/00000080

chmod +x ${tmp}/etc/acpi/PWRF/00000080
cp --archive /dev/{null,console,tty} ${tmp}/dev/
cp --archive /dev/input/event* ${tmp}/dev/input
cp --archive /bin/busybox ${tmp}/bin/

KERNEL=$(uname -r)
echo "Copying kernel modules from host (source version: ${KERNEL})"
mkdir -p "${tmp}/lib/modules/${KERNEL}"
for MODULE in $(find "/lib/modules/${KERNEL}" -name 'button.ko' -or -name 'evdev.ko' -or -name '*xen*.ko'); do
	cp --parents $MODULE "${tmp}";
done
cp "/lib/modules/${KERNEL}/modules.dep" "${tmp}/lib/modules/${KERNEL}/"
echo

chroot ${tmp} /bin/busybox --install

cat << EOF > ${tmp}/etc/inittab
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/sh
tty2::askfirst:-/bin/sh
tty3::askfirst:-/bin/sh
tty4::askfirst:-/bin/sh
tty4::respawn:/sbin/getty 38400 tty5
tty5::respawn:/sbin/getty 38400 tty6
::restart:/sbin/init
::ctrlaltdel:/sbin/reboot
EOF

cat << EOF > ${tmp}/etc/init.d/rcS
#!/bin/busybox sh
mount -t proc none /proc
mount -t sysfs none /sys
modprobe button
modprobe evdev
modprobe xen-evtchn
modprobe xen-acpi-processor
acpid -d &
EOF

chmod +x ${tmp}/etc/init.d/rcS

ln ${tmp}/sbin/init ${tmp}/init

cd ${tmp}
find . -print0 | cpio --null --create --format=newc | gzip --best > /tmp/debian-buster-initramfs
cd -
rm -rf ${tmp}
