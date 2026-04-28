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

# List of users to be deleted
# Add or remove usernames as needed
USERNAMES=(
  example_user
)

# Initialize API Information
# -------------------------
# Retrieve API information for required Synology APIs
# This step is necessary to ensure all required APIs are available
echo "▸ Getting API Info..."
API_INFO=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.Core.User")
echo "API Info Response: $API_INFO"

# Authentication - Core Session
# ----------------------------
# Authenticate with NAS for core operations
# This session is required for user management
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

# User Deletion Loop
# ----------------
# Process each username in the USERNAMES array
for USERNAME in "${USERNAMES[@]}"; do
  # Check for existing user
  # Verifies if the user exists before attempting deletion
  echo "▸ Checking if user '$USERNAME' exists..."
  USER_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=get" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID")
  
  # Skip if user doesn't exist
  if echo "$USER_INFO" | jq -e '.error' >/dev/null; then
    echo "▲  User '$USERNAME' does not exist!"
    echo "----------------------------------------"
    continue
  fi

  echo "▸  Deleting user: $USERNAME"
  
  # Delete user
  # Removes the user account from the NAS system
  DELETE_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=delete" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID")

  # Verify deletion success
  if echo "$DELETE_RESPONSE" | jq -e '.success == true' >/dev/null; then
    echo "✔ User '$USERNAME' deleted successfully"
  else
    echo "✗ Failed to delete user '$USERNAME'"
    echo "Error details:"
    echo $DELETE_RESPONSE | jq '.'
  fi
  
  echo ""
  echo "----------------------------------------"
done

# Session Cleanup
# -------------
# Logout from Core session
# This ensures proper cleanup of authentication session
curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=logout" \
  --data-urlencode "session=Core" \
  --data-urlencode "_sid=$CORE_SID" 
