#!/bin/bash

TMPFILE=$(mktemp)

for dom in $(virsh --quiet list --all|grep running | awk '{ print $2 }'); do
	virsh destroy "${dom}"
done

echo "* Creating VM images..."
echo
./create-image.sh -H gnt-test01 -m "192.168.122.1:3142" -i 192.168.122.11 -n 255.255.255.0 -g 192.168.122.1 -s 27G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test01.img -f
./create-image.sh -H gnt-test02 -m "192.168.122.1:3142" -i 192.168.122.12 -n 255.255.255.0 -g 192.168.122.1 -s 27G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test02.img -f
./create-image.sh -H gnt-test03 -m "192.168.122.1:3142" -i 192.168.122.13 -n 255.255.255.0 -g 192.168.122.1 -s 27G -a /root/.ssh/id_rsa_ganeti_testing.pub -p /var/lib/libvirt/images/gnt-test03.img -f
echo
echo "* Finished creating VM images"
echo
echo

echo "* Creating / booting VMs"
echo
for dom in gnt-test01 gnt-test02 gnt-test03; do
	sed "s/__VM_NAME__/${dom}/" vm-template.xml > $TMPFILE
	virsh create ${TMPFILE}
done
echo "* Finished creating / booting VMs"
echo

echo "* Sleeping 10 seconds to let the VMs finish booting"
sleep 10
echo

echo "* Prepare VMs/initialise ganeti cluster"
ansible-playbook -i inventory ganeti-drbd-cluster.yml


