#!/bin/bash

# Define variables
DB_HOST=""
DB_USER=""
DB_PASS=""
DBS=("") # Update this with your actual database names
BACKUP_PATH="/home/nerdystar/DB"
TABLES_TO_BACKUP=("")  # Fill this array with the specific table name you want to back up

for DB_NAME in "${DBS[@]}"
do
    for TABLE_NAME in "${TABLES_TO_BACKUP[@]}"
    do
        BACKUP_FILE_NAME="${DB_NAME}_${TABLE_NAME}_$(date +%Y%m%d).sql"

        # Create a dump of the backup_path
        sudo mkdir -p $BACKUP_PATH

        # Create a dump of the database for specific tables with no locking
        mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME $TABLE_NAME --single-transaction --set-gtid-purged=OFF > $BACKUP_PATH/$BACKUP_FILE_NAME

        # Check if the dump was successful
        if [ $? -eq 0 ]; then
          echo "Backup of $DB_NAME $TABLE_NAME has been completed successfully. The backup file is located at $BACKUP_PATH/$BACKUP_FILE_NAME"
        else
          echo "Backup of $DB_NAME $TABLE_NAME failed."
          exit 1
        fi
    done
    # Sleep for a while before the next backup
    sleep_duration=10  # adjust this to your needs, this will wait for 10 seconds
    sleep $sleep_duration
done
