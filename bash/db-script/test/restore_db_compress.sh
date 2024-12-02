#!/bin/bash

# Define variables
DB_HOST="10.10.10.50" 
DB_PORT="30736" 
DB_USER="somaz"
DB_PASS="somaz"
DBS=("db1" "db2" "db3" "db4")
BACKUP_PATH="backup"
BACKUP_DATE=$(date +%Y%m%d)
COMPRESSED_FILE="${BACKUP_PATH}/backup_${BACKUP_DATE}.tar.gz"
TEMP_DIR="${BACKUP_PATH}/temp_restore_${BACKUP_DATE}"

# Extract the backup files
mkdir -p $TEMP_DIR
tar -xzf $COMPRESSED_FILE --strip-components=1 -C $TEMP_DIR 

for DB_NAME in "${DBS[@]}"
do
    BACKUP_FILE_NAME="${DB_NAME}_${BACKUP_DATE}.sql"
    BACKUP_FILE_PATH="${TEMP_DIR}/${BACKUP_FILE_NAME}"  

    # Check if backup file exists
    if [ ! -f $BACKUP_FILE_PATH ]; then
      echo "Backup file $BACKUP_FILE_PATH does not exist."
      exit 1
    fi

    # Check if the database exists (포트 추가)
    DB_EXISTS=$(mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS -e "SHOW DATABASES LIKE '$DB_NAME';" | grep "$DB_NAME" > /dev/null; echo "$?")
    
    # If the database does not exist, create it (포트 추가)
    if [ $DB_EXISTS -ne 0 ]; then
        echo "Database $DB_NAME does not exist. Creating..."
        mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
        if [ $? -eq 0 ]; then
            echo "Database $DB_NAME created successfully."
        else
            echo "Failed to create database $DB_NAME."
            continue # Skip to the next database
        fi
    fi

    # Restore the database from the backup file (포트 추가)
    mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE_PATH

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

# Clean up temporary files
rm -rf $TEMP_DIR