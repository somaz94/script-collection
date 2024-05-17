#!/bin/bash

# Input file or directory path
file_path="$1"

# Target directory for synchronization
sync_target_dir="/data/local-somaz/" # Change your Target directory

# Log file path configuration
log_file="/root/sync-script/sync.log" 

# Current date and time
current_time=$(date "+%Y-%m-%d %H:%M:%S")

# Record detected changes in the log file
echo "[$current_time] Detected change in: $file_path" >> $log_file

# Execute rsync to synchronize the changed file or directory to the target directory
rsync -avz --delete "$file_path" "$sync_target_dir"

# Record synchronization completion message in the log file
echo "[$current_time] Synchronized $file_path to $sync_target_dir" >> $log_file

