#!/bin/bash
# =============================================================================
# Kubespray & Kubernetes Version Check Script
#
# Usage:
#   ./check-version.sh                    # Check all versions
#   ./check-version.sh --k8s              # K8s versions only
#   ./check-version.sh --kubespray        # Kubespray version only
#   ./check-version.sh --compatibility    # Show version compatibility matrix
# =============================================================================

set -euo pipefail

# Load shared config
_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.env
source "$_SCRIPT_DIR/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

print_item() {
  printf "  %-25s : ${GREEN}%s${NC}\n" "$1" "$2"
}

print_warn() {
  printf "  %-25s : ${YELLOW}%s${NC}\n" "$1" "$2"
}

check_k8s() {
  print_header "Kubernetes Cluster"

  echo ""
  echo -e "  ${YELLOW}[Nodes]${NC}"
  kubectl get nodes -o wide 2>/dev/null || echo -e "  ${RED}kubectl not available locally. Run on control plane.${NC}"

  echo ""
  echo -e "  ${YELLOW}[Version]${NC}"
  K8S_SERVER=$(kubectl version -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])" 2>/dev/null || echo "unknown")
  print_item "K8s Server Version" "$K8S_SERVER"

  echo ""
  echo -e "  ${YELLOW}[Component Status]${NC}"
  kubectl get --raw='/readyz?verbose' 2>/dev/null | grep -E '^\[|readyz' | head -20 || echo -e "  ${RED}Cannot reach API server${NC}"
}

check_kubespray() {
  print_header "Kubespray (on Control Plane)"

  KUBESPRAY_VER=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git describe --tags 2>/dev/null" 2>/dev/null || echo "SSH failed")
  KUBESPRAY_BRANCH=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git branch --show-current 2>/dev/null" 2>/dev/null || echo "unknown")

  echo ""
  print_item "Kubespray Version" "$KUBESPRAY_VER"
  print_item "Git Branch" "$KUBESPRAY_BRANCH"
  print_item "Control Plane" "$CONTROL_PLANE"
  print_item "Kubespray Path" "$KUBESPRAY_DIR"
}

check_tools() {
  print_header "Local Tools"

  echo ""
  KUBECTL_VER=$(kubectl version --client -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['clientVersion']['gitVersion'])" 2>/dev/null || echo "not installed")
  HELM_VER=$(helm version --short 2>/dev/null || echo "not installed")
  HELMFILE_VER=$(helmfile --version 2>/dev/null || echo "not installed")
  ANSIBLE_VER=$(ansible --version 2>/dev/null | head -1 || echo "not installed")

  print_item "kubectl (client)" "$KUBECTL_VER"
  print_item "helm" "$HELM_VER"
  print_item "helmfile" "$HELMFILE_VER"
  print_item "ansible" "$ANSIBLE_VER"
}

check_supported_versions() {
  print_header "Current Kubespray Supported K8s Versions"

  echo ""
  echo -e "  ${YELLOW}[From checksums.yml on control plane]${NC}"
  VERSIONS=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && grep -A200 'kubelet_checksums:' roles/kubespray_defaults/vars/main/checksums.yml | sed -n '/amd64:/,/^  [a-z]/p' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV" 2>/dev/null)

  if [ -n "$VERSIONS" ]; then
    MIN_VER=$(echo "$VERSIONS" | head -1)
    MAX_VER=$(echo "$VERSIONS" | tail -1)
    MINOR_VERSIONS=$(echo "$VERSIONS" | grep -Eo '^[0-9]+\.[0-9]+' | sort -uV)

    print_item "Supported Range" "v${MIN_VER} ~ v${MAX_VER}"
    echo ""

    echo -e "  ${YELLOW}[Available patch versions]${NC}"
    for minor in $MINOR_VERSIONS; do
      patches=$(echo "$VERSIONS" | grep "^${minor}\." | tr '\n' ', ' | sed 's/,$//')
      printf "  %-8s : ${GREEN}%s${NC}\n" "v${minor}" "$patches"
    done

    # Show current vs latest
    CURRENT_K8S=$(kubectl version -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])" 2>/dev/null || echo "unknown")
    echo ""
    print_item "Current K8s" "$CURRENT_K8S"
    print_item "Latest Supported" "v${MAX_VER}"

    if [ "$CURRENT_K8S" = "v${MAX_VER}" ]; then
      echo -e "\n  ${GREEN}✓ Already on latest supported version${NC}"
    elif [ "$CURRENT_K8S" != "unknown" ]; then
      echo -e "\n  ${YELLOW}→ Upgrade available: ${CURRENT_K8S} → v${MAX_VER}${NC}"
    fi
  else
    echo -e "  ${RED}Failed to read checksums from control plane${NC}"
  fi
}

