#!/bin/bash
set -e

#############################################
# GitLab Artifact Cleanup Tool
# Modes: list / delete / cleanup
#############################################

# Defaults
GITLAB_URL="${GITLAB_URL:-http://gitlab.example.com}"
GITLAB_TOKEN="${GITLAB_TOKEN:-<your-gitlab-token>}"
PROJECT_ID=""
MODE=""
EXPIRED_ONLY=false
DRY_RUN=false
OLDER_THAN=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
  echo "Usage: $0 [options] <mode>"
  echo ""
  echo "Modes:"
  echo "  projects               List all projects with IDs"
  echo "  list                   List artifacts"
  echo "  delete                 Delete all matching artifacts"
  echo "  cleanup                List first, then confirm and delete"
  echo ""
  echo "Required:"
  echo "  -p, --project <ID>     GitLab project ID (not needed for projects mode)"
  echo "  -t, --token <TOKEN>    GitLab Private Token (or GITLAB_TOKEN env var)"
  echo ""
  echo "Options:"
  echo "  -u, --url <URL>        GitLab URL (default: ${GITLAB_URL})"
  echo "  -e, --expired          Target only expired artifacts"
  echo "  -o, --older-than <N>   Target artifacts older than N days (e.g. 7)"
  echo "  -n, --dry-run          Show targets without actually deleting"
  echo "  -h, --help             Show this help"
  echo ""
  echo "Examples:"
  echo "  # List all artifacts"
  echo "  $0 -p 15 -t \$TOKEN list"
  echo ""
  echo "  # List only expired artifacts"
  echo "  $0 -p 15 -t \$TOKEN -e list"
  echo ""
  echo "  # Cleanup artifacts older than 7 days"
  echo "  $0 -p 15 -t \$TOKEN -o 7 cleanup"
  echo ""
  echo "  # Dry-run before deleting"
  echo "  $0 -p 15 -t \$TOKEN -n delete"
  echo ""
  echo "  # List all projects"
  echo "  $0 projects"
  echo ""
  echo "  # Using environment variable"
  echo "  GITLAB_TOKEN=\$TOKEN $0 -p 15 cleanup"
  exit 1
}

# List projects
list_projects() {
  echo ""
  echo -e "${CYAN}Fetching projects...${NC}"
  echo ""

  local page=1
  local per_page=100

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  printf "  %-6s %-40s %s\n" "ID" "Project" "Description"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local total=0
  while true; do
    local response
    response=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${GITLAB_URL}/api/v4/projects?per_page=${per_page}&page=${page}&order_by=id&sort=asc")

    if [ "$response" = "[]" ] || [ -z "$response" ]; then
      break
    fi

    echo "$response" | python3 -c "
import sys, json
projects = json.load(sys.stdin)
for p in projects:
    desc = (p.get('description') or '')[:30]
    print(f\"  {p['id']:<6} {p['path_with_namespace']:<40} {desc}\")
" 2>/dev/null

    local page_count
    page_count=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    total=$((total + page_count))

    if [ "$page_count" -lt "$per_page" ]; then
      break
    fi
    page=$((page + 1))
  done

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Total: ${GREEN}${total}${NC} projects"
  echo ""
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--project)   PROJECT_ID="$2"; shift 2 ;;
    -t|--token)     GITLAB_TOKEN="$2"; shift 2 ;;
    -u|--url)       GITLAB_URL="$2"; shift 2 ;;
    -e|--expired)   EXPIRED_ONLY=true; shift ;;
    -o|--older-than) OLDER_THAN="$2"; shift 2 ;;
    -n|--dry-run)   DRY_RUN=true; shift ;;
    -h|--help)      usage ;;
    -*)             echo -e "${RED}Unknown option: $1${NC}"; usage ;;
    *)              MODE="$1"; shift ;;
  esac
done

