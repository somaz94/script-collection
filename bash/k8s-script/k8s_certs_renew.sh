#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Define variables
current_date=$(date +'%Y-%m-%d')
k8s_user=${K8S_USER:-somaz}  # Use environment variable with default value
backup_dir="/root/${current_date}-kubernetes-pki-backup"

# Checking the expiration of certificates
echo "Checking the expiration of current Kubernetes certificates..."
kubeadm certs check-expiration

# Backup current certificates before renewal
echo "Backing up existing certificates..."
mkdir -p "$backup_dir"
if ! cp -r /etc/kubernetes/pki/* "$backup_dir"; then
    echo "Backup failed"
    exit 1
fi

# Verify backup
if ! diff -r /etc/kubernetes/pki "$backup_dir" > /dev/null; then
    echo "Backup verification failed"
    exit 1
fi

# Renew all Kubernetes certificates
echo "Renewing Kubernetes certificates..."
kubeadm certs renew all || { echo "Certificate renewal failed"; exit 1; }

# Restart kubelet to apply new certificates
echo "Restarting kubelet to apply new certificates..."
systemctl restart kubelet || { echo "Failed to restart kubelet"; exit 1; }

# Wait for kubelet and control plane components to restart
echo "Waiting for kubelet and control plane components to reload configurations..."
sleep 20

# Explicitly reload control plane components if not managed by kubelet as static pods
echo "Reloading Kubernetes control plane components..."
for component in kube-apiserver kube-controller-manager kube-scheduler; do
    if ! pidof $component > /dev/null; then
        echo "Warning: $component is not running"
        continue
    fi
    kill -s SIGHUP $(pidof $component)
done

# Restart container runtime to ensure it's using the latest certificates
echo "Restarting container runtime..."
systemctl restart containerd || { echo "Failed to restart container runtime"; exit 1; }

# Ensure system manager is aware of any changes in the system services
echo "Reloading system daemon configurations..."
systemctl daemon-reload

# Confirm running status of all components
echo "Checking the status of Kubernetes components..."
kubectl get pods --all-namespaces

# Update admin configuration
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

# Check nodes and again check certificate expiration to confirm renewal
echo "Checking status of nodes and rechecking certificate expirations..."
kubectl get nodes
kubeadm certs check-expiration

echo "Certificate renewal process completed successfully."