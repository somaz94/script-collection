#!/bin/bash
# =============================================================================
# Kubespray Upgrade Script
#
# Run on control plane (copy this script to control plane)
# Override defaults with env vars: KUBESPRAY_DIR=/path INVENTORY_NAME=my-cluster ./upgrade-kubespray.sh
#
# Usage:
#   ./upgrade-kubespray.sh                    # Interactive upgrade to latest tag
#   ./upgrade-kubespray.sh --target v2.30.0   # Upgrade to specific tag
#   ./upgrade-kubespray.sh --diff-only        # Show diff only, no upgrade
#   ./upgrade-kubespray.sh --check            # Pre-flight check only
#   ./upgrade-kubespray.sh -h                 # Help
# =============================================================================

set -euo pipefail

KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"
INVENTORY_NAME="${INVENTORY_NAME:-concrit-cluster}"
INVENTORY_DIR="$KUBESPRAY_DIR/inventory/$INVENTORY_NAME"
BACKUP_BASE="$KUBESPRAY_DIR/upgrade-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

confirm() {
  echo ""
  read -rp "  $(echo -e "${YELLOW}$1 [y/N]:${NC} ")" answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# =============================================================================
# Functions
# =============================================================================

show_help() {
  cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Kubespray Upgrade Script — run on control plane

Options:
  (default)              Interactive upgrade (shows diff, asks for confirmation)
  --target <TAG>         Target kubespray version (e.g., v2.30.0)
  --diff-only            Show config diff between current and target, no upgrade
  --check                Pre-flight check only (versions, inventory, venv)
  -h, --help             Show this help message

Environment Variables:
  KUBESPRAY_DIR          Kubespray directory (default: ~/kubespray)
  INVENTORY_NAME         Inventory name (default: concrit-cluster)

Examples:
  $(basename "$0")                        # Interactive upgrade
  $(basename "$0") --target v2.30.0       # Upgrade to v2.30.0
  $(basename "$0") --diff-only            # Review changes first
  $(basename "$0") --check                # Verify everything before upgrade
HELP
}

preflight_check() {
  print_header "Pre-flight Check"

  echo ""
  # Check kubespray directory
  if [ -d "$KUBESPRAY_DIR" ]; then
    echo -e "  ${GREEN}✓${NC} Kubespray directory: $KUBESPRAY_DIR"
  else
    echo -e "  ${RED}✗${NC} Kubespray directory not found: $KUBESPRAY_DIR"
    exit 1
  fi

  # Check inventory
  if [ -d "$INVENTORY_DIR" ]; then
    echo -e "  ${GREEN}✓${NC} Inventory: $INVENTORY_DIR"
  else
    echo -e "  ${RED}✗${NC} Inventory not found: $INVENTORY_DIR"
    exit 1
  fi

  # Check venv
  if [ -f "$KUBESPRAY_DIR/venv/bin/activate" ]; then
    echo -e "  ${GREEN}✓${NC} Python venv found"
  else
    echo -e "  ${RED}✗${NC} Python venv not found at $KUBESPRAY_DIR/venv/"
    exit 1
  fi

  # Check git
  cd "$KUBESPRAY_DIR"
  CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
  CURRENT_FULL=$(git describe --tags 2>/dev/null || echo "unknown")
  echo -e "  ${GREEN}✓${NC} Current kubespray tag: $CURRENT_TAG ($CURRENT_FULL)"

  # Check K8s
  K8S_VER=$(kubectl version -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])" 2>/dev/null || echo "unknown")
  echo -e "  ${GREEN}✓${NC} Current K8s version: $K8S_VER"

  # Check kubectl nodes
  echo ""
  echo -e "  ${YELLOW}[Cluster Nodes]${NC}"
  kubectl get nodes -o wide 2>/dev/null || echo -e "  ${RED}kubectl failed${NC}"

  # Fetch latest tags
  echo ""
  git fetch --tags -q 2>/dev/null
  LATEST_TAG=$(git tag -l | sort -V | tail -1)
  echo -e "  Latest available tag: ${GREEN}$LATEST_TAG${NC}"

  if [ "$CURRENT_TAG" = "$LATEST_TAG" ]; then
    echo -e "  ${GREEN}✓ Kubespray is up to date${NC}"
  else
    echo -e "  ${YELLOW}→ Upgrade available: $CURRENT_TAG → $LATEST_TAG${NC}"
  fi
}

