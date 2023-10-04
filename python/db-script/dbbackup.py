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

    # Create a dump of the backup_path
    os.makedirs(BACKUP_PATH, exist_ok=True)

    # Create a dump of the database
    command = ["mysqldump", "-h", DB_HOST, "-u", DB_USER, "--set-gtid-purged=OFF", DB_NAME]
    with open(os.path.join(BACKUP_PATH, BACKUP_FILE_NAME), 'w') as f:
        result = subprocess.run(command, stdout=f, env={"MYSQL_PWD": DB_PASS})

    # Check if the dump was successful
    if result.returncode == 0:
        print("Backup of {} has been completed successfully. The backup file is located at {}/{}".format(DB_NAME, BACKUP_PATH, BACKUP_FILE_NAME))
    else:
        print("Backup of {} failed.".format(DB_NAME))
        exit(1)

    # Sleep for a while before the next backup
    sleep_duration = 10  # adjust this to your needs, this will wait for 10 seconds
    time.sleep(sleep_duration)

