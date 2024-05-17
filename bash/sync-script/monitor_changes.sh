#!/bin/bash

# Set the directory to be monitored
watch_dir="/root/somaz"

# Target directory for synchronization
sync_target_dir="/data/local-somaz/"

# Path to the change handling script
action_script="/root/sync-script/handle_change.sh"

# Perform initial synchronization
echo "Performing initial sync..."
rsync -avz --delete "$watch_dir/" "$sync_target_dir"
echo "Initial sync completed."

# Monitor for file changes and execute the script on changes
inotifywait -m -r -e modify -e move -e create -e delete "$watch_dir" --format '%w%f' |
while read file; do
    echo "Detected change in $file"
    # Execute the change handling script when changes are detected
    bash "$action_script" "$file"
done
