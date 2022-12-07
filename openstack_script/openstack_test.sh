#!/bin/bash

shopt -s expand_aliases
source ${HOME}/.bashrc

echo "Creating private network..."
PRIVATE_NAME_TEMP=$(openstack network list | grep private-net | awk '{print $4}')
if [ "x${PRIVATE_NAME_TEMP}" != "xprivate-net" ]; then
    openstack network create private-net
    openstack subnet create --network private-net --subnet-range 172.30.1.0/24 \
        --dns-nameserver 8.8.8.8 private-subnet
fi
echo "Done"

echo "Creating external network..."
PUBLIC_NAME_TEMP=$(openstack network list | grep public-net | awk '{print $4}')
if [ "x${PUBLIC_NAME_TEMP}" != "xpublic-net" ]; then
    openstack network create --external --share --provider-network-type flat --provider-physical-network external public-net
    openstack subnet create --network public-net --subnet-range 192.168.202.0/24 \
        --allocation-pool start=192.168.202.201,end=192.168.202.240 --dns-nameserver 8.8.8.8 public-subnet
fi
echo "Done"

echo "Creating router..."
ADMIN_ROUTER_TEMP=$(openstack router list | grep admin-router | awk '{print $4}')
if [ "x${ADMIN_ROUTER_TEMP}" != "xadmin-router" ]; then
    openstack router create admin-router
    openstack router add subnet admin-router private-subnet
    openstack router set --external-gateway public-net admin-router
    openstack router show admin-router
fi
echo "Done"

echo "Creating image..."
IMAGE_NAME_TEMP=$(openstack image list | grep Cirros-0.4.0 | awk '{print $4}')
if [ "x${IMAGE_NAME_TEMP}" != "xCirros-0.4.0" ]; then
    openstack image create --disk-format qcow2 --container-format bare \
        --file ${HOME}/cirros-0.4.0-x86_64-disk.img \
        --public \
        Cirros-0.4.0
    openstack image show Cirros-0.4.0
fi
echo "Done"

echo "Adding security group for ssh"
SEC_GROUPS=$(openstack security group list --project admin | grep default | awk '{print $2}')
for sec_var in $SEC_GROUPS
do
    SEC_RULE=$(openstack security group rule list $SEC_GROUPS | grep 1:65535 | awk '{print $8}')
    if [ "x${SEC_RULE}" != "x1:65535" ]; then
        openstack security group rule create --proto tcp --remote-ip 0.0.0.0/0 --dst-port 1:65535 --ingress  $sec_var
        openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 $sec_var
        openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 --egress $sec_var
    fi
done
echo "Done"

if [[ $(openstack server list | grep test) ]]; then
  echo "Removing existing test VM..."
  openstack server delete test
  echo "Done"
fi

IMAGE=$(openstack image list| grep Cirros-0.4.0| awk '{print $2}')
FLAVOR=$(openstack flavor list | grep default | awk '{print $2}')
NETWORK=$(openstack network list | grep private-net | awk '{print $2}')

echo "Creating virtual machine..."
openstack volume create --image $IMAGE --size 1 test-vol
sleep 20
openstack server create --volume test-vol --flavor $FLAVOR --nic net-id=$NETWORK test --wait
echo "Done"

echo "Adding external ip to vm..."
SERVER_INFO=$(openstack server list | grep test)
FLOATING_IP=$(openstack floating ip create public-net | grep floating_ip_address | awk '{print $4}')
SERVER=$(echo $SERVER_INFO| awk '{print $2}')
openstack server add floating ip $SERVER $FLOATING_IP
echo "Done"

openstack server list

if [[ $(openstack volume list | grep test_bfv) ]]; then
  echo "Removing existing test volume.."
  openstack volume delete test_bfv
  echo "Done"
fi

echo "Creating volume..."
openstack volume create --size 55 --image $IMAGE test_bfv
VOLUME=$(openstack volume list | grep test_bfv | awk '{print $2}')
echo "Attaching volume to vm..."
i=0
until [ "${VOLUME_STATUS}" == "available" ]
do
  echo "Waiting for ${VOLUME} availability."
  sleep 1
  VOLUME_STATUS=$(openstack volume list | grep test_bfv | awk '{print $6}')
  if [ "$i" = '10' ]; then
    echo "Volume is not available at least 10 seconds so I give up."
    break
  fi
  ((i++))
done
openstack server add volume $SERVER $VOLUME
echo "Done"
