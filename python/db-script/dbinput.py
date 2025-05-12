#!/usr/bin/env python3

# Database Restore Script
# ---------------------
# This script restores multiple MySQL databases from backup files
# It includes error handling and verification of backup files

import os
import subprocess
import time

# Database Configuration
# --------------------
# Define database connection parameters
DB_HOST = "your_db_host"      # Database server hostname
DB_USER = "your_db_user"      # Database username
DB_PASS = "your_db_password"  # Database password
DBS = ["db1", "db2", "db3", "db4", "db5", "db6", "db7"]  # List of databases to restore
BACKUP_PATH = "your_backup_path"  # Directory containing backup files

# Process each database
for DB_NAME in DBS:
    # Generate expected backup filename with current date
    BACKUP_FILE_NAME = "{}_{}.sql".format(DB_NAME, time.strftime("%Y%m%d"))
    backup_file_path = os.path.join(BACKUP_PATH, BACKUP_FILE_NAME)

    # Verify backup file exists
    if not os.path.exists(backup_file_path):
        print(f"Backup file {backup_file_path} does not exist.")
        exit(1)

    # Restore database from backup file
    # Uses mysql command-line client to restore the database
    command = ["mysql", "-h", DB_HOST, "-u", DB_USER, "--password={}".format(DB_PASS), DB_NAME]
    with open(backup_file_path, 'r') as f:
        result = subprocess.run(command, stdin=f)

    # Verify restore success
    if result.returncode == 0:
        print(f"Restore of {DB_NAME} has been completed successfully.")
    else:
        print(f"Restore of {DB_NAME} failed.")
        exit(1)

    # Wait between restores to prevent server overload
    sleep_duration = 10  # seconds between restores
    time.sleep(sleep_duration)

