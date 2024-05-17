import os
import time
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import subprocess

# Settings: Directory to monitor, target directory for synchronization, log file path
watch_dir = '/root/somaz'
sync_target_dir = '/data/local-somaz/'
log_file_path = '/root/sync-script/sync.log'

# Function to log messages in the log file
def log_message(message):
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file_path, 'a') as log_file:
        log_file.write(f"[{current_time}] {message}\n")

# Perform initial synchronization
log_message("Performing initial sync...")
subprocess.run(['rsync', '-avz', '--delete', watch_dir + '/', sync_target_dir])
log_message("Initial sync completed.")

# Event handler class
class ChangeHandler(FileSystemEventHandler):
    def on_any_event(self, event):
        # Logic to execute when a file or directory changes
        if event.is_directory:
            return
        file_path = event.src_path
        log_message(f"Detected change in: {file_path}")
        subprocess.run(['rsync', '-avz', '--delete', file_path, sync_target_dir])
        log_message(f"Synchronized {file_path} to {sync_target_dir}")

# Create and configure the Observer object
observer = Observer()
observer.schedule(ChangeHandler(), watch_dir, recursive=True)

# Start monitoring the file system
observer.start()
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    observer.stop()

observer.join()
