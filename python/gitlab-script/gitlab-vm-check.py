#!/usr/bin/env python3

# GitLab VM Health Check Script
# --------------------------
# This script performs a comprehensive health check of a GitLab VM,
# including system resources, services, and Kubernetes cluster status

import os
import subprocess
import json

def run_command(cmd):
    """Execute a shell command and return its output.
    
    Args:
        cmd (str): Command to execute
        
    Returns:
        str: Command output or None if command fails
    """
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL, shell=True).decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return None

def check_kubernetes_status():
    """Check if Kubernetes cluster is operational.
    
    Returns:
        bool: True if cluster is operational, False otherwise
    """
    try:
        nodes_status = run_command("kubectl get nodes")
        if "Ready" in nodes_status:
            print("Kubernetes cluster is operational.")
            return True
        else:
            print("Kubernetes cluster has issues. Not all nodes are in 'Ready' state.")
            return False
    except:
        print("Kubernetes cluster is not operational or kubectl is not properly configured.")
        return False

def check_pods_status():
    """Check status of all Kubernetes pods in the cluster."""
    all_pods_json = run_command('kubectl get pods --all-namespaces -o json')
    all_pods_data = json.loads(all_pods_json)

    error_pods = []

    for pod in all_pods_data['items']:
        if pod['status']['phase'] not in ['Running', 'Succeeded']:
            error_pods.append(f"{pod['metadata']['name']} {pod['status']['phase']}")

    if error_pods:
        print("Some pods are not in 'Running' or 'Succeeded' state:")
        print("\n".join(error_pods))
    else:
        print("All pods are running smoothly.")

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
    # Check disk space on critical GitLab directories and system partitions
    df_output = run_command("df -h | grep -E '(\\/var\\/opt\\/gitlab\\/backups|\\/var\\/opt\\/gitlab\\/git-data|\\/var\\/opt\\/gitlab\\/gitlab-rails\\/shared\\/lfs-objects|\\/$|\\/boot$)'")
    print(df_output)

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

    # 10. Kubernetes Status Check
    print("10. Checking Kubernetes Cluster Status...")
    if check_kubernetes_status():
        print("11. Checking Kubernetes Pods Status...")
        check_pods_status()
    else:
        print("Skipping pods check as Kubernetes is not operational.")

    # End of script message
    print("Inspection complete!")

if __name__ == "__main__":
    main()
