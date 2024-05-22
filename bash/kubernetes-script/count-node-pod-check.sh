#!/bin/bash

# Loop through all nodes and count the number of pods
echo "Counting pods per node..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  pod_count=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$node --no-headers | wc -l)
  echo "Node '$node' has $pod_count pods."
done