show_config_diff() {
  local target_tag="$1"

  print_header "Config Diff: $CURRENT_TAG → $target_tag"

  cd "$KUBESPRAY_DIR"

  echo ""
  echo -e "  ${YELLOW}[1/3] Sample inventory changes (group_vars defaults)${NC}"
  echo ""
  git diff "$CURRENT_TAG".."$target_tag" -- inventory/sample/group_vars/ 2>/dev/null | head -200 || echo "  No changes"

  echo ""
  echo -e "  ${YELLOW}[2/3] Urgent upgrade notes from commits${NC}"
  echo ""
  git log "$CURRENT_TAG".."$target_tag" --oneline --grep="Action required" --grep="BREAKING" --grep="deprecated" --all-match 2>/dev/null | head -20 || echo "  No breaking changes found"

  echo ""
  echo -e "  ${YELLOW}[3/3] Your inventory vs sample (current differences)${NC}"
  echo ""
  if [ -d "$INVENTORY_DIR/group_vars" ]; then
    for file in "$INVENTORY_DIR/group_vars/k8s_cluster"/*.yml; do
      fname=$(basename "$file")
      sample="inventory/sample/group_vars/k8s_cluster/$fname"
      if [ -f "$sample" ]; then
        changes=$(diff "$file" "$sample" 2>/dev/null | grep -c '^[<>]' || true)
        if [ "$changes" -gt 0 ]; then
          echo -e "  ${YELLOW}$fname${NC}: $changes differences"
        else
          echo -e "  ${GREEN}$fname${NC}: identical"
        fi
      fi
    done

    echo ""
    for file in "$INVENTORY_DIR/group_vars/all"/*.yml; do
      fname=$(basename "$file")
      sample="inventory/sample/group_vars/all/$fname"
      if [ -f "$sample" ]; then
        changes=$(diff "$file" "$sample" 2>/dev/null | grep -c '^[<>]' || true)
        if [ "$changes" -gt 0 ]; then
          echo -e "  ${YELLOW}$fname${NC}: $changes differences"
        else
          echo -e "  ${GREEN}$fname${NC}: identical"
        fi
      fi
    done
  fi
}

backup_inventory() {
  print_header "Backup Inventory"

  mkdir -p "$BACKUP_BASE"
  BACKUP_DIR="$BACKUP_BASE/${TIMESTAMP}_${CURRENT_TAG}"
  cp -r "$INVENTORY_DIR" "$BACKUP_DIR"
  echo ""
  echo -e "  ${GREEN}✓${NC} Backed up to: $BACKUP_DIR"
  echo "  Files:"
  find "$BACKUP_DIR" -type f | while read -r f; do
    echo "    - ${f#$BACKUP_DIR/}"
  done
}

do_upgrade() {
  local target_tag="$1"

  print_header "Upgrade Kubespray: $CURRENT_TAG → $target_tag"

  cd "$KUBESPRAY_DIR"

  # Stash any local changes
  echo ""
  STASH_RESULT=$(git stash 2>&1)
  if echo "$STASH_RESULT" | grep -q "Saved"; then
    echo -e "  ${YELLOW}⚠ Stashed local changes${NC}"
  fi

  # Checkout target tag
  echo -e "  Checking out $target_tag..."
  git checkout "$target_tag" 2>/dev/null
  echo -e "  ${GREEN}✓${NC} Switched to $target_tag"

  # Update dependencies
  echo -e "  Updating Python dependencies..."
  source "$KUBESPRAY_DIR/venv/bin/activate"
  pip install -r requirements.txt -q 2>/dev/null
  echo -e "  ${GREEN}✓${NC} Dependencies updated"

  # Pop stash if we stashed
  if echo "$STASH_RESULT" | grep -q "Saved"; then
    git stash pop 2>/dev/null || {
      echo -e "  ${RED}⚠ Stash pop conflict — resolve manually:${NC}"
      echo -e "  ${RED}  git stash show -p | git apply --3way${NC}"
    }
  fi

  # Show new supported versions
  echo ""
  echo -e "  ${YELLOW}[New supported K8s versions]${NC}"
  grep -A200 'kubelet_checksums:' roles/kubespray_defaults/vars/main/checksums.yml 2>/dev/null \
    | sed -n '/amd64:/,/^  [a-z]/p' \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -uV \
    | awk '{printf "  %s\n", $0}'

  print_header "Kubespray Upgrade Complete"

  echo ""
  echo -e "  ${GREEN}✓${NC} Kubespray: $CURRENT_TAG → $target_tag"
  echo ""
  echo -e "  ${YELLOW}Next steps:${NC}"
  echo "  1. Review config diff: $0 --diff-only"
  echo "  2. Update group_vars if needed (new/deprecated options)"
  echo "  3. Run K8s upgrade:"
  echo "     source ~/kubespray/venv/bin/activate"
  echo "     ansible-playbook -i inventory/$INVENTORY_NAME/inventory.ini upgrade-cluster.yml -b --become-user=root"
}

# =============================================================================
# Main
# =============================================================================

TARGET_TAG=""
DIFF_ONLY=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --target)
      TARGET_TAG="$2"
      shift 2
      ;;
    --diff-only)
      DIFF_ONLY=true
      shift
      ;;
    --check)
      CHECK_ONLY=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Pre-flight
cd "$KUBESPRAY_DIR"
git fetch --tags -q 2>/dev/null
CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
LATEST_TAG=$(git tag -l | sort -V | tail -1)

if $CHECK_ONLY; then
  preflight_check
  exit 0
fi

# Determine target
if [ -z "$TARGET_TAG" ]; then
  TARGET_TAG="$LATEST_TAG"
fi

# Validate target tag exists
if ! git rev-parse "$TARGET_TAG" >/dev/null 2>&1; then
  echo -e "${RED}Error: Tag $TARGET_TAG not found${NC}"
  echo "Available tags:"
  git tag -l | sort -V | tail -10
  exit 1
fi

if [ "$CURRENT_TAG" = "$TARGET_TAG" ]; then
  echo -e "${GREEN}Already on $TARGET_TAG — nothing to do${NC}"
  exit 0
fi

# Diff only mode
if $DIFF_ONLY; then
  show_config_diff "$TARGET_TAG"
  exit 0
fi

# Interactive upgrade
preflight_check
show_config_diff "$TARGET_TAG"

if ! confirm "Proceed with upgrade: $CURRENT_TAG → $TARGET_TAG?"; then
  echo -e "  ${YELLOW}Upgrade cancelled${NC}"
  exit 0
fi

backup_inventory
do_upgrade "$TARGET_TAG"
