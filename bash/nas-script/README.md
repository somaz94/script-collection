# NAS User Management Scripts

This directory contains scripts for managing users on a Synology NAS system through their API.

<br/>

## Scripts

<br/>

### 1. nas-user-create.sh

This script creates new users on the Synology NAS and adds them to a specified group.

#### Features:
- Creates user accounts with default settings (email, password, description)
- Adds users to a specified group
- Prevents duplicate user creation by checking for existing accounts
- Uses both the Synology API and direct synogroup commands

#### Usage:
1. Edit the script to configure NAS connection settings
2. Add the usernames to be created in the `USERNAMES` array
3. Run the script:
   ```
   ./nas-user-create.sh
   ```

<br/>

### 2. nas-user-delete.sh

This script deletes users from the Synology NAS.

#### Features:
- Verifies if users exist before attempting deletion
- Safely removes user accounts from the NAS system
- Provides detailed success/failure information

#### Usage:
1. Edit the script to configure NAS connection settings
2. Add the usernames to be deleted in the `USERNAMES` array
3. Run the script:
   ```
   ./nas-user-delete.sh
   ```

<br/>

## Configuration

Both scripts use the following configuration variables:

| Variable | Description |
|----------|-------------|
| NAS_IP | IP address of the Synology NAS |
| NAS_URL | Base URL for NAS API access |
| ADMIN_USERNAME | Administrator username for NAS access |
| ADMIN_PASSWORD | Administrator password for NAS access |
| EMAIL_DOMAIN | Domain for user email addresses (create script only) |
| GROUP_NAME | Default group to add/verify users |
| DEFAULT_PASSWORD | Initial password for new users (create script only) |
| DESCRIPTION | Default description for new users (create script only) |

<br/>

## Requirements

- bash
- curl
- jq (for JSON parsing)
- sshpass (for SSH access on user creation)

<br/>

## Security Note

These scripts contain sensitive information like admin credentials. It's recommended to:
1. Restrict access permissions to the script files
2. Consider using environment variables or a secure vault for credentials
3. Change default passwords after user creation

<br/>

## Troubleshooting

If you encounter errors:
1. Verify NAS connection settings
2. Ensure admin credentials are correct
3. Check if the target group exists
4. Review script output for detailed error messages 
