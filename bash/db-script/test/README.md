# MySQL Database Backup and Restore Scripts

This repository contains scripts and configurations for MySQL database backup and restore operations in a Kubernetes environment.

## Files
- `backup_db_compress.sh`: Script for backing up multiple MySQL databases and compressing them into a single tar.gz file
- `restore_db_compress.sh`: Script for restoring MySQL databases from a compressed backup
- `mysql.yaml`: Kubernetes manifest file for deploying MySQL with necessary configurations

## Prerequisites
- Kubernetes cluster
- NFS storage class configured
- MySQL client installed on the machine running the scripts

## Configuration

### MySQL Deployment (`mysql.yaml`)
- Deploys MySQL instance with persistent storage
- Creates initial databases and user permissions
- Configures NodePort service for external access
- Includes initialization scripts via ConfigMap

### Backup Script (`backup_db_compress.sh`)
- Backs up specified databases (`db1`, `db2`, `db3`, `db4`)
- Creates daily backup directory
- Compresses all backups into a single tar.gz file
- Automatically removes backups older than 30 days
- Logs backup operations

### Restore Script (`restore_db_compress.sh`)
- Restores databases from compressed backup file
- Creates databases if they don't exist
- Handles error checking and logging
- Includes cleanup of temporary files

## Usage

### Deploy MySQL
```bash
kubectl apply -f mysql.yaml
```

### Backup Databases
```bash
./backup_db_compress.sh
```

### Restore Databases
```bash
./restore_db_compress.sh
```

## Backup File Structure
```
backup/
└── backup_YYYYMMDD.tar.gz
    └── YYYYMMDD/
        ├── db1_YYYYMMDD.sql
        ├── db2_YYYYMMDD.sql
        ├── db3_YYYYMMDD.sql
        └── db4_YYYYMMDD.sql
```

## Configuration Variables
Both scripts use the following variables that should be configured:
- `DB_HOST`: MySQL host address
- `DB_PORT`: MySQL port number
- `DB_USER`: MySQL username
- `DB_PASS`: MySQL password
- `BACKUP_PATH`: Path for storing backups

## Notes
- Backup files are automatically compressed and old backups are cleaned up
- Restore process includes automatic database creation if needed
- All operations are logged for monitoring and debugging
```

This README provides a comprehensive overview of the scripts and their usage, including the file structure, prerequisites, and configuration details.

