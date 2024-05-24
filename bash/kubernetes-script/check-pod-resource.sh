#!/bin/bash

# Function to print resource usage for each pod
function print_pod_usage() {
    local namespace=$1
    pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')

    echo "Resource usage in namespace: $namespace"
    for pod in $pods; do
        echo "Pod: $pod"
        # Get CPU and memory requests
        cpu_requests=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].resources.requests.cpu}')
        mem_requests=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].resources.requests.memory}')

        # Get CPU and memory limits
        cpu_limits=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].resources.limits.cpu}')
        mem_limits=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].resources.limits.memory}')

        echo "  CPU Requests: $cpu_requests, CPU Limits: $cpu_limits"
        echo "  Memory Requests: $mem_requests, Memory Limits: $mem_limits"
        echo ""
    done
}

echo "Fetching namespaces..."
# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
echo "Available namespaces:"
echo "$namespaces"
echo "Enter a namespace to inspect or type 'all' to inspect all namespaces:"
read input_namespace

if [ "$input_namespace" == "all" ]; then
    # Iterate over each namespace and print pod resource usage
    for namespace in $namespaces; do
        print_pod_usage $namespace
    done
else
    # Check if the entered namespace is valid
    if [[ " $namespaces " =~ " $input_namespace " ]]; then
        print_pod_usage $input_namespace
    else
        echo "Error: Namespace '$input_namespace' does not exist."
    fi
fi
