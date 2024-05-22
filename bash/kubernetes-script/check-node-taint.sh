#!/bin/bash

# List all nodes
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
  # Get the taints on each node
  taints=$(kubectl get node $node -o jsonpath='{.spec.taints}')
  
  if [ -n "$taints" ]; then
    # If taints are present, print them
    echo "Node $node has taints: $taints"
  else
    # If no taints are present
    echo "Node $node has no taints"
  fi
done
