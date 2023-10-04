#!/usr/bin/env python3

import os
import subprocess
import time

# Define variables
DB_HOST = "your_db_host"
DB_USER = "your_db_user"
DB_PASS = "your_db_password"
DBS = ["db1", "db2", "db3", "db4", "db5", "db6", "db7"]  # Update this with your actual database names
BACKUP_PATH = "your_backup_path"

for DB_NAME in DBS:
    BACKUP_FILE_NAME = "{}_{}.sql".format(DB_NAME, time.strftime("%Y%m%d"))

    backup_file_path = os.path.join(BACKUP_PATH, BACKUP_FILE_NAME)

    # Check if backup file exists
    if not os.path.exists(backup_file_path):
        print(f"Backup file {backup_file_path} does not exist.")
        exit(1)

    # Restore the database from the backup file
    command = ["mysql", "-h", DB_HOST, "-u", DB_USER, "--password={}".format(DB_PASS), DB_NAME]
    with open(backup_file_path, 'r') as f:
        result = subprocess.run(command, stdin=f)

    # Check if the restore was successful
    if result.returncode == 0:
        print(f"Restore of {DB_NAME} has been completed successfully.")
    else:
        print(f"Restore of {DB_NAME} failed.")
        exit(1)

    # Sleep for a while before the next restore
    sleep_duration = 10  # adjust this to your needs, this will wait for 10 seconds
    time.sleep(sleep_duration)

