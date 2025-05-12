#!/usr/bin/env python3

# GitLab User Creation Script
# -------------------------
# This script creates GitLab users and adds them to a specified group
# using the GitLab API.

import requests
import json
import sys
from typing import List, Optional

class GitLabUserCreator:
    """GitLab user creation and management class."""
    
    def __init__(self, gitlab_url: str, private_token: str, default_password: str, 
                 email_domain: str, group_name: str):
        """Initialize GitLab configuration.
        
        Args:
            gitlab_url: Base URL of your GitLab instance
            private_token: GitLab API access token with admin privileges
            default_password: Initial password for new users
            email_domain: Domain for user email addresses
            group_name: Target group name for user membership
        """
        self.gitlab_url = gitlab_url.rstrip('/')
        self.private_token = private_token
        self.default_password = default_password
        self.email_domain = email_domain
        self.group_name = group_name
        self.headers = {'PRIVATE-TOKEN': private_token}
        
        # Get group ID during initialization
        self.group_id = self._get_group_id()
        if not self.group_id:
            print(f"❌ Group '{group_name}' not found!")
            sys.exit(1)
        print(f"📦 Found Group '{group_name}' with ID: {self.group_id}")
        print("----------------------------------------")

    def _get_group_id(self) -> Optional[int]:
        """Get the group ID using the group name.
        
        Returns:
            Group ID if found, None otherwise
        """
        url = f"{self.gitlab_url}/api/v4/groups"
        params = {'search': self.group_name}
        
        response = requests.get(url, headers=self.headers, params=params)
        if response.status_code == 200:
            groups = response.json()
            if groups:
                return groups[0]['id']
        return None

    def _user_exists(self, username: str) -> bool:
        """Check if a user already exists.
        
        Args:
            username: Username to check
            
        Returns:
            True if user exists, False otherwise
        """
        url = f"{self.gitlab_url}/api/v4/users"
        params = {'username': username}
        
        response = requests.get(url, headers=self.headers, params=params)
        if response.status_code == 200:
            users = response.json()
            return len(users) > 0
        return False

    def create_user(self, username: str) -> Optional[int]:
        """Create a new GitLab user.
        
        Args:
            username: Username for the new user
            
        Returns:
            User ID if creation successful, None otherwise
        """
        email = f"{username}@{self.email_domain}"
        name = username
        
        url = f"{self.gitlab_url}/api/v4/users"
        data = {
            'email': email,
            'username': username,
            'name': name,
            'password': self.default_password,
            'skip_confirmation': True
        }
        
        response = requests.post(url, headers=self.headers, data=data)
        if response.status_code == 201:
            return response.json()['id']
        return None

    def add_user_to_group(self, user_id: int) -> bool:
        """Add a user to the specified group with Maintainer access level.
        
        Args:
            user_id: ID of the user to add
            
        Returns:
            True if successful, False otherwise
        """
        url = f"{self.gitlab_url}/api/v4/groups/{self.group_id}/members"
        data = {
            'user_id': user_id,
            'access_level': 40  # 40: Maintainer, 30: Developer
        }
        
        response = requests.post(url, headers=self.headers, data=data)
        return response.status_code in (200, 201)

    def process_users(self, usernames: List[str]) -> None:
        """Process a list of usernames for creation and group assignment.
        
        Args:
            usernames: List of usernames to process
        """
        for username in usernames:
            # Check if user exists
            if self._user_exists(username):
                print(f"⚠️  User '{username}' already exists!")
                print("----------------------------------------")
                continue

            # Create user
            print(f"🔧 Creating user: {username}")
            user_id = self.create_user(username)
            
            if not user_id:
                print(f"❌ Failed to create user '{username}'")
                print("----------------------------------------")
                continue

            print(f"✅ User '{username}' created with ID: {user_id}")

            # Add to group
            print(f"👥 Adding '{username}' to group '{self.group_name}'")
            if self.add_user_to_group(user_id):
                print(f"✨ Done for {username}")
            else:
                print(f"❌ Failed to add '{username}' to group")
            
            print("")
            print("----------------------------------------")

def main():
    """Main function to run the GitLab user creation process."""
    
    # GitLab Configuration Variables
    GITLAB_URL = ""  # Base URL of your GitLab instance
    PRIVATE_TOKEN = ""  # GitLab API access token with admin privileges
    DEFAULT_PASSWORD = ""  # Initial password for new users
    EMAIL_DOMAIN = ""  # Domain for user email addresses
    GROUP_NAME = ""  # Target group name for user membership

    # List of users to be created
    USERNAMES = [
        "somaz",
        "somaz2"
    ]

    # Validate required configuration
    if not all([GITLAB_URL, PRIVATE_TOKEN, DEFAULT_PASSWORD, EMAIL_DOMAIN, GROUP_NAME]):
        print("❌ Please fill in all required configuration variables!")
        sys.exit(1)

    # Create GitLab user creator instance
    creator = GitLabUserCreator(
        gitlab_url=GITLAB_URL,
        private_token=PRIVATE_TOKEN,
        default_password=DEFAULT_PASSWORD,
        email_domain=EMAIL_DOMAIN,
        group_name=GROUP_NAME
    )

    # Process users
    creator.process_users(USERNAMES)

if __name__ == "__main__":
    main() 