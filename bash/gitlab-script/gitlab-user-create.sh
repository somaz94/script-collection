#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<USAGE
Usage: ./${0##*/} [--dry-run] [-h | --help]

  Create users on the new GitLab instance and add them to GROUP_NAME.

  Target users: USERNAMES array at the top of the script (edit before running)
  Server config: GITLAB_URL, PRIVATE_TOKEN, DEFAULT_PASSWORD, EMAIL_DOMAIN, GROUP_NAME (top of script)

Options:
  --dry-run     Skip the mutating POST /users + POST /groups/<id>/members
                calls; read-only group/user lookups still run.
  -h, --help    Show this help and exit

Flow:
  1) Resolve GROUP_NAME -> group ID via GitLab API
  2) Iterate USERNAMES: create user, then add as group member
USAGE
      exit 0
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *)  break ;;
  esac
done

GITLAB_URL="http://gitlab.example.com"
# 🔴 Supplied through the environment, never committed. The token this script
# needs is the instance-level `cicd` service-account PAT, which carries
# admin_mode + sudo — it can act as any user on the instance. It sat here as a
# literal from 2026-03-23 until 2026-08-10, readable by anyone with read access
# to this repo, and has to be treated as compromised for that whole window.
PRIVATE_TOKEN="${PRIVATE_TOKEN:?PRIVATE_TOKEN is required — export the GitLab admin PAT before running}"
DEFAULT_PASSWORD="CHANGE_ME"
EMAIL_DOMAIN="example.com"
GROUP_NAME="server"

USERNAMES=(
  sunddu
)

GROUP_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/groups?search=$GROUP_NAME")
GROUP_ID=$(echo "$GROUP_RESPONSE" | jq ".[0].id")

if [[ "$GROUP_ID" == "null" || -z "$GROUP_ID" ]]; then
  echo "✗ Error: Could not retrieve Group ID for '$GROUP_NAME'."
  echo "   GitLab API Response: $GROUP_RESPONSE"
  echo "----------------------------------------"
  exit 1
fi

echo "✔ Found Group '$GROUP_NAME' with ID: $GROUP_ID"
echo "----------------------------------------"

for USERNAME in "${USERNAMES[@]}"; do
  EMAIL="${USERNAME}@${EMAIL_DOMAIN}"
  NAME="$USERNAME"

  EXISTING_USER_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/users?username=$USERNAME")
  
  # jq returns "null" if user doesn't exist, or an empty string if there's an API error.
  EXISTING_USER_ID=$(echo "$EXISTING_USER_RESPONSE" | jq '.[0].id')
  
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

  # skip_confirmation=true allows immediate access without email verification
  echo "▸ Creating user: $USERNAME ($EMAIL)"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) POST $GITLAB_URL/api/v4/users (email=$EMAIL, username=$USERNAME, name=$NAME, skip_confirmation=true)"
    echo "    (dry-run) POST $GITLAB_URL/api/v4/groups/$GROUP_ID/members (user_id=<new>, access_level=40)"
    echo "✔ (dry-run) plan for '$USERNAME' printed"
    echo "----------------------------------------"
    continue
  fi
  USER_ID=$(curl -s --request POST "$GITLAB_URL/api/v4/users" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "email=$EMAIL&username=$USERNAME&name=$NAME&password=$DEFAULT_PASSWORD&skip_confirmation=true" \
    | jq '.id')

  if [ "$USER_ID" = "null" ]; then
    echo "✗ Failed to create user '$USERNAME'"
    echo "----------------------------------------"
    continue
  fi

  echo "✔ User '$USERNAME' created with ID: $USER_ID"

  # access_level 40 = Maintainer (30 = Developer).
  echo "▸ Adding '$USERNAME' to group '$GROUP_NAME'"
  curl -s --request POST "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "user_id=$USER_ID&access_level=40"

  echo "✔ Done for $USERNAME"
  echo ""
  echo "----------------------------------------"
done
