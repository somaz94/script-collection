#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<USAGE
Usage: ./${0##*/} [--dry-run] [-h | --help]

  Remove users from the new GitLab instance (deletes the user account).

  Target users: USERNAMES array at the top of the script (edit before running)
  Server config: GITLAB_URL, PRIVATE_TOKEN, GROUP_NAME (top of script)

Options:
  --dry-run     Skip the mutating DELETE /groups/<id>/members + DELETE /users/<id>
                calls; read-only group/user lookups still run.
  -h, --help    Show this help and exit

Flow:
  1) Resolve each USERNAME to a user ID via GitLab API
  2) DELETE /api/v4/users/<id> with PRIVATE-TOKEN header
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
GROUP_NAME="gamedesign"

USERNAMES=(
  test
)

GROUP_ID=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/groups?search=$GROUP_NAME" | jq ".[0].id")

echo "✔ Found Group '$GROUP_NAME' with ID: $GROUP_ID"
echo "----------------------------------------"

for USERNAME in "${USERNAMES[@]}"; do
  EXISTING_USER=$(curl -s --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/users?username=$USERNAME" | jq '.[0]')
  
  if [ "$EXISTING_USER" = "null" ]; then
    echo "▲  User '$USERNAME' does not exist!"
    echo "----------------------------------------"
    continue
  fi

  USER_ID=$(echo $EXISTING_USER | jq '.id')
  
  # This must be done before user deletion to avoid orphaned references
  echo "▸  Removing '$USERNAME' from group '$GROUP_NAME'"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) DELETE $GITLAB_URL/api/v4/groups/$GROUP_ID/members/$USER_ID"
  else
    curl -s --request DELETE "$GITLAB_URL/api/v4/groups/$GROUP_ID/members/$USER_ID" \
      --header "PRIVATE-TOKEN: $PRIVATE_TOKEN"
  fi

  # This is a permanent operation and cannot be undone
  echo "▸ Deleting user: $USERNAME"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) DELETE $GITLAB_URL/api/v4/users/$USER_ID"
    echo "✔ (dry-run) plan for '$USERNAME' printed"
  else
    curl -s --request DELETE "$GITLAB_URL/api/v4/users/$USER_ID" \
      --header "PRIVATE-TOKEN: $PRIVATE_TOKEN"
    echo "✔ User '$USERNAME' deleted successfully"
  fi
  echo "✔ Done for $USERNAME"
  echo ""
  echo "----------------------------------------"
done 