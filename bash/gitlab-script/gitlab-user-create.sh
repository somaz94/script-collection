#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -h/--help guard — running without args immediately calls the GitLab API
case "${1:-}" in
  -h|--help)
    cat <<USAGE
Usage: ./${0##*/} [-h | --help]

  Create users on the new GitLab instance and add them to GROUP_NAME.

  Target users: USERNAMES array at the top of the script (edit before running)
  Server config: GITLAB_URL, PRIVATE_TOKEN, DEFAULT_PASSWORD, EMAIL_DOMAIN, GROUP_NAME (top of script)

Options:
  -h, --help    Show this help and exit

Flow:
  1) Resolve GROUP_NAME -> group ID via GitLab API
  2) Iterate USERNAMES: create user, then add as group member
USAGE
    exit 0
    ;;
esac

# GitLab Configuration Variables
# ---------------------------
# GITLAB_URL: Base URL of your GitLab instance
# PRIVATE_TOKEN: GitLab API access token with admin privileges
# DEFAULT_PASSWORD: Initial password for new users
# EMAIL_DOMAIN: Domain for user email addresses
# GROUP_NAME: Target group name for user membership
GITLAB_URL="http://gitlab.example.com"
PRIVATE_TOKEN="<your-gitlab-token>"
DEFAULT_PASSWORD="CHANGE_ME"
EMAIL_DOMAIN="example.com"
GROUP_NAME="server"

# List of users to be created
# Add or remove usernames as needed
USERNAMES=(
  sunddu
)

# Group Information Retrieval
# -------------------------
# Get the group ID using the group name
# This ID is required for adding users to the group
GROUP_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/groups?search=$GROUP_NAME")
GROUP_ID=$(echo "$GROUP_RESPONSE" | jq ".[0].id")

# Check for API errors or if group not found
if [[ "$GROUP_ID" == "null" || -z "$GROUP_ID" ]]; then
  echo "✗ Error: Could not retrieve Group ID for '$GROUP_NAME'."
  echo "   GitLab API Response: $GROUP_RESPONSE"
  echo "----------------------------------------"
  exit 1
fi

echo "✔ Found Group '$GROUP_NAME' with ID: $GROUP_ID"
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
  EXISTING_USER_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/users?username=$USERNAME")
  
  # jq returns "null" if user doesn't exist, or an empty string if there's an API error.
  EXISTING_USER_ID=$(echo "$EXISTING_USER_RESPONSE" | jq '.[0].id')
  
  # Skip if user already exists
  if [[ "$EXISTING_USER_ID" != "null" && -n "$EXISTING_USER_ID" ]]; then
    echo "▲  User '$USERNAME' already exists with ID: $EXISTING_USER_ID"
    echo "----------------------------------------"
    continue
  elif [[ "$EXISTING_USER_ID" != "null" ]]; then
    # This case handles API errors where the response is not the expected array.
    echo "✗ Error: Failed to check for user '$USERNAME' due to an API error."
    echo "   GitLab API Response: $EXISTING_USER_RESPONSE"
    echo "----------------------------------------"
    continue
  fi

  # User Creation
  # ------------
  # Create new user with specified parameters
  # skip_confirmation=true allows immediate access without email verification
  echo "▸ Creating user: $USERNAME ($EMAIL)"
  USER_ID=$(curl -s --request POST "$GITLAB_URL/api/v4/users" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "email=$EMAIL&username=$USERNAME&name=$NAME&password=$DEFAULT_PASSWORD&skip_confirmation=true" \
    | jq '.id')

  # Verify user creation success
  if [ "$USER_ID" = "null" ]; then
    echo "✗ Failed to create user '$USERNAME'"
    echo "----------------------------------------"
    continue
  fi

  echo "✔ User '$USERNAME' created with ID: $USER_ID"

  # Group Membership Management
  # --------------------------
  # Add user to specified group with Maintainer access level
  # Access levels:
  # - 40: Maintainer
  # - 30: Developer
  echo "▸ Adding '$USERNAME' to group '$GROUP_NAME'"
  curl -s --request POST "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "user_id=$USER_ID&access_level=40" # Maintainer access level=30 Developer access level=40 Maintainer

  echo "✔ Done for $USERNAME"
  echo ""
  echo "----------------------------------------"
done
