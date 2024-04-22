#!/bin/bash

# Define current date for backup
current_date=$(date +'%Y-%m-%d')

# Checking the expiration of certificates
echo "Checking the expiration of current Kubernetes certificates..."
kubeadm certs check-expiration

# Backup current certificates before renewal
echo "Backing up existing certificates..."
backup_dir="/root/${current_date}-kubernetes-pki-backup"
mkdir -p "$backup_dir"
cp -r /etc/kubernetes/pki/* "$backup_dir" || { echo "Backup failed"; exit 1; }

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
kill -s SIGHUP $(pidof kube-apiserver)
kill -s SIGHUP $(pidof kube-controller-manager)
kill -s SIGHUP $(pidof kube-scheduler)

# Restart container runtime to ensure it's using the latest certificates
echo "Restarting container runtime..."
systemctl restart containerd || { echo "Failed to restart container runtime"; exit 1; }

# Ensure system manager is aware of any changes in the system services
echo "Reloading system daemon configurations..."
systemctl daemon-reload

# Confirm running status of all components
echo "Checking the status of Kubernetes components..."
kubectl get pods --all-namespaces

# Update admin configuration in .kube/config
echo "Updating admin configuration..."
cp /etc/kubernetes/admin.conf /root/.kube/config
cp /etc/kubernetes/admin.conf /home/somaz/.kube/config || { echo "Failed to copy admin.conf to user somaz"; exit 1; }

# Check nodes and again check certificate expiration to confirm renewal
echo "Checking status of nodes and rechecking certificate expirations..."
kubectl get nodes
kubeadm certs check-expiration

echo "Certificate renewal process completed successfully."