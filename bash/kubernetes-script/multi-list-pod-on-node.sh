#!/bin/bash

# Function to list all nodes and prompt the user to select one or more, excluding master by default
select_node() {
  echo "Available nodes (excluding master nodes):"
  # Exclude master nodes unless they are explicitly requested
  kubectl get nodes --selector='!node-role.kubernetes.io/master' -o name
  echo ""
  echo "Enter the name of the node(s) separated by commas (e.g., node/node1,node/node2) or type 'all' to select all non-master nodes."
  read -p "Enter your choice: " INPUT

  if [ -z "$INPUT" ]; then
    echo "No input provided. Exiting."
    exit 1
  elif [ "$INPUT" == "all" ]; then
    NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}')
  else
    NODES=$(echo $INPUT | tr ',' '\n')
  fi
  echo "Selected nodes: $NODES"
}

# Function to list pods on the selected node(s)
list_pods_on_node() {
  for NODE in $NODES; do
    echo "Pods running on $NODE:"
    # Ensuring we're querying correctly by logging the field selector
    echo "Running command: kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$(echo $NODE | cut -d'/' -f2)"
    kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$(echo $NODE | cut -d'/' -f2)
    echo ""
  done
}

# Main script execution
select_node
list_pods_on_node

