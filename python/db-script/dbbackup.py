#!/usr/bin/env python3

# Database Backup Script
# --------------------
# This script creates backups of multiple MySQL databases
# It uses mysqldump to create SQL dumps and includes error handling

import os
import subprocess
import time

# Database Configuration
# --------------------
# Define database connection parameters
DB_HOST = "your_db_host"      # Database server hostname
DB_USER = "your_db_user"      # Database username
DB_PASS = "your_db_password"  # Database password
DBS = ["db1", "db2", "db3", "db4", "db5", "db6", "db7"]  # List of databases to backup
BACKUP_PATH = "your_backup_path"  # Directory to store backups

# Process each database
for DB_NAME in DBS:
    # Generate backup filename with current date
    BACKUP_FILE_NAME = "{}_{}.sql".format(DB_NAME, time.strftime("%Y%m%d"))

    # Ensure backup directory exists
    os.makedirs(BACKUP_PATH, exist_ok=True)

    # Create database dump using mysqldump
    # --set-gtid-purged=OFF is used to avoid GTID-related issues
    command = ["mysqldump", "-h", DB_HOST, "-u", DB_USER, "--set-gtid-purged=OFF", DB_NAME]
    with open(os.path.join(BACKUP_PATH, BACKUP_FILE_NAME), 'w') as f:
        result = subprocess.run(command, stdout=f, env={"MYSQL_PWD": DB_PASS})

    # Verify backup success
    if result.returncode == 0:
        print("Backup of {} has been completed successfully. The backup file is located at {}/{}".format(DB_NAME, BACKUP_PATH, BACKUP_FILE_NAME))
    else:
        print("Backup of {} failed.".format(DB_NAME))
        exit(1)

    # Wait between backups to prevent server overload
    sleep_duration = 10  # seconds between backups
    time.sleep(sleep_duration)

