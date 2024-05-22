#!/bin/bash

# Set the namespace
NAMESPACE=$1

if [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

LOG_FILE="logs_${NAMESPACE}_$(date +%Y%m%d%H%M%S).log"

echo "Streaming logs for all pods in namespace '$NAMESPACE' and saving to $LOG_FILE..."
for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "Starting to stream logs for pod '$pod' in namespace '$NAMESPACE'..." | tee -a $LOG_FILE
  {
    echo "Logs for pod '$pod':" | tee -a $LOG_FILE
    kubectl logs -n $NAMESPACE $pod -f | sed "s/^/[$pod] /" | tee -a $LOG_FILE
  } &
done

# Wait for all background log streaming to complete
wait

echo "All logs have been streamed and saved to $LOG_FILE. Opening in less..."
less +F $LOG_FILE
