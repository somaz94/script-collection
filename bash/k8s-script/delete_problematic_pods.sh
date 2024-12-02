#!/bin/bash

# Show available namespaces
echo "Available namespaces:"
kubectl get namespaces | grep -v NAME | awk '{print "- " $1}'
echo

NAMESPACE="$1"

if [ -z "$NAMESPACE" ]; then
    echo "Please provide a namespace."
    exit 1
fi

# Delete pods in Error state
kubectl get po -n $NAMESPACE | grep Error | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

# Delete pods in Evicted state
kubectl get po -n $NAMESPACE | grep Evicted | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

# Delete pods in CrashLoopBackOff state
kubectl get po -n $NAMESPACE | grep CrashLoopBackOff | awk '{print $1}' | xargs kubectl delete po -n $NAMESPACE

echo "Done deleting problematic pods in namespace $NAMESPACE."

