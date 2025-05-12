# GitLab Management Scripts

This collection of Python scripts provides tools for managing GitLab instances, including user management, system upgrades, and health monitoring.

<br/>

## Prerequisites

- Python 3.6 or higher
- GitLab instance with API access
- GitLab API token with appropriate permissions
- Sudo privileges for system-level operations

<br/>

## Installation

1. Clone the repository or copy the scripts to your desired location

2. Create and activate a virtual environment:
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate
```

3. Install the required dependencies:
```bash
pip install -r requirements.txt
```

4. (Optional) Verify the installation:
```bash
# Check installed packages
pip3 list

# Check Python version
python3 --version
```

<br/>

## Available Scripts

<br/>

### 1. GitLab User Management

#### User Creation (`gitlab-user-create.py`)
Creates new GitLab users and adds them to specified groups.

```bash
python gitlab-user-create.py
```

Configuration required in script:
- `GITLAB_URL`: Your GitLab instance URL
- `PRIVATE_TOKEN`: GitLab API token with admin privileges
- `DEFAULT_PASSWORD`: Initial password for new users
- `EMAIL_DOMAIN`: Domain for user email addresses
- `GROUP_NAME`: Target group name
- `USERNAMES`: List of usernames to create

#### User Deletion (`gitlab-user-delete.py`)
Removes users from GitLab and their associated group memberships.

```bash
python gitlab-user-delete.py
```

Configuration required in script:
- `GITLAB_URL`: Your GitLab instance URL
- `PRIVATE_TOKEN`: GitLab API token with admin privileges
- `GROUP_NAME`: Target group name
- `USERNAMES`: List of usernames to delete

<br/>

### 2. GitLab Upgrade (`gitlab-upgrade.py`)
Automates the process of upgrading GitLab to a specified version.

```bash
sudo python gitlab-upgrade.py
```

Configuration required in script:
- `version`: Target GitLab version (e.g., "16.3.4-ce.0")

<br/>

### 3. VM Health Check (`gitlab-vm-check.py`)
Performs comprehensive health checks on the GitLab VM, including:
- System resources (CPU, RAM, Disk)
- Operating system information
- Service status
- Kubernetes cluster status
- Network configuration

```bash
sudo python gitlab-vm-check.py
```

<br/>

## Features

<br/>

### User Management Scripts
- Create/delete users with proper error handling
- Group membership management
- Email domain configuration
- Detailed operation logging
- Type-safe implementation

<br/>

### Upgrade Script
- Automated version upgrade
- Package management
- Service reconfiguration
- Automatic restart

<br/>

### Health Check Script
- System resource monitoring
- Service status verification
- Kubernetes cluster health
- Network configuration check
- Disk space monitoring
- Security status verification

<br/>

## Security Notes

1. Always use secure API tokens with minimum required permissions
2. Store sensitive information (tokens, passwords) securely
3. Run system-level scripts with appropriate sudo privileges
4. Regularly update dependencies for security patches

<br/>

## Error Handling

All scripts include comprehensive error handling:
- API request failures
- Invalid configurations
- System-level operation failures
- Network connectivity issues
