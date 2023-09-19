# Kubernetes Maintenance Scripts
This repository contains scripts to help manage and maintain Kubernetes clusters.

## 1. Delete Problematic Pods Script

<br/>

### Description
This script identifies and deletes problematic pods within a given Kubernetes namespace. It specifically targets pods with the statuses: Error, Evicted, and CrashLoopBackOff.

<br/>

### Usage
Replace [NAMESPACE] with the desired Kubernetes namespace where you want to target the problematic pods.
```bash
./delete_problematic_pods.sh [NAMESPACE]
```

<br/>

### Prerequisites
kubectl should be installed and configured to point to your Kubernetes cluster.
Appropriate permissions to delete pods in the target namespace.

<br/>

### Notes
- Ensure the script has execute permissions. Grant them using: chmod +x delete_problematic_pods.sh.
- The script will target pods with the statuses: Error, Evicted, and CrashLoopBackOff. Understand the implications before running.

<br/>

## 2. Kubernetes Certificate Renewal Script

<br/>

### Description
This script is designed to renew Kubernetes certificates managed by kubeadm and restart the associated control plane pods.

<br/>

### Usage
```bash
./k8s_certs_renew.sh
```

### Prerequisites
The cluster should be set up with kubeadm.
Ensure the script is run as a user with sufficient permissions to renew certificates and manage cluster resources.

<br/>

### Notes
- The script first checks the expiration of the certificates, renews them, and then restarts the required control plane pods.
- After renewal, it updates the kubeconfig files in both the /root/.kube/ and $HOME/.kube/ directories.
- Make sure the script has execute permissions. Grant them using: chmod +x k8s_certs_renew.sh.
- Ensure you backup any critical data and configurations before running the script.




