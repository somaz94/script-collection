#!/bin/bash

# Operating System Detection
# ----------------------
# Detect the type of Linux distribution
# Supports both RHEL-based and Debian-based systems
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$(echo "$ID_LIKE" | tr '[:upper:]' '[:lower:]')
    if [[ "$OS_FAMILY" == *"rhel"* || "$OS_FAMILY" == *"fedora"* || "$ID" == "centos" || "$ID" == "rocky" ]]; then
        OS_TYPE="rhel"
    elif [[ "$OS_FAMILY" == *"debian"* || "$ID" == "ubuntu" ]]; then
        OS_TYPE="debian"
    else
        OS_TYPE="unknown"
    fi
fi

echo "Linux Server Inspection Script"
echo "-----------------------------"

# 1. Operating System Check
# ----------------------
# Display detailed OS information based on distribution type
echo "1. Checking Operating System..."
if [ "$OS_TYPE" == "rhel" ]; then
    os_description=$(cat /etc/redhat-release)
    echo "Description: $os_description"
elif [ "$OS_TYPE" == "debian" ]; then
    os_description=$(lsb_release -d | cut -f2)
    os_codename=$(lsb_release -c | cut -f2)
    echo "Description: $os_description"
    echo "Codename: $os_codename"
fi

# 2. Kernel Version Check
# --------------------
# Display current kernel version
echo "2. Checking Kernel Version..."
kernel_version=$(uname -r)
echo "Kernel Version: $kernel_version"

# 3. CPU Information Check
# ---------------------
# Display CPU core count and system architecture
echo "3. Checking CPU Information..."
cores=$(grep -c ^processor /proc/cpuinfo)
architecture=$(uname -m)
echo "CPU Cores: $cores"
echo "Architecture: $architecture"

# 4. Memory Check
# ------------
# Display total system RAM in megabytes
echo "4. Checking RAM..."
total_ram=$(free -m | awk '/^Mem:/{print $2}')
echo "Total RAM: $total_ram MB"

# 5. Disk Space Check
# ----------------
# Check disk usage on critical partitions (root and boot)
echo "5. Checking Disk Space..."
df -h | grep -E '(\/$|\/boot$)'

# 6. Firewall Status Check
# --------------------
# Check firewall status based on OS type
# Supports both firewalld (RHEL) and UFW (Debian)
echo "6. Checking Firewall status..."
if [ "$OS_TYPE" == "rhel" ]; then
    if systemctl is-active --quiet firewalld; then
        echo "firewalld is running."
    else
        echo "firewalld is not running."
    fi
elif [ "$OS_TYPE" == "debian" ]; then
    if sudo ufw status | grep -q "^Status: active$"; then
        echo "UFW firewall is active."
    else
        echo "UFW firewall is not active."
    fi
fi

# 7. Service Status Check
# -------------------
# Check status of critical system services
echo "7. Checking important services status..."
if systemctl is-active --quiet sshd; then
    echo "SSH is running."
else
    echo "SSH is not running."
fi

# 8. System Updates Check
# -------------------
# Check for available system updates
# Supports both yum (RHEL) and apt (Debian) package managers
echo "8. Checking for software updates..."
if [ "$OS_TYPE" == "rhel" ]; then
    updates_count=$(sudo yum list updates -q 2>/dev/null | wc -l)
elif [ "$OS_TYPE" == "debian" ]; then
    updates_count=$(sudo apt list --upgradable 2>/dev/null | wc -l)
    # Subtract header line from apt list output
    ((updates_count--))
fi

if (( updates_count > 0 )); then
    echo "There are software updates available."
else
    echo "No software updates found."
fi

# 10. Kubernetes Cluster Check
# ------------------------
# Check Kubernetes cluster status if kubectl is available
echo "10. Checking Kubernetes Cluster Status..."
if command -v kubectl &>/dev/null; then
    if kubectl cluster-info &>/dev/null; then
        echo "Kubernetes cluster is operational."

        # 11. Kubernetes Pod Status Check
        # ---------------------------
        # Check status of all pods in the cluster
        echo "11. Checking Kubernetes Pods Status..."
        non_running_pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | awk '$4 != "Running" && $4 != "Completed" {print $2 " " $4}')
        if [ -z "$non_running_pods" ]; then
            echo "All pods are in 'Running' or 'Completed' state."
        else
            echo "Some pods are not in 'Running' or 'Completed' state:"
            echo "$non_running_pods"
        fi
    else
        echo "Kubernetes cluster is not operational or kubectl is not properly configured."
    fi
else
    echo "kubectl command not found. Skipping Kubernetes check."
fi

# Script Completion
# --------------
echo "Inspection complete!"
