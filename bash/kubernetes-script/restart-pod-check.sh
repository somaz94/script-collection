#!/bin/bash

# Set the threshold for the number of restarts
THRESHOLD=5

# Loop through all pods in all namespaces
for pod in $(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{" "}{end}'); do
  namespace=$(echo $pod | cut -d'|' -f1)
  pod_name=$(echo $pod | cut -d'|' -f2)

  # Get the restart counts for all containers in the pod
  restarts=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{" "}{end}')

  # Calculate the total restarts for the pod
  total_restarts=0
  for restart in $restarts; do
    total_restarts=$((total_restarts + restart))
  done

  # Check if the total restart count exceeds the threshold
  if [ "$total_restarts" -ge "$THRESHOLD" ]; then
    echo "Pod '$pod_name' in namespace '$namespace' has restarted $total_restarts times."
  fi
done
