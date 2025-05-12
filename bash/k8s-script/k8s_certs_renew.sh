#!/bin/bash

# Root Privilege Check
# -----------------
# Verify script is running with root privileges
# Required for certificate operations and system service management
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Variable Initialization
# --------------------
# Set up variables for backup and user management
# current_date: Used for backup directory naming
# k8s_user: Kubernetes admin user (defaults to 'somaz' if not set)
# backup_dir: Directory for certificate backups
current_date=$(date +'%Y-%m-%d')
k8s_user=${K8S_USER:-somaz}  # Use environment variable with default value
backup_dir="/root/${current_date}-kubernetes-pki-backup"

# Certificate Expiration Check
# -------------------------
# Check current certificate expiration dates
# Provides overview of certificates that need renewal
echo "Checking the expiration of current Kubernetes certificates..."
kubeadm certs check-expiration

# Certificate Backup
# ----------------
# Create backup of existing certificates before renewal
# Includes verification of backup integrity
echo "Backing up existing certificates..."
mkdir -p "$backup_dir"
if ! cp -r /etc/kubernetes/pki/* "$backup_dir"; then
    echo "Backup failed"
    exit 1
fi

# Backup Verification
# ----------------
# Verify backup was created successfully
# Compares original and backup directories
if ! diff -r /etc/kubernetes/pki "$backup_dir" > /dev/null; then
    echo "Backup verification failed"
    exit 1
fi

# Certificate Renewal
# ----------------
# Renew all Kubernetes certificates
# Includes error handling for failed renewal
echo "Renewing Kubernetes certificates..."
kubeadm certs renew all || { echo "Certificate renewal failed"; exit 1; }

# Kubelet Restart
# -------------
# Restart kubelet to apply new certificates
# Required for new certificates to take effect
echo "Restarting kubelet to apply new certificates..."
systemctl restart kubelet || { echo "Failed to restart kubelet"; exit 1; }

# Component Reload Wait
# ------------------
# Wait for components to restart and reload configurations
# Ensures system stability during renewal process
echo "Waiting for kubelet and control plane components to reload configurations..."
sleep 20

# Control Plane Component Reload
# ---------------------------
# Reload control plane components if not managed by kubelet
# Sends SIGHUP signal to reload configurations
echo "Reloading Kubernetes control plane components..."
for component in kube-apiserver kube-controller-manager kube-scheduler; do
    if ! pidof $component > /dev/null; then
        echo "Warning: $component is not running"
        continue
    fi
    kill -s SIGHUP $(pidof $component)
done

# Container Runtime Restart
# ----------------------
# Restart container runtime to ensure latest certificate usage
# Required for proper certificate propagation
echo "Restarting container runtime..."
systemctl restart containerd || { echo "Failed to restart container runtime"; exit 1; }

# System Daemon Reload
# -----------------
# Reload system daemon configurations
# Ensures system is aware of all service changes
echo "Reloading system daemon configurations..."
systemctl daemon-reload

# Component Status Check
# -------------------
# Verify all Kubernetes components are running
# Provides overview of system health after renewal
echo "Checking the status of Kubernetes components..."
kubectl get pods --all-namespaces

# Admin Configuration Update
# ----------------------
# Update admin configuration with new certificates
# Copies updated config to appropriate locations
echo "Updating admin configuration..."
cp /etc/kubernetes/admin.conf /root/.kube/config
if [[ -d "/home/${k8s_user}" ]]; then
    cp /etc/kubernetes/admin.conf "/home/${k8s_user}/.kube/config" || { 
        echo "Failed to copy admin.conf to user ${k8s_user}"
        exit 1
    }
else
    echo "Warning: User ${k8s_user} home directory not found"
fi

# Final Verification
# ----------------
# Verify node status and certificate expiration
# Confirms successful renewal process
echo "Checking status of nodes and rechecking certificate expirations..."
kubectl get nodes
kubeadm certs check-expiration

echo "Certificate renewal process completed successfully."