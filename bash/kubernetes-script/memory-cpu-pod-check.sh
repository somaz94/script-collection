#!/bin/bash

# Set the threshold for CPU and memory usage (in millicores and MiB)
CPU_THRESHOLD=500m
MEMORY_THRESHOLD=256Mi

# Convert CPU_THRESHOLD to a numeric value for comparison
CPU_THRESHOLD_NUM=$(echo $CPU_THRESHOLD | sed 's/m//')
MEMORY_THRESHOLD_NUM=$(echo $MEMORY_THRESHOLD | sed 's/Mi//')

# Loop through all pods in all namespaces and check resource usage
kubectl top pod --all-namespaces | awk -v cpu=$CPU_THRESHOLD_NUM -v mem=$MEMORY_THRESHOLD_NUM '
NR>1 {
  cpu_usage=$3
  mem_usage=$4
  sub("m$", "", cpu_usage)
  sub("Mi$", "", mem_usage)
  if (cpu_usage+0 > cpu || mem_usage+0 > mem) print $0
}'
