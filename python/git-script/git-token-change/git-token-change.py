#!/usr/bin/env python3
"""
GitHub Repository Secrets Bulk Updater
Bulk add/update secrets across all repositories.
"""

import os
import sys
import requests
from base64 import b64encode
from nacl import encoding, public
from datetime import datetime

# ==================== Configuration ====================
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', '')  # Or set directly
GITHUB_ORG = ''  # Organization name or username
SECRET_NAME = 'GITLAB_TOKEN'  # Secret name to update
SECRET_VALUE = os.environ.get('SECRET_VALUE', '')  # Secret value (environment variable recommended)

# Dry-run mode (If True, no actual updates)
DRY_RUN = False

# =======================================================

class Colors:
    """Terminal colors"""
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    """Print header"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}\n")

def print_success(text):
    """Print success message"""
    print(f"{Colors.GREEN}✓ {text}{Colors.RESET}")

def print_warning(text):
    """Print warning message"""
    print(f"{Colors.YELLOW}⚠ {text}{Colors.RESET}")

def print_error(text):
    """Print error message"""
    print(f"{Colors.RED}✗ {text}{Colors.RESET}")

def encrypt_secret(public_key: str, secret_value: str) -> str:
    """Encrypt GitHub Secret"""
    try:
        pk = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
        sealed_box = public.SealedBox(pk)
        encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
        return b64encode(encrypted).decode("utf-8")
    except Exception as e:
        raise Exception(f"Encryption failed: {e}")

def get_all_repos(org: str, token: str):
    """Get all repositories (with pagination)"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    repos = []
    page = 1
    
    print("Fetching repository list...")
    
    while True:
        url = f'https://api.github.com/orgs/{org}/repos?per_page=100&page={page}'
        # For personal accounts (not organization):
        # url = f'https://api.github.com/users/{org}/repos?per_page=100&page={page}'
        
        response = requests.get(url, headers=headers)
        
        if response.status_code == 404:
            # Try personal repositories if not an organization
            url = f'https://api.github.com/users/{org}/repos?per_page=100&page={page}'
            response = requests.get(url, headers=headers)
        
        if response.status_code != 200:
            print_error(f"Failed to fetch repository list: HTTP {response.status_code}")
            print_error(f"Response: {response.text}")
            sys.exit(1)
        
        data = response.json()
        if not data:
            break
        
        repos.extend([repo['name'] for repo in data])
        print(f"  Page {page}: {len(data)} found (Total: {len(repos)})")
        page += 1
    
    return repos

def check_secret_exists(org: str, repo: str, secret_name: str, token: str):
    """Check if secret exists"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/{secret_name}'
    response = requests.get(url, headers=headers)
    
    return response.status_code == 200

def update_secret(org: str, repo: str, secret_name: str, secret_value: str, token: str, dry_run=False):
    """Update/add secret"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    try:
        # 1. Check if secret exists
        exists = check_secret_exists(org, repo, secret_name, token)
        action = 'update' if exists else 'add'
        
        if dry_run:
            return True, f'Would {action} (dry-run)', action
        
        # 2. Get public key
        key_url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/public-key'
        key_response = requests.get(key_url, headers=headers)
        
        if key_response.status_code != 200:
            return False, f'Failed to get public key: HTTP {key_response.status_code}', action
        
        key_data = key_response.json()
        key_id = key_data['key_id']
        public_key = key_data['key']
        
        # 3. Encrypt secret
        encrypted_value = encrypt_secret(public_key, secret_value)
        
        # 4. Update secret
        secret_url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/{secret_name}'
        secret_data = {
            'encrypted_value': encrypted_value,
            'key_id': key_id
        }
        
        response = requests.put(secret_url, headers=headers, json=secret_data)
        
        if response.status_code in [201, 204]:
            return True, 'Success', action
        else:
            return False, f'HTTP {response.status_code}: {response.text}', action
            
    except Exception as e:
        return False, str(e), 'error'

