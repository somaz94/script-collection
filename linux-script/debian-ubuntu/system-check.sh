#!/bin/bash

echo "Debian/Ubuntu Server Inspection Script"
echo "------------------------------"

# 1. Check the OS and version
echo "1. Checking Operating System..."
os_description=$(lsb_release -d | cut -f2)
os_codename=$(lsb_release -c | cut -f2)
echo "Description: $os_description"
echo "Codename: $os_codename"

# 2. Check Kernel version
echo "2. Checking Kernel Version..."
kernel_version=$(uname -r)
echo "Kernel Version: $kernel_version"

# 3. Check CPU cores and architecture
echo "3. Checking CPU Information..."
cores=$(grep -c ^processor /proc/cpuinfo)
architecture=$(uname -m)
echo "CPU Cores: $cores"
echo "Architecture: $architecture"

# 4. Check total RAM
echo "4. Checking RAM..."
total_ram=$(free -m | awk '/^Mem:/{print $2}')
echo "Total RAM: $total_ram MB"

# 5. Check disk space on important partitions
echo "5. Checking Disk Space..."
df -h | grep -E '(\/$|\/boot$)'

# 6. Check if UFW (Uncomplicated Firewall) is active
echo "6. Checking for active firewall (UFW)..."
if sudo ufw status | grep -q "active"; then
    echo "UFW firewall is active."
else
    echo "UFW firewall is not active."
fi

# 7. Check for important services status (like SSH)
echo "7. Checking important services status..."
if systemctl is-active --quiet sshd; then
    echo "SSH is running."
else
    echo "SSH is not running."
fi

# 8. Checking for installed software updates
echo "8. Checking for software updates..."
updates_count=$(sudo apt list --upgradable 2>/dev/null | wc -l)
if (( updates_count > 1 )); then
    echo "There are software updates available."
else
    echo "No software updates found."
fi

# 9. Check hostname and IP address
echo "9. Checking hostname and IP address..."
hostname=$(hostname)
ip_address=$(hostname -I | awk '{print $1}')
echo "Hostname: $hostname"
echo "IP Address: $ip_address"

# End of script message
echo "Inspection complete!"

