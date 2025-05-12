#!/bin/bash

# Network Configuration
# ------------------
# Define network parameters for ping test
# SUBNET: First three octets of IP address (e.g., 10.10.100)
# CIDR: Subnet mask in CIDR notation (e.g., 24 for /24)
SUBNET="10.10.100" # Input Your IP Range
CIDR=24 # Input Your Subnet

# Host Count Calculation
# -------------------
# Calculate total number of possible hosts in subnet
# Formula: 2^(32-CIDR) - 2
# Subtract 2 to exclude network and broadcast addresses
NUM_HOSTS=$((2**(32-CIDR)-2))

# IP Range Setup
# ------------
# Define start and end IP addresses for scanning
# Start from 1 to skip network address
# End at calculated number of hosts
START_IP=1
END_IP=$NUM_HOSTS

# Network Scan
# ----------
# Ping each IP address in the specified range
# -c 1: Send only one ping packet
# -W 1: Wait maximum 1 second for response
# Output only responding hosts
for i in $(seq $START_IP $END_IP); do
    ping -c 1 -W 1 $SUBNET.$i > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "$SUBNET.$i: OK"
    fi
done
