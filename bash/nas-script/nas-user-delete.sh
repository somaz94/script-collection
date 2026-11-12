#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<USAGE
Usage: ./${0##*/} [--dry-run] [-h | --help]

  Delete users from a Synology NAS.

  Target users: USERNAMES array at the top of the script (edit before running)
  Server config: nas.conf in the same directory

Options:
  --dry-run     Skip the mutating DELETE POST; authentication session +
                existence lookup still run.
  -h, --help    Show this help and exit

Flow:
  1) Query NAS API info -> authenticate Core session
  2) Iterate USERNAMES: verify existence, then delete
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

USERNAMES=(
  example_user
)

echo "▸ Getting API Info..."
API_INFO=$(curl -s -X GET "$NAS_URL/webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.Core.User")
echo "API Info Response: $API_INFO"

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

for USERNAME in "${USERNAMES[@]}"; do
  echo "▸ Checking if user '$USERNAME' exists..."
  USER_INFO=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=get" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID")
  
  if echo "$USER_INFO" | jq -e '.error' >/dev/null; then
    echo "▲  User '$USERNAME' does not exist!"
    echo "----------------------------------------"
    continue
  fi

  echo "▸  Deleting user: $USERNAME"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) POST $NAS_URL/webapi/entry.cgi api=SYNO.Core.User method=delete name=$USERNAME"
    echo "✔ (dry-run) plan for '$USERNAME' printed"
    echo ""
    echo "----------------------------------------"
    continue
  fi

  DELETE_RESPONSE=$(curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
    --data-urlencode "api=SYNO.Core.User" \
    --data-urlencode "version=1" \
    --data-urlencode "method=delete" \
    --data-urlencode "name=$USERNAME" \
    --data-urlencode "_sid=$CORE_SID")

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

curl -s -X POST "$NAS_URL/webapi/entry.cgi" \
  --data-urlencode "api=SYNO.API.Auth" \
  --data-urlencode "version=7" \
  --data-urlencode "method=logout" \
  --data-urlencode "session=Core" \
  --data-urlencode "_sid=$CORE_SID" 