# Validate required
if [ -z "$GITLAB_TOKEN" ]; then
  echo -e "${RED}GitLab token is required. (-t option or GITLAB_TOKEN env var)${NC}"
  usage
fi

if [ -z "$MODE" ]; then
  echo -e "${RED}Please specify a mode. (projects / list / delete / cleanup)${NC}"
  usage
fi

# projects mode doesn't need project ID
if [ "$MODE" = "projects" ]; then
  list_projects
  exit 0
fi

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Project ID is required. (-p option)${NC}"
  echo -e "${YELLOW}List projects: $0 projects${NC}"
  usage
fi

API_URL="${GITLAB_URL}/api/v4/projects/${PROJECT_ID}"

# Cutoff date for --older-than
get_cutoff_date() {
  if [ -n "$OLDER_THAN" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      date -v-${OLDER_THAN}d -u +"%Y-%m-%dT%H:%M:%SZ"
    else
      date -u -d "${OLDER_THAN} days ago" +"%Y-%m-%dT%H:%M:%SZ"
    fi
  fi
}

# Fetch artifacts with pagination
fetch_artifacts() {
  local page=1
  local per_page=100
  local tmp_file
  tmp_file=$(mktemp)

  echo "[" > "$tmp_file"
  local first=true

  while true; do
    local response
    response=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${API_URL}/jobs?per_page=${per_page}&page=${page}")

    if [ "$response" = "[]" ] || [ -z "$response" ]; then
      break
    fi

    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$tmp_file"
    fi
    echo "$response" | python3 -c "
import sys, json
items = json.load(sys.stdin)
print(','.join(json.dumps(i) for i in items))
" >> "$tmp_file"

    local count
    count=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [ "$count" -lt "$per_page" ]; then
      break
    fi

    page=$((page + 1))
  done

  echo "]" >> "$tmp_file"

  # Filter jobs with artifacts
  cat "$tmp_file" | python3 -c "
import sys, json
from datetime import datetime, timezone, timedelta

expired_only = '$EXPIRED_ONLY' == 'true'
older_than = '$OLDER_THAN'
cutoff = None
if older_than:
    cutoff = datetime.now(timezone.utc) - timedelta(days=int(older_than))

data = json.load(sys.stdin)

results = []
for job in data:
    artifacts = [a for a in job.get('artifacts', []) if a.get('filename') != 'job.log']
    if not artifacts:
        continue

    if expired_only:
        has_expired = False
        for a in artifacts:
            exp = a.get('expire_at')
            if exp:
                exp_dt = datetime.fromisoformat(exp.replace('Z', '+00:00'))
                if exp_dt < datetime.now(timezone.utc):
                    has_expired = True
                    break
        if not has_expired:
            continue

    if cutoff:
        created = job.get('created_at', '')
        if created:
            created_dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
            if created_dt > cutoff:
                continue

    total_size = sum(a.get('size', 0) for a in artifacts)
    results.append({
        'id': job['id'],
        'name': job.get('name', 'unknown'),
        'ref': job.get('ref', ''),
        'created_at': job.get('created_at', ''),
        'size': total_size,
        'artifact_count': len(artifacts),
        'pipeline_id': job.get('pipeline', {}).get('id', '')
    })

print(json.dumps(results))
" 2>/dev/null

  rm -f "$tmp_file"
}

# Human-readable size
human_size() {
  local bytes=$1
  if [ "$bytes" -ge 1073741824 ]; then
    echo "$(echo "scale=1; $bytes / 1073741824" | bc) GiB"
  elif [ "$bytes" -ge 1048576 ]; then
    echo "$(echo "scale=1; $bytes / 1048576" | bc) MiB"
  elif [ "$bytes" -ge 1024 ]; then
    echo "$(echo "scale=1; $bytes / 1024" | bc) KiB"
  else
    echo "${bytes} B"
  fi
}

# Print list
print_list() {
  local artifacts_json="$1"
  local count
  count=$(echo "$artifacts_json" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))")

  if [ "$count" -eq 0 ]; then
    echo -e "${YELLOW}No matching artifacts found.${NC}"
    return 1
  fi

  local total_size
  total_size=$(echo "$artifacts_json" | python3 -c "import sys,json; data=json.load(sys.stdin); print(sum(d['size'] for d in data))")

  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  printf "  %-12s %-25s %-12s %-10s %s\n" "Job ID" "Job Name" "Pipeline" "Size" "Created"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  echo "$artifacts_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for d in data:
    size = d['size']
    if size >= 1048576:
        size_str = f\"{size/1048576:.1f} MiB\"
    elif size >= 1024:
        size_str = f\"{size/1024:.1f} KiB\"
    else:
        size_str = f\"{size} B\"
    date_str = d['created_at'][:10] if d['created_at'] else ''
    print(f\"  {d['id']:<12} {d['name']:<25} #{d['pipeline_id']:<11} {size_str:<10} {date_str}\")
"

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Total: ${GREEN}${count}${NC} artifacts, $(human_size "$total_size")"
  echo ""
}

# Delete artifacts
delete_artifacts() {
  local artifacts_json="$1"
  local count
  count=$(echo "$artifacts_json" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))")

  if [ "$count" -eq 0 ]; then
    echo -e "${YELLOW}No artifacts to delete.${NC}"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN] Showing targets only, no actual deletion.${NC}"
    print_list "$artifacts_json"
    return 0
  fi

  local job_ids
  job_ids=$(echo "$artifacts_json" | python3 -c "import sys,json; [print(d['id']) for d in json.load(sys.stdin)]")

  local success=0
  local fail=0
  local total=$count

  echo ""
  for job_id in $job_ids; do
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --request DELETE \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${API_URL}/jobs/${job_id}/artifacts")

    if [ "$status_code" = "204" ] || [ "$status_code" = "200" ]; then
      success=$((success + 1))
      echo -e "  ${GREEN}✓${NC} Job ${job_id} deleted (${success}/${total})"
    else
      fail=$((fail + 1))
      echo -e "  ${RED}✗${NC} Job ${job_id} failed (HTTP ${status_code})"
    fi
  done

  echo ""
  echo -e "Result: ${GREEN}${success} succeeded${NC}, ${RED}${fail} failed${NC} / ${total} total"
}

