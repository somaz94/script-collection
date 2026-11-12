#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<USAGE
Usage: ./${0##*/} [--dry-run] [-h | --help]

  Create users on a Synology NAS and grant group/shared-folder permissions.

  Target users: USERNAMES array at the top of the script (edit before running)
  Server config: nas.conf in the same directory
  Description : DESCRIPTION variable at the top

Options:
  --dry-run     Skip the mutating POST (user create) + synogroup ssh commands;
                authentication sessions + read-only lookups still run.
  -h, --help    Show this help and exit

Flow:
  1) Query NAS API info -> authenticate FileStation + Core sessions
  2) Iterate USERNAMES: create user, add to group, grant share permissions
USAGE
      exit 0
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *)  break ;;
  esac
done

# Resolve script path portably across bash and zsh (BASH_SOURCE → $0 fallback).
_SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_PATH")" && pwd)"
unset _SCRIPT_PATH
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

USERNAMES=(
  example_user
)

echo "▸ Getting API Info..."
API_INFO=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.Core.User,SYNO.Core.Group,SYNO.Core.Share,SYNO.FileStation.List,SYNO.FileStation.Sharing")
echo "API Info Response: $API_INFO"

# FileStation and Core APIs need separate sessions.
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

SID=$(echo $AUTH_RESPONSE | jq -r '.data.sid')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "✗ Failed to authenticate with NAS"
    echo "Error details:"
    echo $AUTH_RESPONSE | jq '.'
    exit 1
fi

echo "✔ Successfully authenticated with NAS (FileStation session)"
echo "----------------------------------------"

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

CORE_SID=$(echo $CORE_AUTH_RESPONSE | jq -r '.data.sid')

if [ -z "$CORE_SID" ] || [ "$CORE_SID" = "null" ]; then
    echo "✗ Failed to authenticate with NAS (Core session)"
    echo "Error details:"
    echo $CORE_AUTH_RESPONSE | jq '.'
    exit 1
fi

echo "✔ Successfully authenticated with NAS (Core session)"
echo "----------------------------------------"

echo "▸ Getting group info..."
GROUP_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.Core.Group" \
  --data-urlencode "version=1" \
  --data-urlencode "method=list" \
  --data-urlencode "_sid=$CORE_SID")
echo "Group Info: $GROUP_INFO"

echo "▸ Getting share folder info..."
SHARE_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.Core.Share" \
  --data-urlencode "version=1" \
  --data-urlencode "method=list" \
  --data-urlencode "_sid=$CORE_SID")
echo "Share Info: $SHARE_INFO"

for USERNAME in "${USERNAMES[@]}"; do
  EMAIL="${USERNAME}@${EMAIL_DOMAIN}"

  EXISTING_USER=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=get" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID" | jq '.data')
  
  if [ "$EXISTING_USER" != "null" ]; then
    echo "▲  User '$USERNAME' already exists!"
    echo "----------------------------------------"
    continue
  fi

  echo "▸ Creating user: $USERNAME ($EMAIL)"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) POST $NAS_URL/webapi/entry.cgi api=SYNO.Core.User method=create name=$USERNAME email=$EMAIL"
    echo "    (dry-run) ssh $ADMIN_USERNAME@$NAS_IP synogroup --memberadd '$GROUP_NAME' '$USERNAME'"
    echo "✔ (dry-run) plan for '$USERNAME' printed"
    echo "----------------------------------------"
    continue
  fi

  CREATE_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=create" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "password=$DEFAULT_PASSWORD" \
    --data-urlencode "email=$EMAIL" \
    --data-urlencode "description=$DESCRIPTION" \
    --data-urlencode "_sid=$CORE_SID")

  if echo "$CREATE_RESPONSE" | jq -e '.success == true' >/dev/null; then
    echo "✔ User '$USERNAME' created successfully"

    echo "▸ Waiting for user creation to complete..."
    sleep 2

    echo "▸ Adding '$USERNAME' to group '$GROUP_NAME'"
    
    echo "▸ Executing synogroup command..."
    GROUP_RESPONSE=$(sshpass -p "$ADMIN_PASSWORD" ssh $ADMIN_USERNAME@$NAS_IP "echo '$ADMIN_PASSWORD' | sudo -S /usr/syno/sbin/synogroup --memberadd '$GROUP_NAME' '$USERNAME'")
    
    echo "Group update response: $GROUP_RESPONSE"
    
    echo "▸ Verifying group membership..."
    VERIFY_RESPONSE=$(sshpass -p "$ADMIN_PASSWORD" ssh $ADMIN_USERNAME@$NAS_IP "echo '$ADMIN_PASSWORD' | sudo -S /usr/syno/sbin/synogroup --get '$GROUP_NAME' | grep '$USERNAME'")
    
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
