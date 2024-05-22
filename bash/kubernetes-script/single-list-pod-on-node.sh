#!/bin/bash

# Function to list all nodes and prompt the user to select one
select_node() {
  echo "Available nodes:"
  kubectl get nodes --selector='!node-role.kubernetes.io/master' -o name
  echo ""
  read -p "Enter the name of the node (e.g., node/node1): " NODE
  if [ -z "$NODE" ]; then
    echo "No node selected. Exiting."
    exit 1
  fi
}

# Function to list pods on the selected node
list_pods_on_node() {
  echo "Pods running on $NODE:"
  kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$(echo $NODE | cut -d'/' -f2)
}

# Main script execution
select_node
list_pods_on_node