# ── Main ──

echo ""
echo -e "${GREEN}=== GitLab Artifact Cleanup ===${NC}"
echo "  GitLab:     ${GITLAB_URL}"
echo "  Project ID: ${PROJECT_ID}"
echo "  Mode:       ${MODE}"
[ "$EXPIRED_ONLY" = true ] && echo "  Filter:     Expired only"
[ -n "$OLDER_THAN" ] && echo "  Filter:     Older than ${OLDER_THAN} days"
[ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}[DRY-RUN MODE]${NC}"
echo ""

echo -e "${CYAN}Fetching artifacts...${NC}"
ARTIFACTS=$(fetch_artifacts)

case "$MODE" in
  list)
    print_list "$ARTIFACTS"
    ;;

  delete)
    print_list "$ARTIFACTS" || exit 0
    if [ "$DRY_RUN" = false ]; then
      echo -e "${RED}All artifacts listed above will be deleted.${NC}"
      echo -ne "${YELLOW}Continue? (y/N): ${NC}"
      read -r CONFIRM
      if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Cancelled."
        exit 0
      fi
    fi
    delete_artifacts "$ARTIFACTS"
    ;;

  cleanup)
    print_list "$ARTIFACTS" || exit 0
    echo -ne "${YELLOW}Delete the artifacts listed above? (y/N): ${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "Cancelled."
      exit 0
    fi
    delete_artifacts "$ARTIFACTS"
    ;;

  *)
    echo -e "${RED}Unknown mode: ${MODE}${NC}"
    usage
    ;;
esac

echo -e "${GREEN}Done!${NC}"