check_compatibility() {
  print_header "Kubespray ↔ K8s Version Compatibility (from GitHub)"

  echo ""
  echo -e "  ${YELLOW}[Fetching latest releases from GitHub API...]${NC}"
  echo ""

  RELEASES=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kubespray/releases?per_page=15" 2>/dev/null)

  if [ -n "$RELEASES" ] && echo "$RELEASES" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "$RELEASES" | python3 -c "
import sys, json, re

releases = json.load(sys.stdin)
for r in releases:
    tag = r['tag_name']
    body = r.get('body', '')
    date = r['published_at'][:10]

    # Extract K8s versions from 'Add Kubernetes X.Y.Z hash' lines
    k8s_versions = re.findall(r'[Kk]ubernetes\s+(1\.\d+)', body)
    unique = sorted(set(k8s_versions))

    # Also check for version patterns in body
    if not unique:
        k8s_versions = re.findall(r'v?(1\.\d+\.\d+)', body[:2000])
        minors = sorted(set(re.sub(r'\.\d+$', '', v) for v in k8s_versions))
        unique = minors[:3] if minors else ['see release notes']

    k8s_range = ', '.join(f'v{v}' for v in unique) if unique else 'see release notes'
    print(f'  {tag:<12} ({date})  K8s: {k8s_range}')
" 2>/dev/null
  else
    # Fallback to static table
    echo "  ┌──────────────┬──────────────────────────┐"
    echo "  │ Kubespray    │ K8s Supported Range       │"
    echo "  ├──────────────┼──────────────────────────┤"
    echo "  │ v2.25.x      │ v1.29.x ~ v1.31.x        │"
    echo "  │ v2.26.x      │ v1.30.x ~ v1.32.x        │"
    echo "  │ v2.27.x      │ v1.31.x ~ v1.33.x        │"
    echo "  │ v2.28.x      │ v1.32.x ~ v1.34.x        │"
    echo "  └──────────────┴──────────────────────────┘"
  fi

  echo ""
  echo -e "  ${YELLOW}Full release notes: https://github.com/kubernetes-sigs/kubespray/releases${NC}"
}

check_available_tags() {
  print_header "Available Kubespray Tags (latest 10)"

  echo ""
  ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git fetch --tags -q 2>/dev/null && git tag -l | sort -V | tail -10" 2>/dev/null | while read -r tag; do
    echo "  - $tag"
  done || echo -e "  ${RED}SSH failed${NC}"

  echo ""
  CURRENT_TAG=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git describe --tags --abbrev=0 2>/dev/null" 2>/dev/null || echo "unknown")
  LATEST_TAG=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git tag -l | sort -V | tail -1" 2>/dev/null || echo "unknown")

  print_item "Current Tag" "$CURRENT_TAG"
  print_item "Latest Available" "$LATEST_TAG"

  if [ "$CURRENT_TAG" = "$LATEST_TAG" ]; then
    echo -e "\n  ${GREEN}✓ Kubespray is up to date${NC}"
  elif [ "$CURRENT_TAG" != "unknown" ] && [ "$LATEST_TAG" != "unknown" ]; then
    echo -e "\n  ${YELLOW}→ Kubespray upgrade available: ${CURRENT_TAG} → ${LATEST_TAG}${NC}"
    echo -e "  ${YELLOW}  Run: cd ~/kubespray && git checkout ${LATEST_TAG}${NC}"
  fi
}

