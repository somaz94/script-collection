#!/bin/bash
 
# Debug Mode
# ---------
# Enable command execution tracing for debugging
# Optional: Helps identify error locations
set -x
 
# Environment Setup
# --------------
# Enable alias expansion and load bash configuration
shopt -s expand_aliases
source ${HOME}/.bashrc
 
# New Flavor Creation
# ----------------
# Create a new flavor with specific specifications if it doesn't exist
# Specifications:
# - 4 vCPUs
# - 8GB RAM
# - 50GB disk
# - Single CPU socket
echo "Creating new flavor..."
FLAVOR_NAME_TEMP=$(openstack flavor list | grep default2 | awk '{print $4}')
if [ "x${FLAVOR_NAME_TEMP}" != "xdefault2" ]; then
        openstack flavor create --vcpu 4 --ram 8192 --disk 50 default2 --property=hw:cpu_max_sockets=1 --public
fi
echo "Done"
 
# VM Information Collection
# ----------------------
# Get list of VMs to be resized and calculate timing parameters
VM=$(openstack server list | grep default | awk '{print $2}')
COUNT=$(openstack server list | grep default | awk '{print $2}' | wc -l)
SL=$(($COUNT / 2))    # Short wait time
SX=$(($COUNT * 4))    # Medium wait time
SF=$(($COUNT * 6))    # Long wait time
CONFIRM=$(openstack server list | grep VERIFY_RESIZE | awk '{print $2}')
 
# VM Shutdown Process
# ----------------
# Stop all VMs that need to be resized
echo "Stopping default flavor virtual machine..."
for i in $VM ; do openstack server stop $i ; done
sleep $SX
echo "Done"
 
# VM Resize Process
# --------------
# Resize all VMs to the new flavor
echo "Resizing flavor virtual machine..."
for i in $VM ; do openstack server resize --flavor default2 $i ; done
sleep $SF
echo "Done"
 
# Resize Confirmation
# ----------------
# Confirm the resize operation for all VMs
echo "Confirming flavor resize virtual machine..."
for i in $CONFIRM ; do openstack server resize confirm $i ; done
sleep $SX
echo "Done"
 
# VM Restart Process
# --------------
# Get list of resized VMs and start them
NEW_VM=$(openstack server list | grep default2 | awk '{print $2}')
 
echo "Starting default2 flavor virtual machine..."
for i in $NEW_VM ; do openstack server start $i ; done
sleep $SL
echo "Done"
