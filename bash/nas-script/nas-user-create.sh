#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Inline NAS config (was nas.conf in the source repo) ---
NAS_IP="192.0.2.5"
NAS_URL="http://${NAS_IP}:5000"

# 관리자 자격증명 (DSM admin)
ADMIN_USERNAME="user"
ADMIN_PASSWORD="CHANGE_ME"

# 사용자 그룹 (create 시 그룹 멤버 추가, delete 시 검증용)
GROUP_NAME="UserMember"

# 신규 사용자 기본값 (create 전용 — delete 에서는 무시됨)
EMAIL_DOMAIN="example.com"
DEFAULT_PASSWORD="CHANGE_ME"

# Per-user description (varies between users → kept in wrapper)
DESCRIPTION="server_user"

# List of users to be created
# Add or remove usernames as needed
USERNAMES=(
  example_user
)

# Initialize API Information
# -------------------------
# Retrieve API information for required Synology APIs
# This step is necessary to ensure all required APIs are available
echo "▸ Getting API Info..."
API_INFO=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.Core.User,SYNO.Core.Group,SYNO.Core.Share,SYNO.FileStation.List,SYNO.FileStation.Sharing")
echo "API Info Response: $API_INFO"

# Authentication - FileStation Session
# -----------------------------------
# First authentication session for FileStation operations
# This session is required for file system related operations
echo "▸ Attempting to authenticate with NAS (FileStation session)..."
AUTH_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=login" \
  --data-urlencode "account=$ADMIN_USERNAME" \
  --data-urlencode "passwd=$ADMIN_PASSWORD" \
  --data-urlencode "session=FileStation" \
  --data-urlencode "format=cookie")

echo "Auth Response: $AUTH_RESPONSE"

# Extract Session ID (SID) from authentication response
SID=$(echo $AUTH_RESPONSE | jq -r '.data.sid')

# Validate FileStation authentication
if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "✗ Failed to authenticate with NAS"
    echo "Error details:"
    echo $AUTH_RESPONSE | jq '.'
    exit 1
fi

echo "✔ Successfully authenticated with NAS (FileStation session)"
echo "----------------------------------------"

# Authentication - Core Session
# ----------------------------
# Second authentication session for core operations
# This session is required for user and group management
echo "▸ Attempting to authenticate with NAS (Core session)..."
CORE_AUTH_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=login" \
  --data-urlencode "account=$ADMIN_USERNAME" \
  --data-urlencode "passwd=$ADMIN_PASSWORD" \
  --data-urlencode "session=Core" \
  --data-urlencode "format=cookie")

echo "Core Auth Response: $CORE_AUTH_RESPONSE"

# Extract Core Session ID
CORE_SID=$(echo $CORE_AUTH_RESPONSE | jq -r '.data.sid')

# Validate Core authentication
if [ -z "$CORE_SID" ] || [ "$CORE_SID" = "null" ]; then
    echo "✗ Failed to authenticate with NAS (Core session)"
    echo "Error details:"
    echo $CORE_AUTH_RESPONSE | jq '.'
    exit 1
fi

echo "✔ Successfully authenticated with NAS (Core session)"
echo "----------------------------------------"

# Group Information Retrieval
# --------------------------
# Get information about existing groups
# This is used to verify group existence and permissions
echo "▸ Getting group info..."
GROUP_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.Core.Group" \
  --data-urlencode "version=1" \
  --data-urlencode "method=list" \
  --data-urlencode "_sid=$CORE_SID")
echo "Group Info: $GROUP_INFO"

# Share Folder Information
# -----------------------
# Get information about shared folders
# This is used to verify share permissions and access
echo "▸ Getting share folder info..."
SHARE_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.Core.Share" \
  --data-urlencode "version=1" \
  --data-urlencode "method=list" \
  --data-urlencode "_sid=$CORE_SID")
echo "Share Info: $SHARE_INFO"

# User Creation Loop
# ----------------
# Process each username in the USERNAMES array
for USERNAME in "${USERNAMES[@]}"; do
  # Generate email address for the user
  EMAIL="${USERNAME}@${EMAIL_DOMAIN}"

  # Check for existing user
  # Prevents duplicate user creation
  EXISTING_USER=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=get" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID" | jq '.data')
  
  # Skip if user already exists
  if [ "$EXISTING_USER" != "null" ]; then
    echo "▲  User '$USERNAME' already exists!"
    echo "----------------------------------------"
    continue
  fi

  echo "▸ Creating user: $USERNAME ($EMAIL)"
  
  # Create new user
  # Sets up basic user account with email and description
  CREATE_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=create" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "password=$DEFAULT_PASSWORD" \
    --data-urlencode "email=$EMAIL" \
    --data-urlencode "description=$DESCRIPTION" \
    --data-urlencode "_sid=$CORE_SID")

  # Verify user creation success
  if echo "$CREATE_RESPONSE" | jq -e '.success == true' >/dev/null; then
    echo "✔ User '$USERNAME' created successfully"

    # Wait for user creation to complete
    # This ensures all user data is properly initialized
    echo "▸ Waiting for user creation to complete..."
    sleep 2

    # Group Membership Management
    # --------------------------
    # Add user to specified group using synogroup command
    echo "▸ Adding '$USERNAME' to group '$GROUP_NAME'"
    
    # Execute synogroup command with sudo privileges
    echo "▸ Executing synogroup command..."
    GROUP_RESPONSE=$(sshpass -p "$ADMIN_PASSWORD" ssh $ADMIN_USERNAME@$NAS_IP "echo '$ADMIN_PASSWORD' | sudo -S /usr/syno/sbin/synogroup --memberadd '$GROUP_NAME' '$USERNAME'")
    
    echo "Group update response: $GROUP_RESPONSE"
    
    # Verify group membership
    # Ensures user was successfully added to the group
    echo "▸ Verifying group membership..."
    VERIFY_RESPONSE=$(sshpass -p "$ADMIN_PASSWORD" ssh $ADMIN_USERNAME@$NAS_IP "echo '$ADMIN_PASSWORD' | sudo -S /usr/syno/sbin/synogroup --get '$GROUP_NAME' | grep '$USERNAME'")
    
    # Check group membership status
    if [ -n "$VERIFY_RESPONSE" ]; then
      echo "✔ User '$USERNAME' added to group '$GROUP_NAME'"
      echo "▸ Group members from synogroup command:"
      sshpass -p "$ADMIN_PASSWORD" ssh $ADMIN_USERNAME@$NAS_IP "echo '$ADMIN_PASSWORD' | sudo -S /usr/syno/sbin/synogroup --get '$GROUP_NAME'"
    else
      echo "✗ Failed to add user '$USERNAME' to group '$GROUP_NAME'"
      echo "Error details: $GROUP_RESPONSE"
    fi

    echo "✔ Done for $USERNAME"
  else
    echo "✗ Failed to create user '$USERNAME'"
    echo "Error details:"
    echo $CREATE_RESPONSE | jq '.'
  fi
  
  echo ""
  echo "----------------------------------------"
done

# Session Cleanup
# -------------
# Logout from both FileStation and Core sessions
# This ensures proper cleanup of authentication sessions
curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=logout" \
  --data-urlencode "session=FileStation" \
  --data-urlencode "_sid=$SID"

curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=logout" \
  --data-urlencode "session=Core" \
  --data-urlencode "_sid=$CORE_SID" 
