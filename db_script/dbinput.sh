#!/bin/bash

# Define variables
DB_HOST=""
DB_USER=""
DB_PASS=""
DBS=("" "" "" "" "" "" "") # Update this with your actual database names
BACKUP_PATH=""

for DB_NAME in "${DBS[@]}"
do
    BACKUP_FILE_NAME="${DB_NAME}_$(date +%Y%m%d).sql"

    # Check if backup file exists
    if [ ! -f $BACKUP_PATH/$BACKUP_FILE_NAME ]; then
      echo "Backup file $BACKUP_PATH/$BACKUP_FILE_NAME does not exist."
      exit 1
    fi

    # Restore the database from the backup file
    mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_PATH/$BACKUP_FILE_NAME

    # Check if the restore was successful
    if [ $? -eq 0 ]; then
      echo "Restore of $DB_NAME has been completed successfully."
    else
      echo "Restore of $DB_NAME failed."
      exit 1
    fi

    # Sleep for a while before the next restore
    sleep_duration=10  # adjust this to your needs, this will wait for 20 seconds
    sleep $sleep_duration
done
