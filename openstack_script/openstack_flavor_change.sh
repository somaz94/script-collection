#!/bin/bash
 
set -x          # 해당 옵션은 선택입니다. error위치를 알 수 있습니다.
 
shopt -s expand_aliases
source ${HOME}/.bashrc
 
echo "Creating new flavor..."
FLAVOR_NAME_TEMP=$(openstack flavor list | grep default2 | awk '{print $4}')
if [ "x${FLAVOR_NAME_TEMP}" != "xdefault2" ]; then
        openstack flavor create --vcpu 4 --ram 8192 --disk 50 default2 --property=hw:cpu_max_sockets=1 --public
fi
echo "Done"
 
VM=$(openstack server list | grep default | awk '{print $2}')
COUNT=$(openstack server list | grep default | awk '{print $2}' | wc -l)
SL=$(($COUNT / 2))
SX=$(($COUNT * 4))
SF=$(($COUNT * 6))
CONFIRM=$(openstack server list | grep VERIFY_RESIZE | awk '{print $2}')
 
echo "Stopping default flavor virtual machine..."
for i in $VM ; do openstack server stop $i ; done
sleep $SX
echo "Done"
 
echo "Resizing flavor virtual machine..."
for i in $VM ; do openstack server resize --flavor default2 $i ; done
sleep $SF
echo "Done"
 
echo "Confirming flavor resize virtual machine..."
for i in $CONFIRM ; do openstack server resize confirm $i ; done
sleep $SX
echo "Done"
 
NEW_VM=$(openstack server list | grep default2 | awk '{print $2}')
 
echo "Starting default2 flavor virtual machine..."
for i in $NEW_VM ; do openstack server start $i ; done
sleep $SL
echo "Done"
