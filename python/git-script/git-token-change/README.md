# GitHub Secrets Bulk Updater

A Python script to bulk add/update `GITLAB_TOKEN` secrets across all GitHub repositories.

<br/>

## Features

- ✅ Bulk update secrets across all repositories
- ✅ Automatically add to repositories without the secret
- ✅ Dry-run mode support (for testing)
- ✅ Detailed progress display
- ✅ Automatic log file generation
- ✅ Support for both Organizations and personal accounts

<br/>

## Prerequisites

<br/>

### 1. Create GitHub Personal Access Token

1. Access GitHub website
2. **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
3. Click **Generate new token (classic)**
4. Select permissions:
   - ✅ `repo` (full)
   - ✅ `workflow`
   - ✅ `admin:org` (for Organizations, not required for personal accounts)
5. Click **Generate token**
6. Copy and securely store the generated token

<br/>

### 2. Prepare GitLab Token

Prepare your newly created GitLab Token.
```
Example: glpat-xxxxxxxxxxxxxxxxxxxx
```

<br/>

## Installation and Execution

<br/>

### 1. Clone Repository or Download Script
```bash
# Create directory
mkdir github-secrets-updater
cd github-secrets-updater

# Create script file (update_secrets.py)
# Copy and save the script code below
```

<br/>

### 2. Create Python Virtual Environment
```bash
# Check Python version (3.6 or higher required)
python3 --version

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# macOS/Linux:
source venv/bin/activate

# Windows:
# venv\Scripts\activate
```

<br/>

### 3. Install Required Packages
```bash
pip install --upgrade pip
pip install PyNaCl requests
```

<br/>

### 4. Configure Script

Open the `update_secrets.py` file and modify the following variables:
```python
# ==================== Configuration ====================
GITHUB_TOKEN = ''  # Leave empty and use environment variable (recommended)
GITHUB_ORG = 'somaz94'  # Your GitHub username or organization name
NEW_GITLAB_TOKEN = ''  # New GitLab Token
SECRET_NAME = 'GITLAB_TOKEN'

# Dry-run mode (If True, no actual updates)
DRY_RUN = True  # Test with True first!
# ======================================================
```

<br/>

### 5. Set Environment Variables (Recommended)
```bash
# Set GitHub Token as environment variable
export GITHUB_TOKEN='ghp_your_github_token_here'

# GitLab Token can also be set as environment variable (optional)
export GITLAB_TOKEN='glpat_your_gitlab_token_here'
```

<br/>

### 6. Dry-run Test
```bash
# Run with DRY_RUN = True
python3 update_secrets.py
```

Example output:
```bash
============================================================
GitHub Repository Secrets Update
============================================================

Organization: somaz94
Secret Name: GITLAB_TOKEN
Dry Run: True
⚠ DRY-RUN mode: No actual updates will be made.

...

[1/45] somaz94/repo1
✓ Secret updated (dry-run)

[2/45] somaz94/repo2
✓ Secret added (dry-run)
```

<br/>

### 7. Run Actual Update

If there are no issues, change to `DRY_RUN = False` and run:
```python
DRY_RUN = False  # Actual update mode
```
```bash
python3 update_secrets.py
```

When confirmation message appears, type `yes`:
```
Do you really want to update GITLAB_TOKEN in all repositories?
Type 'yes' to continue: yes
```

<br/>

## Execution Results

<br/>

### Success Output
```
============================================================
3. Summary
============================================================

Total Repositories: 45
✓ Updated: 30
✓ Added: 15
✗ Failed: 0

Log file saved: github_secrets_update_20241224_153045.log

============================================================
Complete!
============================================================
```

<br/>

### Log File

A log file is automatically created after execution:
```
github_secrets_update_20241224_153045.log
```

Example content:
```
GitHub Secrets Update Log
============================================================

Time: 2024-12-24 15:30:45
Organization: somaz94
Secret Name: GITLAB_TOKEN
Dry Run: False

Results:
  Total: 45
  Updated: 30
  Added: 15
  Failed: 0
```

<br/>

## Troubleshooting

<br/>

### 1. Authentication Error
```
Failed to fetch repository list: HTTP 401
```

**Solution:**
- Verify GitHub Token is correct
- Confirm token has `repo` and `workflow` permissions

<br/>

### 2. Organization Access Denied
```
Failed to fetch repository list: HTTP 404
```

**Solution:**
- Verify organization name is correct
- Use username for personal accounts
- For organizations, `admin:org` permission is required

<br/>

### 3. Secret Update Failed
```
✗ Failed: Failed to get public key: HTTP 403
```

**Solution:**
- Verify Actions are enabled in the repository
- Confirm token has `workflow` permission

<br/>

### 4. PyNaCl Installation Error
```bash
# macOS
brew install libsodium
pip install PyNaCl

# Ubuntu/Debian
sudo apt-get install libsodium-dev
pip install PyNaCl
```

<br/>

## Important Notes

⚠️ **Critical Information:**

1. **Run Dry-run First**: Always test with `DRY_RUN = True` before actual update
2. **Token Security**: Use environment variables instead of hardcoding GitHub and GitLab tokens
3. **Backup**: Backup secrets from important repositories beforehand
4. **Verify Permissions**: Confirm appropriate permissions for Organizations

<br/>

## Environment Variable Usage Example

Create `.env` file:
```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
GITLAB_TOKEN=glpat_xxxxxxxxxxxxxxxxxxxx
```

Use in script:
```python
import os
from dotenv import load_dotenv

load_dotenv()

GITHUB_TOKEN = os.getenv('GITHUB_TOKEN')
NEW_GITLAB_TOKEN = os.getenv('GITLAB_TOKEN')
```

<br/>

## Deactivate Virtual Environment

After completing work:
```bash
deactivate
```