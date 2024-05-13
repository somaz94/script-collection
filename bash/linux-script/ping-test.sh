#!/bin/bash

# Variables to define the subnet and CIDR
SUBNET="10.10.100" # Input Your IP Range
CIDR=24 # Input Your Subnet

# Calculate the number of hosts based on the CIDR
NUM_HOSTS=$((2**(32-CIDR)-2)) # Subtract 2 for network and broadcast addresses

# Set start and end IP
START_IP=1
END_IP=$NUM_HOSTS

# This script pings all IP addresses in the specified subnet and IP range and checks which IPs are alive.
for i in $(seq $START_IP $END_IP); do
    ping -c 1 -W 1 $SUBNET.$i > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "$SUBNET.$i: OK"
    fi
done
