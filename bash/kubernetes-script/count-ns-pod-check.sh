#!/bin/bash

# Loop through all namespaces and count the number of pods
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  pod_count=$(kubectl get pods -n $ns --no-headers | wc -l)
  echo "Namespace '$ns' has $pod_count pods."
done
