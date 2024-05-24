#!/bin/bash

echo "Checking physical CPU, memory, and disk storage for each node..."

# Function to convert Ki to Gi
convert_ki_to_gi() {
  local ki=$1
  echo "scale=2; $ki / 1024 / 1024" | bc
}

# Get the list of all nodes
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

# Loop through each node
for node in $nodes; do
  echo "Node: $node"

  # Get the CPU capacity of the node
  cpu=$(kubectl get node $node -o jsonpath='{.status.capacity.cpu}')
  echo "  CPU: $cpu cores"

  # Get the memory capacity of the node in Ki and remove the 'Ki' suffix
  memory_ki=$(kubectl get node $node -o jsonpath='{.status.capacity.memory}' | sed 's/Ki//')
  memory_gi=$(convert_ki_to_gi $memory_ki)
  echo "  Memory: $memory_gi Gi"

  # Get the disk capacity of the node in Ki and remove the 'Ki' suffix
  disk_ki=$(kubectl get node $node -o jsonpath='{.status.capacity.ephemeral-storage}' | sed 's/Ki//')
  disk_gi=$(convert_ki_to_gi $disk_ki)
  echo "  Disk: $disk_gi Gi"

  echo "-------------------------------------"
done

