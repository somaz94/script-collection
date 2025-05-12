#!/usr/bin/env python3

# File System Monitoring and Synchronization Script
# --------------------------------------------
# This script monitors a directory for changes and automatically
# synchronizes modified files to a target directory using rsync.
# It includes logging functionality and handles file system events.

import os
import time
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import subprocess

# Configuration Settings
# -------------------
# Define paths for monitoring, synchronization, and logging
watch_dir = '/root/somaz'                    # Directory to monitor for changes
sync_target_dir = '/data/local-somaz/'       # Target directory for synchronization
log_file_path = '/root/sync-script/sync.log' # Path for log file

def log_message(message):
    """Log messages with timestamp to the specified log file.
    
    Args:
        message (str): Message to be logged
    """
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file_path, 'a') as log_file:
        log_file.write(f"[{current_time}] {message}\n")

# Initial Synchronization
# ---------------------
# Perform initial sync of all files from watch directory to target
log_message("Performing initial sync...")
subprocess.run(['rsync', '-avz', '--delete', watch_dir + '/', sync_target_dir])
log_message("Initial sync completed.")

class ChangeHandler(FileSystemEventHandler):
    """Event handler class for file system changes.
    
    This class handles various file system events and triggers
    synchronization when changes are detected.
    """
    def on_any_event(self, event):
        """Handle any file system event.
        
        Args:
            event: File system event that occurred
        """
        # Skip if the event is for a directory
        if event.is_directory:
            return
            
        # Get the path of the changed file
        file_path = event.src_path
        
        # Log the detected change
        log_message(f"Detected change in: {file_path}")
        
        # Synchronize the changed file to target directory
        subprocess.run(['rsync', '-avz', '--delete', file_path, sync_target_dir])
        log_message(f"Synchronized {file_path} to {sync_target_dir}")

# Observer Setup and Monitoring
# --------------------------
# Create and configure the file system observer
observer = Observer()
observer.schedule(ChangeHandler(), watch_dir, recursive=True)

# Start the file system monitoring
observer.start()

try:
    # Keep the script running until interrupted
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    # Handle graceful shutdown on keyboard interrupt
    observer.stop()

# Wait for the observer to complete
observer.join()
