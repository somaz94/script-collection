#!/bin/bash
set -e

#############################################
# GitLab Source Restore from Google Drive
#############################################

# Default values (override with flags or environment variables)
REMOTE="${REMOTE:-Gitlab Backup}"
WORK_DIR="${WORK_DIR:-/tmp/gitlab-restore}"
RCLONE_CONFIG="${RCLONE_CONFIG:-}"
SELECT_MODE=false
COMPARE_REPO=""

# Color
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 [options] <project-name> [gitlab-repo-url]"
  echo ""
  echo "Options:"
  echo "  -r, --remote <name>       rclone remote name (default: Gitlab Backup)"
  echo "  -w, --work-dir <path>     working directory (default: /tmp/gitlab-restore)"
  echo "  -c, --config <path>       rclone config file path"
  echo "  -s, --select              select backup from list (default: latest)"
  echo "  -d, --diff <repo-path>    compare with local repo after restore"
  echo "  -h, --help                show this help"
  echo ""
  echo "Examples:"
  echo "  # Local restore (latest backup)"
  echo "  $0 my-project"
  echo ""
  echo "  # Restore to remote GitLab repo (latest backup)"
  echo "  $0 my-project git@gitlab.example.com:group/restore-repo.git"
  echo ""
  echo "  # Select specific backup from list"
  echo "  $0 -s my-project"
  echo ""
  echo "  # Restore and compare with original repo"
  echo "  $0 -d ~/gitlab-project/my-project my-project"
  echo ""
  echo "  # With custom remote, config, and work directory"
  echo "  $0 -r 'Gitlab Backup' -c ~/.config/rclone/rclone.conf -w /tmp/restore my-project"
  echo ""
  echo "  # Using environment variables"
  echo "  REMOTE='Gitlab Backup' WORK_DIR=/tmp/restore $0 my-project"
  exit 1
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--remote)    REMOTE="$2"; shift 2 ;;
    -w|--work-dir)  WORK_DIR="$2"; shift 2 ;;
    -c|--config)    RCLONE_CONFIG="$2"; shift 2 ;;
    -s|--select)    SELECT_MODE=true; shift ;;
    -d|--diff)      COMPARE_REPO="$2"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo -e "${RED}Unknown option: $1${NC}"; usage ;;
    *)              break ;;
  esac
done

PROJECT_NAME="$1"
GITLAB_REPO_URL="$2"

if [ -z "$PROJECT_NAME" ]; then
  usage
fi

# Validate compare repo path
if [ -n "$COMPARE_REPO" ] && [ ! -d "$COMPARE_REPO" ]; then
  echo -e "${RED}Compare repo not found: ${COMPARE_REPO}${NC}"
  exit 1
fi

# Build rclone config flag
CONFIG_FLAG=""
if [ -n "$RCLONE_CONFIG" ]; then
  CONFIG_FLAG="--config $RCLONE_CONFIG"
fi

# Create working directory
mkdir -p "$WORK_DIR"

echo -e "${GREEN}=== GitLab Source Restore ===${NC}"
echo "  Remote:   ${REMOTE}"
echo "  Project:  ${PROJECT_NAME}"
echo "  Work Dir: ${WORK_DIR}"
[ -n "$RCLONE_CONFIG" ] && echo "  Config:   ${RCLONE_CONFIG}"
[ -n "$COMPARE_REPO" ] && echo "  Compare:  ${COMPARE_REPO}"
echo ""

# Step 1: List available backups (store in array)
echo -e "${GREEN}[1/6] Listing backups${NC}"
echo "---"

BACKUPS=()
while IFS= read -r line; do
  [ -n "$line" ] && BACKUPS+=("$line")
done < <(rclone lsf "${REMOTE}:${PROJECT_NAME}/" $CONFIG_FLAG | awk -F'_' '{print $(NF-1)"_"$NF, $0}' | sort -k1,1 | awk '{print $2}')