sync_inventory() {
  print_header "Sync Inventory from Control Plane"

  echo ""
  REMOTE_INVENTORY="$KUBESPRAY_DIR/inventory/$INVENTORY_NAME"

  # Check remote inventory exists
  if ! ssh $SSH_OPTS "$CONTROL_PLANE" "test -d $REMOTE_INVENTORY" 2>/dev/null; then
    echo -e "  ${RED}✗ Remote inventory not found: $CONTROL_PLANE:$REMOTE_INVENTORY${NC}"
    exit 1
  fi

  # Show what will be synced
  echo -e "  ${YELLOW}Source:${NC}  $CONTROL_PLANE:$REMOTE_INVENTORY"
  echo -e "  ${YELLOW}Target:${NC}  $LOCAL_INVENTORY_DIR"
  echo ""

  # Backup local if exists
  BACKUP_BASE="$LOCAL_BACKUP_DIR"
  if [ -d "$LOCAL_INVENTORY_DIR" ]; then
    mkdir -p "$BACKUP_BASE"
    BACKUP_PATH="$BACKUP_BASE/inventory-${INVENTORY_NAME}_$(date +%Y%m%d_%H%M%S)"
    cp -r "$LOCAL_INVENTORY_DIR" "$BACKUP_PATH"
    echo -e "  ${GREEN}✓${NC} Local backup: backup/$(basename "$BACKUP_PATH")"

    # Keep only last 5 backups
    BACKUP_COUNT=$(ls -d "$BACKUP_BASE"/inventory-${INVENTORY_NAME}_* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKUP_COUNT" -gt 5 ]; then
      ls -dt "$BACKUP_BASE"/inventory-${INVENTORY_NAME}_* | tail -n +6 | xargs rm -rf
      echo -e "  ${GREEN}✓${NC} Cleaned old backups (kept last 5)"
    fi
  fi

  # Sync
  rsync -avz --delete -e "ssh $SSH_OPTS" \
    "$CONTROL_PLANE:$REMOTE_INVENTORY/" "$LOCAL_INVENTORY_DIR/" 2>/dev/null

  if [ $? -eq 0 ]; then
    echo ""
    echo -e "  ${GREEN}✓ Inventory synced successfully${NC}"
    echo ""
    echo -e "  ${YELLOW}[Synced files]${NC}"
    find "$LOCAL_INVENTORY_DIR" -type f | while read -r f; do
      echo "    - ${f#$LOCAL_INVENTORY_DIR/}"
    done

    # Show kubespray version from remote
    REMOTE_VER=$(ssh $SSH_OPTS "$CONTROL_PLANE" "cd $KUBESPRAY_DIR && git describe --tags --abbrev=0 2>/dev/null" 2>/dev/null || echo "unknown")
    echo ""
    print_item "Remote Kubespray" "$REMOTE_VER"
    echo ""
    echo -e "  ${YELLOW}Don't forget to commit:${NC}"
    echo "    cd $(dirname "$LOCAL_INVENTORY_DIR")"
    echo "    git add inventory-${INVENTORY_NAME}/ && git commit -m \"chore: sync kubespray inventory\""
  else
    echo -e "  ${RED}✗ Sync failed${NC}"
    exit 1
  fi
}

# =============================================================================
# Main
# =============================================================================
show_help() {
  cat <<HELP
Usage: $(basename "$0") [OPTION]

Kubespray & Kubernetes Version Check Script

Options:
  (default)         Check all versions (K8s, Kubespray, tools, supported, compatibility, tags)
  --k8s             Kubernetes cluster status and version
  --kubespray       Kubespray version and available tags
  --supported       Show supported K8s versions from current kubespray (from checksums.yml)
  --tools           Local tool versions (kubectl, helm, helmfile, ansible)
  --compatibility   Kubespray ↔ K8s version compatibility from GitHub releases
  --sync            Sync inventory from control plane to local (with backup)
  -h, --help        Show this help message

Examples:
  $(basename "$0")                  # Full check
  $(basename "$0") --k8s            # K8s cluster only
  $(basename "$0") --supported      # Current kubespray's supported K8s versions
  $(basename "$0") --kubespray      # Kubespray info + latest tags
  $(basename "$0") --compatibility  # Version matrix from GitHub API
  $(basename "$0") --sync           # Sync inventory from control plane
HELP
}

case "${1:-all}" in
  -h|--help)
    show_help
    ;;
  --k8s)
    check_k8s
    ;;
  --kubespray)
    check_kubespray
    check_available_tags
    ;;
  --supported)
    check_supported_versions
    ;;
  --sync)
    sync_inventory
    ;;
  --compatibility)
    check_compatibility
    ;;
  --tools)
    check_tools
    ;;
  all)
    check_k8s
    check_kubespray
    check_supported_versions
    check_tools
    check_compatibility
    check_available_tags
    ;;
  *)
    echo "Unknown option: $1"
    echo ""
    show_help
    exit 1
    ;;
esac

echo ""
