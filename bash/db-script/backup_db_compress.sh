#!/bin/bash

# Define variables
DB_HOST="your_db_host" 
DB_USER="your_db_user"
DB_PASS="your_db_password"
DBS=("db1" "db2" "db3" "db4")
BACKUP_PATH="your_backup_path"
BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="${BACKUP_PATH}/${BACKUP_DATE}"

# Create backup directory for today
sudo mkdir -p $BACKUP_DIR

for DB_NAME in "${DBS[@]}"
do
    BACKUP_FILE_NAME="${DB_NAME}_${BACKUP_DATE}.sql"

    # Create a dump of the database
    mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME --set-gtid-purged=OFF > "$BACKUP_DIR/$BACKUP_FILE_NAME"

    # Check if the dump was successful
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup of $DB_NAME completed successfully." | tee -a "${BACKUP_PATH}/backup.log"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup of $DB_NAME failed." | tee -a "${BACKUP_PATH}/backup.log"
        exit 1
    fi

    sleep_duration=10
    sleep $sleep_duration
done

# After all databases are backed up, create single tar.gz archive
COMPRESSED_FILE="${BACKUP_PATH}/backup_${BACKUP_DATE}.tar.gz"
tar -czf "$COMPRESSED_FILE" -C $BACKUP_PATH "${BACKUP_DATE}" && \
rm -rf "$BACKUP_DIR"

# Delete backups older than 30 days
find $BACKUP_PATH -name "backup_*.tar.gz" -mtime +30 -delete

echo "$(date '+%Y-%m-%d %H:%M:%S') - All backups compressed successfully to ${COMPRESSED_FILE}" | tee -a "${BACKUP_PATH}/backup.log"
