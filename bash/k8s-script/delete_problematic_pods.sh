#!/bin/bash

# Namespace Discovery
# ----------------
# Display all available namespaces in the cluster
# Format: List each namespace with a bullet point
echo "Available namespaces:"
kubectl get namespaces | grep -v NAME | awk '{print "- " $1}'
echo

# Input Validation
# -------------
# Check if namespace argument is provided
# Exit if no namespace is specified
NAMESPACE="$1"

if [ -z "$NAMESPACE" ]; then
    echo "Please provide a namespace."
    exit 1
fi

# Pod Cleanup Process
# ----------------
# Delete pods in various problematic states:
# 1. Error state: Pods that have failed to start or run
# 2. Evicted state: Pods that were evicted due to node issues
# 3. CrashLoopBackOff state: Pods that repeatedly crash and restart

# Delete pods in Error state
kubectl get po -n $NAMESPACE | grep Error | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

# Delete pods in Evicted state
kubectl get po -n $NAMESPACE | grep Evicted | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

# Delete pods in CrashLoopBackOff state
kubectl get po -n $NAMESPACE | grep CrashLoopBackOff | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

# Completion Message
# --------------
# Notify user of successful cleanup
echo "Done deleting problematic pods in namespace $NAMESPACE."

