#!/usr/bin/env python3

# GitLab User Deletion Script
# -------------------------
# This script deletes GitLab users and removes them from a specified group
# using the GitLab API.

import requests
import json
import sys
from typing import List, Optional, Dict, Any

class GitLabUserDeleter:
    """GitLab user deletion and management class."""
    
    def __init__(self, gitlab_url: str, private_token: str, group_name: str):
        """Initialize GitLab configuration.
        
        Args:
            gitlab_url: Base URL of your GitLab instance
            private_token: GitLab API access token with admin privileges
            group_name: Target group name for user removal
        """
        self.gitlab_url = gitlab_url.rstrip('/')
        self.private_token = private_token
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

    def _get_user_info(self, username: str) -> Optional[Dict[str, Any]]:
        """Get user information including user ID.
        
        Args:
            username: Username to look up
            
        Returns:
            User information dictionary if found, None otherwise
        """
        url = f"{self.gitlab_url}/api/v4/users"
        params = {'username': username}
        
        response = requests.get(url, headers=self.headers, params=params)
        if response.status_code == 200:
            users = response.json()
            if users:
                return users[0]
        return None

    def remove_from_group(self, user_id: int) -> bool:
        """Remove a user from the specified group.
        
        Args:
            user_id: ID of the user to remove
            
        Returns:
            True if successful, False otherwise
        """
        url = f"{self.gitlab_url}/api/v4/groups/{self.group_id}/members/{user_id}"
        response = requests.delete(url, headers=self.headers)
        return response.status_code in (200, 204)

    def delete_user(self, user_id: int) -> bool:
        """Delete a user from GitLab.
        
        Args:
            user_id: ID of the user to delete
            
        Returns:
            True if successful, False otherwise
        """
        url = f"{self.gitlab_url}/api/v4/users/{user_id}"
        response = requests.delete(url, headers=self.headers)
        return response.status_code in (200, 204)

    def process_users(self, usernames: List[str]) -> None:
        """Process a list of usernames for deletion.
        
        Args:
            usernames: List of usernames to process
        """
        for username in usernames:
            # Check if user exists
            user_info = self._get_user_info(username)
            if not user_info:
                print(f"⚠️  User '{username}' does not exist!")
                print("----------------------------------------")
                continue

            user_id = user_info['id']

            # Remove from group first
            print(f"🗑️  Removing '{username}' from group '{self.group_name}'")
            if not self.remove_from_group(user_id):
                print(f"❌ Failed to remove '{username}' from group")
                continue

            # Delete user
            print(f"🔧 Deleting user: {username}")
            if self.delete_user(user_id):
                print(f"✅ User '{username}' deleted successfully")
                print(f"✨ Done for {username}")
            else:
                print(f"❌ Failed to delete user '{username}'")
            
            print("")
            print("----------------------------------------")

def main():
    """Main function to run the GitLab user deletion process."""
    
    # GitLab Configuration Variables
    GITLAB_URL = ""  # Base URL of your GitLab instance
    PRIVATE_TOKEN = ""  # GitLab API access token with admin privileges
    GROUP_NAME = ""  # Target group name for user removal

    # List of users to be deleted
    USERNAMES = [
        "somaz",
        "somaz2"
    ]

    # Validate required configuration
    if not all([GITLAB_URL, PRIVATE_TOKEN, GROUP_NAME]):
        print("❌ Please fill in all required configuration variables!")
        sys.exit(1)

    # Create GitLab user deleter instance
    deleter = GitLabUserDeleter(
        gitlab_url=GITLAB_URL,
        private_token=PRIVATE_TOKEN,
        group_name=GROUP_NAME
    )

    # Process users
    deleter.process_users(USERNAMES)

if __name__ == "__main__":
    main() 