def save_log(stats, failed_repos):
    """Save log file"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_file = f'github_secrets_update_{timestamp}.log'
    
    with open(log_file, 'w') as f:
        f.write(f"GitHub Secrets Update Log\n")
        f.write(f"{'='*60}\n\n")
        f.write(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Organization: {GITHUB_ORG}\n")
        f.write(f"Secret Name: {SECRET_NAME}\n")
        f.write(f"Dry Run: {DRY_RUN}\n\n")
        f.write(f"Results:\n")
        f.write(f"  Total: {stats['total']}\n")
        f.write(f"  Updated: {stats['updated']}\n")
        f.write(f"  Added: {stats['added']}\n")
        f.write(f"  Failed: {stats['failed']}\n\n")
        
        if failed_repos:
            f.write(f"Failed Repositories:\n")
            for repo, reason in failed_repos:
                f.write(f"  - {repo}: {reason}\n")
    
    return log_file

def main():
    """Main function"""
    
    # Input validation
    if not GITHUB_TOKEN:
        print_error("GITHUB_TOKEN is not set!")
        print("Set it as an environment variable or directly in the script:")
        print("  export GITHUB_TOKEN='your_token_here'")
        sys.exit(1)
    
    if not SECRET_VALUE:
        print_error("SECRET_VALUE is not set!")
        print("Set it as an environment variable or directly in the script:")
        print("  export SECRET_VALUE='your_secret_value_here'")
        sys.exit(1)
    
    print_header(f"GitHub Repository Secrets Update")
    
    print(f"Organization: {Colors.BOLD}{GITHUB_ORG}{Colors.RESET}")
    print(f"Secret Name: {Colors.BOLD}{SECRET_NAME}{Colors.RESET}")
    print(f"Dry Run: {Colors.BOLD}{DRY_RUN}{Colors.RESET}")
    
    if DRY_RUN:
        print_warning("DRY-RUN mode: No actual updates will be made.")
    
    # Confirmation
    if not DRY_RUN:
        print(f"\n{Colors.YELLOW}Do you really want to update {SECRET_NAME} in all repositories?{Colors.RESET}")
        confirm = input("Type 'yes' to continue: ")
        if confirm.lower() != 'yes':
            print("Cancelled.")
            sys.exit(0)
    
    # Get repository list
    print_header("1. Fetching Repository List")
    repos = get_all_repos(GITHUB_ORG, GITHUB_TOKEN)
    print_success(f"Found {len(repos)} repositories")
    
    # Update secrets
    print_header("2. Updating Secrets...")
    
    stats = {'total': 0, 'updated': 0, 'added': 0, 'failed': 0}
    failed_repos = []
    
    for idx, repo in enumerate(repos, 1):
        stats['total'] += 1
        print(f"\n[{idx}/{len(repos)}] {Colors.BOLD}{GITHUB_ORG}/{repo}{Colors.RESET}")
        
        success, message, action = update_secret(
            GITHUB_ORG, repo, SECRET_NAME, SECRET_VALUE, GITHUB_TOKEN, DRY_RUN
        )
        
        if success:
            if action == 'add':
                stats['added'] += 1
                print_success(f"Secret added")
            else:
                stats['updated'] += 1
                print_success(f"Secret updated")
        else:
            stats['failed'] += 1
            print_error(f"Failed: {message}")
            failed_repos.append((repo, message))
    
    # Summary
    print_header("3. Summary")
    print(f"Total Repositories: {Colors.BOLD}{stats['total']}{Colors.RESET}")
    print_success(f"Updated: {stats['updated']}")
    print_success(f"Added: {stats['added']}")
    if stats['failed'] > 0:
        print_error(f"Failed: {stats['failed']}")
    
    # Failed repositories details
    if failed_repos:
        print(f"\n{Colors.RED}Failed Repositories:{Colors.RESET}")
        for repo, reason in failed_repos:
            print(f"  - {repo}: {reason}")
    
    # Save log
    log_file = save_log(stats, failed_repos)
    print(f"\nLog file saved: {Colors.BOLD}{log_file}{Colors.RESET}")
    
    print_header("Complete!")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Interrupted by user.{Colors.RESET}")
        sys.exit(0)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
