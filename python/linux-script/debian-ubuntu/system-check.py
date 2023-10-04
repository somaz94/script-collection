#!/usr/bin/env python3

import os
import subprocess

def run_command(cmd):
    return subprocess.check_output(cmd, shell=True).decode('utf-8').strip()

def main():
    print("Debian/Ubuntu Server Inspection Script")
    print("------------------------------")

    # 1. Check the OS and version
    print("1. Checking Operating System...")
    os_description = run_command("lsb_release -d | cut -f2")
    os_codename = run_command("lsb_release -c | cut -f2")
    print(f"Description: {os_description}")
    print(f"Codename: {os_codename}")

    # 2. Check Kernel version
    print("2. Checking Kernel Version...")
    kernel_version = run_command("uname -r")
    print(f"Kernel Version: {kernel_version}")

    # 3. Check CPU cores and architecture
    print("3. Checking CPU Information...")
    cores = run_command("grep -c ^processor /proc/cpuinfo")
    architecture = run_command("uname -m")
    print(f"CPU Cores: {cores}")
    print(f"Architecture: {architecture}")

    # 4. Check total RAM
    print("4. Checking RAM...")
    total_ram = run_command("free -m | awk '/^Mem:/{print $2}'")
    print(f"Total RAM: {total_ram} MB")

    # 5. Check disk space on important partitions
    print("5. Checking Disk Space...")
    print(run_command("df -h | grep -E '(\\/$|\\/boot$)'"))

    # 6. Check if UFW (Uncomplicated Firewall) is active
    print("6. Checking for active firewall (UFW)...")
    ufw_status_output = run_command("sudo ufw status")
    if "Status: active" in ufw_status_output.splitlines():
        print("UFW firewall is active.")
    else:
        print("UFW firewall is not active.")

    # 7. Check for important services status (like SSH)
    print("7. Checking important services status...")
    if run_command("systemctl is-active sshd") == "active":
        print("SSH is running.")
    else:
        print("SSH is not running.")

    # 8. Checking for installed software updates
    print("8. Checking for software updates...")
    updates_count = int(run_command("sudo apt list --upgradable 2>/dev/null | wc -l"))
    if updates_count > 1:
        print("There are software updates available.")
    else:
        print("No software updates found.")

    # 9. Check hostname and IP address
    print("9. Checking hostname and IP address...")
    hostname = run_command("hostname")
    ip_address = run_command("hostname -I | awk '{print $1}'")
    print(f"Hostname: {hostname}")
    print(f"IP Address: {ip_address}")

    # End of script message
    print("Inspection complete!")

if __name__ == "__main__":
    main()