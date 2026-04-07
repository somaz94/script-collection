#!/bin/bash
# =============================================================================
# Post-Upgrade Health Check Script
#
# Run after K8s upgrade to verify cluster health.
# Can run from local machine (requires kubectl access) or control plane.
#
# Usage:
#   ./post-upgrade-check.sh           # Full check
#   ./post-upgrade-check.sh --quick   # Quick check (nodes + pods only)
#   ./post-upgrade-check.sh -h        # Help
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
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

pass() {
  echo -e "  ${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

warn() {
  echo -e "  ${YELLOW}⚠${NC} $1"
  WARN=$((WARN + 1))
}

show_help() {
  cat <<HELP
Usage: $(basename "$0") [OPTION]

Post-Upgrade Health Check Script

Options:
  (default)     Full check (nodes, version, pods, services, DNS, certs, containerd, etcd)
  --quick       Quick check (nodes + pods only)
  -h, --help    Show this help message
HELP
}

# =============================================================================
# Checks
# =============================================================================

check_nodes() {
  print_header "1. Node Status"

  echo ""
  kubectl get nodes -o wide 2>/dev/null || { fail "kubectl not available"; return; }

  echo ""
  # Check all nodes Ready
  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | grep -v "Ready," || true)
  if [ -z "$NOT_READY" ]; then
    pass "All nodes are Ready"
  else
    fail "Some nodes are NOT Ready:"
    echo "$NOT_READY" | while read -r line; do echo "    $line"; done
  fi

  # Check SchedulingDisabled
  DISABLED=$(kubectl get nodes --no-headers 2>/dev/null | grep "SchedulingDisabled" || true)
  if [ -z "$DISABLED" ]; then
    pass "No nodes are SchedulingDisabled (cordoned)"
  else
    fail "Nodes still cordoned (run: kubectl uncordon <node>):"
    echo "$DISABLED" | while read -r line; do echo "    $line"; done
  fi

  # Check node count
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NODE_COUNT" -eq "$EXPECTED_NODES" ]; then
    pass "Node count: $NODE_COUNT (expected: $EXPECTED_NODES)"
  else
    fail "Node count: $NODE_COUNT (expected: $EXPECTED_NODES)"
  fi
}

check_version() {
  print_header "2. K8s Version Consistency"

  echo ""
  VERSIONS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' 2>/dev/null)
  echo "$VERSIONS" | while read -r line; do
    echo "  $line"
  done

  echo ""
  UNIQUE_VERSIONS=$(echo "$VERSIONS" | awk '{print $2}' | sort -u)
  VERSION_COUNT=$(echo "$UNIQUE_VERSIONS" | wc -l | tr -d ' ')

  if [ "$VERSION_COUNT" -eq 1 ]; then
    pass "All nodes on same version: $(echo "$UNIQUE_VERSIONS" | head -1)"
  else
    fail "Version mismatch detected:"
    echo "$UNIQUE_VERSIONS" | while read -r v; do echo "    - $v"; done
  fi

  # Server version
  SERVER_VER=$(kubectl version -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])" 2>/dev/null || echo "unknown")
  echo ""
  echo "  API Server: $SERVER_VER"
}

check_pods() {
  print_header "3. Pod Status"

  echo ""
  # System pods
  FAILED_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed\|Terminating" || true)
  if [ -z "$FAILED_PODS" ]; then
    pass "All pods are Running/Completed"
  else
    fail "Unhealthy pods found:"
    echo "$FAILED_PODS" | while read -r line; do echo "    $line"; done
  fi

  # CrashLoopBackOff
  CRASH_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep "CrashLoopBackOff" || true)
  if [ -z "$CRASH_PODS" ]; then
    pass "No CrashLoopBackOff pods"
  else
    fail "CrashLoopBackOff pods:"
    echo "$CRASH_PODS" | while read -r line; do echo "    $line"; done
  fi

  # Restart counts > 10
  echo ""
  HIGH_RESTARTS=$(kubectl get pods -A --no-headers 2>/dev/null | awk '{if ($5+0 > 10) print $0}' || true)
  if [ -z "$HIGH_RESTARTS" ]; then
    pass "No pods with excessive restarts (>10)"
  else
    warn "Pods with high restart count:"
    echo "$HIGH_RESTARTS" | while read -r line; do echo "    $line"; done
  fi
}

check_system_pods() {
  print_header "4. System Components"

  echo ""
  COMPONENTS=("coredns" "cilium" "kube-proxy" "metrics-server")
  for comp in "${COMPONENTS[@]}"; do
    COUNT=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep "$comp" | grep "Running" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
      pass "$comp: $COUNT pod(s) running"
    else
      fail "$comp: not running"
    fi
  done
}

check_dns() {
  print_header "5. DNS Resolution"

  echo ""
  # Test DNS from a pod
  DNS_RESULT=$(kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never --timeout=30s -- nslookup kubernetes.default.svc.concrit-cluster.local 2>/dev/null || echo "DNS_FAILED")

  if echo "$DNS_RESULT" | grep -q "Address" 2>/dev/null; then
    pass "DNS resolution working (kubernetes.default.svc)"
  else
    warn "DNS test inconclusive (may need manual verification)"
    echo "  Run: kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default"
  fi
}