if [ ${#BACKUPS[@]} -eq 0 ]; then
  echo -e "${RED}No backup files found: ${REMOTE}:${PROJECT_NAME}/${NC}"
  exit 1
fi

for i in "${!BACKUPS[@]}"; do
  echo "  $((i + 1))) ${BACKUPS[$i]}"
done

TOTAL=${#BACKUPS[@]}
echo "---"

# Step 2: Select backup file
if [ "$SELECT_MODE" = true ]; then
  # Manual selection
  echo -e "${YELLOW}Select backup number to restore (1-${TOTAL}):${NC}"
  read -r SELECTION

  if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$TOTAL" ]; then
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
  fi

  BACKUP_FILE="${BACKUPS[$((SELECTION - 1))]}"
else
  # Default: latest backup (last in sorted array)
  BACKUP_FILE="${BACKUPS[$((TOTAL - 1))]}"
  echo -e "${YELLOW}Using latest backup (use -s to select manually)${NC}"
fi

echo -e "${GREEN}Selected: ${BACKUP_FILE}${NC}"

# Step 3: Download backup file from Google Drive
echo -e "${GREEN}[2/6] Downloading backup${NC}"
rclone copy "${REMOTE}:${PROJECT_NAME}/${BACKUP_FILE}" "$WORK_DIR/" --progress $CONFIG_FLAG

# Step 4: Extract archive
echo -e "${GREEN}[3/6] Extracting archive${NC}"
cd "$WORK_DIR"

# Clean up previous repo.git if exists
[ -d "repo.git" ] && rm -rf repo.git

tar xzf "${BACKUP_FILE}"

if [ ! -d "repo.git" ]; then
  echo -e "${RED}repo.git directory not found. Please check the backup file.${NC}"
  exit 1
fi

echo "  Branches:"
git --git-dir=repo.git branch | sed 's/^/    /'
echo "  Tags:"
git --git-dir=repo.git tag | sed 's/^/    /'

# Step 5: Restore
if [ -n "$GITLAB_REPO_URL" ]; then
  # Push to remote GitLab repo
  echo -e "${GREEN}[4/6] Restoring to remote repo: ${GITLAB_REPO_URL}${NC}"
  cd repo.git

  # Clean up GitLab internal refs (hidden refs rejected during mirror push)
  echo "  Cleaning internal refs..."
  for ref in $(git for-each-ref --format='%(refname)' refs/merge-requests refs/pipelines refs/environments refs/keep-around 2>/dev/null); do
    git update-ref -d "$ref" 2>/dev/null || true
  done

  # Force push all branches + tags (instead of --mirror to avoid deleting remote-only branches)
  git push --force --all "$GITLAB_REPO_URL" 2>&1 | tee /tmp/push-result.log || true
  git push --force --tags "$GITLAB_REPO_URL" 2>&1 | tee -a /tmp/push-result.log || true

  if grep -q "remote rejected\|error:" /tmp/push-result.log; then
    UNEXPECTED_ERRORS=$(grep "remote rejected\|error:" /tmp/push-result.log \
      | grep -v "deny updating a hidden ref" \
      || true)

    if [ -n "$UNEXPECTED_ERRORS" ]; then
      echo ""
      echo -e "${RED}Push errors:${NC}"
      echo "$UNEXPECTED_ERRORS"
      if echo "$UNEXPECTED_ERRORS" | grep -q "pre-receive hook declined"; then
        echo ""
        echo -e "${YELLOW}Fix: Check protected branch settings in the target repo.${NC}"
        echo -e "${YELLOW}  Settings > Repository > Protected Branches > 'Allowed to force push'${NC}"
        echo -e "${YELLOW}  Also check for wildcard rules (e.g. *)${NC}"
      fi
      exit 1
    fi
  fi
  echo -e "${GREEN}[5/6] Restore complete${NC}"

  # Verify: compare remote repo with backup
  echo ""
  echo -e "${GREEN}[6/6] Comparing remote repo with backup${NC}"
  echo "---"

  VERIFY_DIR="${WORK_DIR}/verify-clone"
  [ -d "$VERIFY_DIR" ] && rm -rf "$VERIFY_DIR"
  git clone --bare "$GITLAB_REPO_URL" "$VERIFY_DIR" 2>/dev/null

  BACKUP_GIT="${WORK_DIR}/repo.git"

  # Compare commits
  DIFF_RESULT=$(diff \
    <(git --git-dir="$VERIFY_DIR" log --all --format='%H' | sort) \
    <(git --git-dir="$BACKUP_GIT" log --all --format='%H' | sort) \
  || true)

  if [ -z "$DIFF_RESULT" ]; then
    echo -e "  Commits:  ${GREEN}IDENTICAL${NC}"
  else
    ONLY_IN_REMOTE=$(echo "$DIFF_RESULT" | grep "^< " | wc -l | tr -d ' ')
    ONLY_IN_BACKUP=$(echo "$DIFF_RESULT" | grep "^> " | wc -l | tr -d ' ')
    echo -e "  Commits:  ${YELLOW}DIFFER${NC}"
    echo "    Only in remote: ${ONLY_IN_REMOTE} commit(s)"
    echo "    Only in backup: ${ONLY_IN_BACKUP} commit(s)"
  fi

  # Compare branches
  BRANCH_DIFF=$(diff \
    <(git --git-dir="$VERIFY_DIR" branch | sed 's/^[* ]*//' | sort) \
    <(git --git-dir="$BACKUP_GIT" branch | sed 's/^[* ]*//' | sort) \
  || true)

  if [ -z "$BRANCH_DIFF" ]; then
    echo -e "  Branches: ${GREEN}IDENTICAL${NC}"
  else
    echo -e "  Branches: ${YELLOW}DIFFER${NC}"
    echo "$BRANCH_DIFF" | grep "^< " | sed 's/^< /    Only in remote: /'
    echo "$BRANCH_DIFF" | grep "^> " | sed 's/^> /    Only in backup: /'
  fi

  # Compare tags
  TAG_DIFF=$(diff \
    <(git --git-dir="$VERIFY_DIR" tag | sort) \
    <(git --git-dir="$BACKUP_GIT" tag | sort) \
  || true)

  if [ -z "$TAG_DIFF" ]; then
    echo -e "  Tags:     ${GREEN}IDENTICAL${NC}"
  else
    echo -e "  Tags:     ${YELLOW}DIFFER${NC}"
    echo "$TAG_DIFF" | grep "^< " | sed 's/^< /    Only in remote: /'
    echo "$TAG_DIFF" | grep "^> " | sed 's/^> /    Only in backup: /'
  fi

  echo "---"

  # Clean up verification clone
  rm -rf "$VERIFY_DIR"
else
  # Clone to local directory
  LOCAL_DIR="${WORK_DIR}/${PROJECT_NAME}"
  [ -d "$LOCAL_DIR" ] && rm -rf "$LOCAL_DIR"
  echo -e "${GREEN}[4/6] Restoring to local: ${LOCAL_DIR}${NC}"
  git clone repo.git "$LOCAL_DIR"
  echo -e "${GREEN}[5/6] Restore complete${NC}"
  echo ""
  echo -e "Working directory: ${YELLOW}${LOCAL_DIR}${NC}"
fi

# Step 6: Compare with original repo
if [ -n "$COMPARE_REPO" ]; then
  echo ""
  echo -e "${GREEN}[6/6] Comparing with: ${COMPARE_REPO}${NC}"
  echo "---"

  RESTORE_GIT="${WORK_DIR}/repo.git"

  # Compare commits
  DIFF_RESULT=$(diff \
    <(cd "$COMPARE_REPO" && git log --all --format='%H' | sort) \
    <(git --git-dir="$RESTORE_GIT" log --all --format='%H' | sort) \
  || true)

  if [ -z "$DIFF_RESULT" ]; then
    echo -e "  Commits: ${GREEN}IDENTICAL${NC}"
  else
    ONLY_IN_ORIGINAL=$(echo "$DIFF_RESULT" | grep "^< " | wc -l | tr -d ' ')
    ONLY_IN_BACKUP=$(echo "$DIFF_RESULT" | grep "^> " | wc -l | tr -d ' ')
    echo -e "  Commits: ${YELLOW}DIFFER${NC}"
    echo "    Only in original: ${ONLY_IN_ORIGINAL} commit(s)"
    echo "    Only in backup:   ${ONLY_IN_BACKUP} commit(s)"

    if [ "$ONLY_IN_ORIGINAL" -gt 0 ]; then
      echo ""
      echo "  Commits only in original (pushed after backup):"
      diff <(cd "$COMPARE_REPO" && git log --all --format='%H' | sort) \
           <(git --git-dir="$RESTORE_GIT" log --all --format='%H' | sort) \
        | grep "^< " | sed 's/^< //' | while read -r hash; do
          MSG=$(cd "$COMPARE_REPO" && git log --format='%h %s' -1 "$hash" 2>/dev/null || echo "$hash (unknown)")
          echo "    - $MSG"
        done
    fi
  fi

  # Compare branches
  BRANCH_DIFF=$(diff \
    <(cd "$COMPARE_REPO" && git branch -r 2>/dev/null | sed 's/^ *//' | grep -v HEAD | sort) \
    <(git --git-dir="$RESTORE_GIT" branch | sed 's/^ *//' | sort) \
  || true)

  if [ -z "$BRANCH_DIFF" ]; then
    echo -e "  Branches: ${GREEN}IDENTICAL${NC}"
  else
    echo -e "  Branches: ${YELLOW}DIFFER${NC}"
    echo "$BRANCH_DIFF" | grep "^< " | sed 's/^< /    Only in original: /'
    echo "$BRANCH_DIFF" | grep "^> " | sed 's/^> /    Only in backup:   /'
  fi

  # Compare tags
  TAG_DIFF=$(diff \
    <(cd "$COMPARE_REPO" && git tag | sort) \
    <(git --git-dir="$RESTORE_GIT" tag | sort) \
  || true)

  if [ -z "$TAG_DIFF" ]; then
    echo -e "  Tags:     ${GREEN}IDENTICAL${NC}"
  else
    echo -e "  Tags:     ${YELLOW}DIFFER${NC}"
    echo "$TAG_DIFF" | grep "^< " | sed 's/^< /    Only in original: /'
    echo "$TAG_DIFF" | grep "^> " | sed 's/^> /    Only in backup:   /'
  fi

  echo "---"
else
  echo -e "${YELLOW}[6/6] Skipped comparison (use -d <repo-path> to compare)${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"