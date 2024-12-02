#!/bin/bash

# Define variables
DB_HOST="your_db_host" 
DB_USER="your_db_user"
DB_PASS="your_db_password"
DBS=("db1" "db2" "db3" "db4") # Update this with your actual database names
BACKUP_PATH="your_backup_path"

for DB_NAME in "${DBS[@]}"
do
    BACKUP_FILE_NAME="${DB_NAME}_$(date +%Y%m%d).sql"

    # Check if backup file exists
    if [ ! -f $BACKUP_PATH/$BACKUP_FILE_NAME ]; then
      echo "Backup file $BACKUP_PATH/$BACKUP_FILE_NAME does not exist."
      exit 1
    fi

    # Check if the database exists
    DB_EXISTS=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -e "SHOW DATABASES LIKE '$DB_NAME';" | grep "$DB_NAME" > /dev/null; echo "$?")
    
    # If the database does not exist, create it
    if [ $DB_EXISTS -ne 0 ]; then
        echo "Database $DB_NAME does not exist. Creating..."
        mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
        if [ $? -eq 0 ]; then
            echo "Database $DB_NAME created successfully."
        else
            echo "Failed to create database $DB_NAME."
            continue # Skip to the next database
        fi
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
