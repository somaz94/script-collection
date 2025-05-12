#!/bin/bash

# GitLab Configuration Variables
# ---------------------------
# GITLAB_URL: Base URL of your GitLab instance
# PRIVATE_TOKEN: GitLab API access token with admin privileges
# GROUP_NAME: Target group name for user removal
GITLAB_URL=""
PRIVATE_TOKEN=""
GROUP_NAME=""

# List of users to be deleted
# Add or remove usernames as needed
USERNAMES=(
  somaz
  somaz2
)

# Group Information Retrieval
# -------------------------
# Get the group ID using the group name
# This ID is required for removing users from the group
GROUP_ID=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/groups?search=$GROUP_NAME" | jq ".[0].id")

echo "📦 Found Group '$GROUP_NAME' with ID: $GROUP_ID"
echo "----------------------------------------"

# User Deletion Loop
# ----------------
# Process each username in the USERNAMES array
for USERNAME in "${USERNAMES[@]}"; do
  # Check for existing user
  # Verifies if the user exists before attempting deletion
  EXISTING_USER=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/users?username=$USERNAME" | jq '.[0]')
  
  # Skip if user doesn't exist
  if [ "$EXISTING_USER" = "null" ]; then
    echo "⚠️  User '$USERNAME' does not exist!"
    echo "----------------------------------------"
    continue
  fi
  
  # Extract User ID
  # Required for both group removal and user deletion
  USER_ID=$(echo $EXISTING_USER | jq '.id')
  
  # Group Membership Removal
  # ----------------------
  # Remove user from the specified group
  # This must be done before user deletion to avoid orphaned references
  echo "🗑️  Removing '$USERNAME' from group '$GROUP_NAME'"
  curl -s --request DELETE "$GITLAB_URL/api/v4/groups/$GROUP_ID/members/$USER_ID" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN"

  # User Deletion
  # ------------
  # Delete the user account from GitLab
  # This is a permanent operation and cannot be undone
  echo "🔧 Deleting user: $USERNAME"
  curl -s --request DELETE "$GITLAB_URL/api/v4/users/$USER_ID" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN"

  echo "✅ User '$USERNAME' deleted successfully"
  echo "✨ Done for $USERNAME"
  echo ""
  echo "----------------------------------------"
done 
