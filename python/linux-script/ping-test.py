#!/usr/bin/env python3

# Network Ping Test Script
# ---------------------
# This script performs a ping test on all IP addresses in a specified subnet
# to identify which hosts are alive and responding to ICMP requests.

import subprocess
import ipaddress

# Network Configuration
# ------------------
# Define the subnet and CIDR notation for the network to scan
# Example: "10.10.100.0/24" will scan all IPs from 10.10.100.1 to 10.10.100.254
subnet = "10.10.100.0/24"  # Input your IP range with CIDR notation

# Create an IPv4 network object for the specified subnet
# strict=False allows for non-standard network addresses
network = ipaddress.ip_network(subnet, strict=False)

# Network Scan
# ----------
# Iterate through all usable host addresses in the subnet
# network.hosts() excludes network and broadcast addresses
for ip in network.hosts():
    try:
        # Ping each IP address with:
        # -c 1: Send only one packet
        # -W 1: Wait only 1 second for response
        response = subprocess.run(['ping', '-c', '1', '-W', '1', str(ip)], 
                                stdout=subprocess.DEVNULL)
        
        # Check if ping was successful (returncode 0)
        if response.returncode == 0:
            print(f"{ip}: OK")
    except Exception as e:
        # Handle any errors that occur during the ping process
        print(f"Failed to ping {ip}: {e}")
