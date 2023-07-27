cat dbbackup.sh
#!/bin/bash

# Define variables
DB_HOST="" 
DB_USER=""
DB_PASS=""
DBS=("" "" "" "") # Update this with your actual database names
BACKUP_PATH=""

for DB_NAME in "${DBS[@]}"
do
    BACKUP_FILE_NAME="${DB_NAME}_$(date +%Y%m%d).sql"

    # Create a dump of the database
    mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME --set-gtid-purged=OFF > $BACKUP_PATH/$BACKUP_FILE_NAME

    # Check if the dump was successful
    if [ $? -eq 0 ]; then
      echo "Backup of $DB_NAME has been completed successfully. The backup file is located at $BACKUP_PATH/$BACKUP_FILE_NAME"
    else
      echo "Backup of $DB_NAME failed."
      exit 1
    fi

    # Sleep for a while before the next backup
    sleep_duration=10  # adjust this to your needs, this will wait for 60 seconds
    sleep $sleep_duration
done