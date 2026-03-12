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
