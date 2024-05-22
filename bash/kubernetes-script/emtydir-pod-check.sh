#!/bin/bash

# Loop through all pods in all namespaces
for pod in $(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{" "}{end}'); do
  namespace=$(echo $pod | cut -d'|' -f1)
  pod_name=$(echo $pod | cut -d'|' -f2)
  
  # Get the volumes for each pod
  volumes=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.spec.volumes}')
  
  # Check if any of the volumes is of type emptyDir
  if echo $volumes | grep -q 'emptyDir'; then
    echo "Pod '$pod_name' in namespace '$namespace' has an emptyDir volume."
  fi
done

