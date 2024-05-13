import subprocess
import ipaddress

# Variables to define the subnet and CIDR
subnet = "10.10.100.0/24"  # Input your IP range with CIDR notation

# Create an IPv4 network object
network = ipaddress.ip_network(subnet, strict=False)

# This script pings all IP addresses in the specified subnet and checks which IPs are alive.
for ip in network.hosts():  # Iterates only over usable hosts, excluding network and broadcast addresses
    try:
        response = subprocess.run(['ping', '-c', '1', '-W', '1', str(ip)], stdout=subprocess.DEVNULL)
        if response.returncode == 0:
            print(f"{ip}: OK")
    except Exception as e:
        print(f"Failed to ping {ip}: {e}")