check_certificates() {
  print_header "6. Certificate Expiration"

  echo ""
  CERT_OUTPUT=$(ssh $SSH_OPTS "$CONTROL_PLANE" "sudo kubeadm certs check-expiration 2>/dev/null" 2>/dev/null || echo "SSH_FAILED")

  if echo "$CERT_OUTPUT" | grep -q "SSH_FAILED"; then
    warn "Cannot check certificates via SSH"
    echo "  Run on control plane: sudo kubeadm certs check-expiration"
  else
    echo "$CERT_OUTPUT" | grep -E "CERTIFICATE|AUTHORITY|admin|apiserver|controller|etcd|front|scheduler" | while read -r line; do
      if echo "$line" | grep -q "EXPIRES"; then
        echo "  $line"
      else
        # Check if expiring within 30 days
        EXPIRY=$(echo "$line" | grep -oE "[A-Z][a-z]{2} [0-9]{2}, [0-9]{4}" || true)
        echo "  $line"
      fi
    done

    # Check if any cert expires within 30 days
    SOON=$(echo "$CERT_OUTPUT" | grep -E "^[a-z]" | awk '{print $NF}' | grep -v "no" | head -1 || true)
    if [ -n "$SOON" ]; then
      pass "Certificates are valid"
    fi
  fi
}

check_containerd() {
  print_header "7. Containerd & Registry"

  echo ""
  for node in $CLUSTER_NODES; do
    HARBOR_CONFIG=$(ssh $SSH_OPTS "${CONTROL_PLANE_USER}@$node" "sudo cat /etc/containerd/certs.d/${HARBOR_HOST}/hosts.toml 2>/dev/null" 2>/dev/null || echo "NOT_FOUND")
    NODE_NAME=$(ssh $SSH_OPTS "${CONTROL_PLANE_USER}@$node" "hostname" 2>/dev/null || echo "$node")

    if echo "$HARBOR_CONFIG" | grep -q "$HARBOR_HOST"; then
      pass "$NODE_NAME ($node): Harbor registry configured"
    else
      fail "$NODE_NAME ($node): Harbor registry config MISSING"
    fi
  done
}

check_etcd() {
  print_header "8. etcd Health"

  echo ""
  ETCD_HEALTH=$(ssh $SSH_OPTS "$CONTROL_PLANE" "sudo ETCDCTL_API=3 etcdctl endpoint health \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=$ETCD_CACERT \
    --cert=$ETCD_CERT \
    --key=$ETCD_KEY 2>/dev/null" 2>/dev/null || echo "CHECK_FAILED")

  if echo "$ETCD_HEALTH" | grep -q "is healthy"; then
    pass "etcd is healthy"
    echo "  $ETCD_HEALTH"
  elif echo "$ETCD_HEALTH" | grep -q "CHECK_FAILED"; then
    warn "Cannot check etcd health via SSH"
  else
    fail "etcd health check failed"
    echo "  $ETCD_HEALTH"
  fi
}

check_api_health() {
  print_header "9. API Server Health"

  echo ""
  READYZ=$(kubectl get --raw='/readyz?verbose' 2>/dev/null | grep -c "ok" || echo "0")
  TOTAL=$(kubectl get --raw='/readyz?verbose' 2>/dev/null | grep -cE "ok|failed" || echo "0")

  if [ "$READYZ" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    pass "API server readyz: $READYZ/$TOTAL checks passed"
  else
    FAILED_CHECKS=$(kubectl get --raw='/readyz?verbose' 2>/dev/null | grep "failed" || true)
    if [ -n "$FAILED_CHECKS" ]; then
      fail "API server readyz: some checks failed"
      echo "$FAILED_CHECKS" | while read -r line; do echo "    $line"; done
    else
      warn "Cannot verify API server health"
    fi
  fi
}

print_summary() {
  print_header "Summary"

  echo ""
  echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}"
  echo ""

  if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║   Upgrade verification PASSED ✓      ║${NC}"
    echo -e "  ${GREEN}╚═══════════════════════════════════════╝${NC}"
  else
    echo -e "  ${RED}╔═══════════════════════════════════════╗${NC}"
    echo -e "  ${RED}║   Upgrade verification FAILED ✗      ║${NC}"
    echo -e "  ${RED}║   Review failed checks above         ║${NC}"
    echo -e "  ${RED}╚═══════════════════════════════════════╝${NC}"
  fi
  echo ""
}

# =============================================================================
# Main
# =============================================================================

case "${1:-full}" in
  -h|--help)
    show_help
    ;;
  --quick)
    check_nodes
    check_pods
    print_summary
    ;;
  full|*)
    check_nodes
    check_version
    check_pods
    check_system_pods
    check_dns
    check_certificates
    check_containerd
    check_etcd
    check_api_health
    print_summary
    ;;
esac
