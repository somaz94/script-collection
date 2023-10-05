import os
import subprocess

def run_command(cmd):
    return subprocess.getoutput(cmd)

def main():
    print("CentOS/RHEL/Rocky Server Inspection Script")
    print("------------------------------------")

    # 1. Check the OS and version
    print("1. Checking Operating System...")
    os_description = run_command("cat /etc/redhat-release")
    print(f"Description: {os_description}")

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
    disk_info = run_command("df -h | grep -E '(\\/$|\\/boot$)'")
    print(disk_info)

    # 6. Check firewall status
    print("6. Checking Firewall status...")
    is_firewalld_running = run_command("systemctl is-active firewalld")
    if "active" in is_firewalld_running:
        print("firewalld is running.")
    else:
        print("firewalld is not running.")

    # 7. Check for important services status (like SSHD)
    print("7. Checking important services status...")
    is_sshd_running = run_command("systemctl is-active sshd")
    if "active" in is_sshd_running:
        print("SSH (sshd) is running.")
    else:
        print("SSH (sshd) is not running.")

    # 8. Checking for installed software updates
    print("8. Checking for software updates...")
    updates_count = int(run_command("yum list updates -q | wc -l"))
    if updates_count > 0:
        print("There are software updates available.")
    else:
        print("No software updates found.")

    # 9. Check hostname and IP address
    print("9. Checking hostname and IP address...")
    hostname = run_command("hostname")
    ip_address = run_command("hostname -I | awk '{print $1}'")
    print(f"Hostname: {hostname}")
    print(f"IP Address: {ip_address}")

    print("Inspection complete!")

if __name__ == "__main__":
    main()

