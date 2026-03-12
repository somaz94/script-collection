#!/bin/bash
set -e

SOURCE_DIR="$HOME/gitlab-project"
PRIVATE_DIR="$HOME/PrivateWork"

# Format: "source_name:dest_name"
REPOS=(
  "$SOURCE_REPO1:$DEST_REPO1"
  "$SOURCE_REPO2:$DEST_REPO2"
)

for entry in "${REPOS[@]}"; do
  src="$SOURCE_DIR/${entry%%:*}"
  dest="$PRIVATE_DIR/${entry##*:}"

  if [ ! -d "$src" ]; then
    echo "SKIP: $src (not found)"
    continue
  fi

  mkdir -p "$dest"
  rsync -a --exclude='.git' "$src/" "$dest/"
  echo "DONE: $src -> $dest"
done

echo ""
echo "========================================="
echo "Checking changes in PRIVATE_DIR repos..."
echo "========================================="

for entry in "${REPOS[@]}"; do
  dest="$PRIVATE_DIR/${entry##*:}"

  if [ ! -d "$dest/.git" ]; then
    echo ""
    echo "[$dest] Not a git repo, skipping status check."
    continue
  fi

  echo ""
  echo "--- ${entry##*:} ---"

  changes=$(git -C "$dest" status --porcelain)

  if [ -z "$changes" ]; then
    echo "No changes."
  else
    echo "$changes"
    echo ""
    echo "Diff summary:"
    git -C "$dest" diff --stat
    # List untracked files separately
    untracked=$(git -C "$dest" ls-files --others --exclude-standard)
    if [ -n "$untracked" ]; then
      echo ""
      echo "Untracked files:"
      echo "$untracked"
    fi

    echo ""
    read -p "Do you want to add, commit and push? (y/n): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      read -p "Commit message: " commit_msg
      git -C "$dest" add -A
      git -C "$dest" commit -m "${commit_msg:-Update from source repo}"
      git -C "$dest" push
      echo "Pushed: ${entry##*:}"
    else
      echo "Skipped push for ${entry##*:}"
    fi
  fi
done