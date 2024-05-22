#!/bin/bash

# Set the namespace
NAMESPACE=$1

if [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

# Create a directory to store logs
LOG_DIR="${NAMESPACE}-logs"
mkdir -p $LOG_DIR

# Loop through all pods in the given namespace and save their logs to files
for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  LOG_FILE="$LOG_DIR/${NAMESPACE}-${pod}.log"
  echo "Saving logs for pod '$pod' in namespace '$NAMESPACE' to '$LOG_FILE'..."
  kubectl logs $pod -n $NAMESPACE > $LOG_FILE
  echo "--------------------------------------------------"
done

echo "All logs have been saved in the directory '$LOG_DIR'."
