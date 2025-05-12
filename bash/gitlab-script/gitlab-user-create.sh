#!/bin/bash

# GitLab Configuration Variables
# ---------------------------
# GITLAB_URL: Base URL of your GitLab instance
# PRIVATE_TOKEN: GitLab API access token with admin privileges
# DEFAULT_PASSWORD: Initial password for new users
# EMAIL_DOMAIN: Domain for user email addresses
# GROUP_NAME: Target group name for user membership
GITLAB_URL=""
PRIVATE_TOKEN=""
DEFAULT_PASSWORD=""
EMAIL_DOMAIN=""
GROUP_NAME=""

# List of users to be created
# Add or remove usernames as needed
USERNAMES=(
  somaz
  somaz2
)

# Group Information Retrieval
# -------------------------
# Get the group ID using the group name
# This ID is required for adding users to the group
GROUP_ID=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/groups?search=$GROUP_NAME" | jq ".[0].id")

echo "📦 Found Group '$GROUP_NAME' with ID: $GROUP_ID"
echo "----------------------------------------"

# User Creation Loop
# ----------------
# Process each username in the USERNAMES array
for USERNAME in "${USERNAMES[@]}"; do
  # Generate email address for the user
  EMAIL="${USERNAME}@${EMAIL_DOMAIN}"
  # Set display name (using username as default)
  NAME="$USERNAME"

  # Check for existing user
  # Prevents duplicate user creation
  EXISTING_USER=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/users?username=$USERNAME" | jq '.[0]')

  # Skip if user already exists
  if [ "$EXISTING_USER" != "null" ]; then
    echo "⚠️  User '$USERNAME' already exists!"
    echo "----------------------------------------"
    continue
  fi

  # User Creation
  # ------------
  # Create new user with specified parameters
  # skip_confirmation=true allows immediate access without email verification
  echo "🔧 Creating user: $USERNAME ($EMAIL)"
  USER_ID=$(curl -s --request POST "$GITLAB_URL/api/v4/users" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "email=$EMAIL&username=$USERNAME&name=$NAME&password=$DEFAULT_PASSWORD&skip_confirmation=true" \
    | jq '.id')

  # Verify user creation success
  if [ "$USER_ID" = "null" ]; then
    echo "❌ Failed to create user '$USERNAME'"
    echo "----------------------------------------"
    continue
  fi

  echo "✅ User '$USERNAME' created with ID: $USER_ID"

  # Group Membership Management
  # --------------------------
  # Add user to specified group with Maintainer access level
  # Access levels:
  # - 40: Maintainer
  # - 30: Developer
  echo "👥 Adding '$USERNAME' to group '$GROUP_NAME'"
  curl -s --request POST "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "user_id=$USER_ID&access_level=40" # Maintainer access level=30 Developer access level=40 Maintainer

  echo "✨ Done for $USERNAME"
  echo ""
  echo "----------------------------------------"
done

