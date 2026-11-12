# shellcheck shell=bash
# =============================================================================
# scripts/svn/lib/svn-user-manager.sh — Shared SVN user create/delete logic
# =============================================================================
# Shared user-management logic used by the Project M, Project BH and SecondaryProject SVN
# servers. Callers (svn/*.sh) wire it up in this order:
#
#   1) source "<relative-path>/lib/svn-user-manager.sh"
#   2) source "<relative-path>/svn/<server>.conf"   (defines variables)
#   3) USERNAMES=( ... )                             (target user list)
#   4) svn_run_main create                           (or delete)
#
# The caller (via the .conf file) must define:
#   SVN_SERVER_IP, SVN_SERVER_USER, SVN_SERVER_PASSWORD,
#   DOCKER_CONTAINER, DOCKER_NEEDS_SUDO, DOCKER_BIN, ENABLE_CONTAINER_CHECK,
#   SVN_CONF_PATH, SVN_AUTHZ_FILE, SVN_PASSWD_FILE,
#   SVN_USER_PASSWORD, SVN_REPO_ROOT
#
# Idempotent guard.
# User-facing runtime messages stay in Korean because every caller
# (example-project / projectbh / secondary-project) targets a Korean ops team — converting them requires
# a separate decision per repository policy.
# =============================================================================

[[ -n "${__SCRIPTS_LIB_SVN_USER_MANAGER_LOADED:-}" ]] && return 0
__SCRIPTS_LIB_SVN_USER_MANAGER_LOADED=1

# -----------------------------------------------------------------------------
# Internal helper — assemble the `docker exec` prefix used in remote SSH.
# -----------------------------------------------------------------------------
# Rule:
#   - DOCKER_NEEDS_SUDO=true  → "echo '$PASS' | sudo -S /usr/local/bin/docker"
#   - DOCKER_NEEDS_SUDO=false → "docker"
# Interpolated verbatim into the remote SSH heredoc.
_svn_docker_exec_prefix() {
  if [[ "${DOCKER_NEEDS_SUDO:-false}" == "true" ]]; then
    printf "echo '%s' | sudo -S %s" "${SVN_SERVER_PASSWORD}" "${DOCKER_BIN:-/usr/local/bin/docker}"
  else
    printf '%s' "${DOCKER_BIN:-docker}"
  fi
}

# -----------------------------------------------------------------------------
# Pre-flight checks — sshpass present, SSH reachable, container running.
# -----------------------------------------------------------------------------
svn_check_prerequisites() {
  if ! command -v sshpass &>/dev/null; then
    echo "✗ sshpass 가 설치되어 있지 않습니다. 먼저 설치해 주세요."
    echo "  MacOS: brew install sshpass"
    echo "  Ubuntu/Debian: apt-get install sshpass"
    echo "  CentOS/RHEL: yum install sshpass"
    exit 1
  fi

  echo "▸ SVN 서버 SSH 연결 확인 중..."
  export SSHPASS="${SVN_SERVER_PASSWORD}"
  if ! sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "echo '✔ SSH connection successful'" &>/dev/null; then
    echo "✗ SVN 서버 ${SVN_SERVER_IP} 에 연결할 수 없습니다"
    exit 1
  fi
  echo "✔ SVN 서버 SSH 연결 성공"

  if [[ "${ENABLE_CONTAINER_CHECK:-true}" != "true" ]]; then
    echo "▲ 컨테이너 검증 단계 건너뜀 (Docker 명령에 sudo 가 필요한 환경)"
    echo "▲ 서버에서 'sudo docker ps' 로 ${DOCKER_CONTAINER} 가동 여부를 직접 확인하세요"
    return 0
  fi

  echo "▸ Docker 컨테이너 ${DOCKER_CONTAINER} 가동 여부 확인 중..."
  local docker_running
  docker_running=$(sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" \
    "docker ps | grep ${DOCKER_CONTAINER} || echo 'not running'")
  if [[ "${docker_running}" == "not running" ]]; then
    echo "✗ Docker 컨테이너 ${DOCKER_CONTAINER} 가 실행 중이 아닙니다"
    exit 1
  fi
  echo "✔ Docker 컨테이너 ${DOCKER_CONTAINER} 실행 중"
}

# -----------------------------------------------------------------------------
# svn_user_create USERNAME
#   Returns: 0 = newly added, 2 = already existed (no change), 1 = failure.
# -----------------------------------------------------------------------------
svn_user_create() {
  local USERNAME="$1"
  local DOCKER_PREFIX
  DOCKER_PREFIX="$(_svn_docker_exec_prefix)"

  echo "▸ 사용자 '${USERNAME}' 를 SVN 에 읽기-쓰기 권한으로 추가 중..."

  export SSHPASS="${SVN_SERVER_PASSWORD}"
  local CHECK_RESULT
  CHECK_RESULT=$(sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "
    AUTHZ_EXISTS=\$(${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} grep -q \"^${USERNAME}=\" ${SVN_AUTHZ_FILE} && echo true || echo false)
    PASSWD_EXISTS=\$(${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} grep -q \"^${USERNAME}=\" ${SVN_PASSWD_FILE} && echo true || echo false)
    if [ \"\$AUTHZ_EXISTS\" = \"true\" ] && [ \"\$PASSWD_EXISTS\" = \"true\" ]; then
      echo USER_EXISTS=BOTH
    else
      echo USER_EXISTS=NO
    fi
  ")

  if echo "${CHECK_RESULT}" | grep -q "USER_EXISTS=BOTH"; then
    echo "◆ 사용자 '${USERNAME}' 는 이미 SVN 설정에 존재합니다"
    return 2
  fi

  echo "▸ 사용자 신규 추가 진행..."
  if [[ "${SVN_DRY_RUN:-0}" == "1" ]]; then
    echo "    (dry-run) ssh ${SVN_SERVER_USER}@${SVN_SERVER_IP} \"${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} bash -c 'append ${USERNAME}=rw to ${SVN_AUTHZ_FILE} + ${USERNAME}=${SVN_USER_PASSWORD} to ${SVN_PASSWD_FILE}'\""
    echo "✔ (dry-run) plan for '${USERNAME}' printed"
    return 0
  fi
  local MODIFY_RESULT
  MODIFY_RESULT=$(sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "
    ${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} bash -c \"
      cd ${SVN_CONF_PATH}
      AUTH_EXISTS=false
      PASSWD_EXISTS=false
      MODIFIED=false
      grep -q '^${USERNAME}=' ${SVN_AUTHZ_FILE} && AUTH_EXISTS=true
      grep -q '^${USERNAME}=' ${SVN_PASSWD_FILE} && PASSWD_EXISTS=true

      if [ \\\"\\\$AUTH_EXISTS\\\" = \\\"true\\\" ] && [ \\\"\\\$PASSWD_EXISTS\\\" = \\\"true\\\" ]; then
        echo 'USER_MODIFIED=false'
        exit 0
      fi

      if [ \\\"\\\$AUTH_EXISTS\\\" != \\\"true\\\" ]; then
        cp ${SVN_AUTHZ_FILE} ${SVN_AUTHZ_FILE}.bak
        echo '${USERNAME}=rw' >> ${SVN_AUTHZ_FILE}
        MODIFIED=true
      fi

      if [ \\\"\\\$PASSWD_EXISTS\\\" != \\\"true\\\" ]; then
        cp ${SVN_PASSWD_FILE} ${SVN_PASSWD_FILE}.bak
        echo '${USERNAME}=${SVN_USER_PASSWORD}' >> ${SVN_PASSWD_FILE}
        MODIFIED=true
      fi

      if [ \\\"\\\$MODIFIED\\\" = \\\"true\\\" ]; then
        echo 'USER_MODIFIED=true'
      else
        echo 'USER_MODIFIED=false'
      fi
    \"
  ")

  if echo "${MODIFY_RESULT}" | grep -q "USER_MODIFIED=true"; then
    echo "✔ 사용자 '${USERNAME}' 추가 완료"
    return 0
  elif echo "${MODIFY_RESULT}" | grep -q "USER_MODIFIED=false"; then
    echo "◆ 사용자 '${USERNAME}' 변경 사항 없음"
    return 2
  else
    echo "✗ 사용자 '${USERNAME}' 추가 실패"
    echo "  응답: ${MODIFY_RESULT}"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# svn_user_delete USERNAME
#   Returns: 0 = deleted, 2 = not present (no change), 1 = failure.
# -----------------------------------------------------------------------------
svn_user_delete() {
  local USERNAME="$1"
  local DOCKER_PREFIX
  DOCKER_PREFIX="$(_svn_docker_exec_prefix)"

  echo "▸ SVN 에서 사용자 '${USERNAME}' 존재 여부 확인 중..."

  export SSHPASS="${SVN_SERVER_PASSWORD}"
  local USER_EXISTS
  USER_EXISTS=$(sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "
    AUTH_EXISTS=\$(${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} grep -q \"^${USERNAME}=\" ${SVN_AUTHZ_FILE} && echo true || echo false)
    PASSWD_EXISTS=\$(${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} grep -q \"^${USERNAME}=\" ${SVN_PASSWD_FILE} && echo true || echo false)
    if [ \"\$AUTH_EXISTS\" = \"false\" ] && [ \"\$PASSWD_EXISTS\" = \"false\" ]; then
      echo NOT_FOUND
    else
      echo FOUND
    fi
  ")

  if echo "${USER_EXISTS}" | grep -q "NOT_FOUND"; then
    echo "▲ 사용자 '${USERNAME}' 가 SVN 설정에 존재하지 않습니다"
    return 2
  fi

  echo "▸ 사용자 '${USERNAME}' 삭제 진행..."
  if [[ "${SVN_DRY_RUN:-0}" == "1" ]]; then
    echo "    (dry-run) ssh ${SVN_SERVER_USER}@${SVN_SERVER_IP} \"${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} bash -c 'sed -i /^${USERNAME}=/d ${SVN_AUTHZ_FILE} ${SVN_PASSWD_FILE}'\""
    echo "✔ (dry-run) plan for '${USERNAME}' printed"
    return 0
  fi
  local DELETED
  DELETED=$(sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "
    ${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} bash -c \"
      cd ${SVN_CONF_PATH}
      AUTH_DELETED=false
      PASSWD_DELETED=false

      if grep -q '^${USERNAME}=' ${SVN_AUTHZ_FILE}; then
        cp ${SVN_AUTHZ_FILE} ${SVN_AUTHZ_FILE}.bak
        sed -i '/^${USERNAME}=/d' ${SVN_AUTHZ_FILE}
        grep -q '^${USERNAME}=' ${SVN_AUTHZ_FILE} || AUTH_DELETED=true
      fi

      if grep -q '^${USERNAME}=' ${SVN_PASSWD_FILE}; then
        cp ${SVN_PASSWD_FILE} ${SVN_PASSWD_FILE}.bak
        sed -i '/^${USERNAME}=/d' ${SVN_PASSWD_FILE}
        grep -q '^${USERNAME}=' ${SVN_PASSWD_FILE} || PASSWD_DELETED=true
      fi

      if [ \\\"\\\$AUTH_DELETED\\\" = \\\"true\\\" ] || [ \\\"\\\$PASSWD_DELETED\\\" = \\\"true\\\" ]; then
        echo DELETED
      else
        echo FAILED
      fi
    \"
  ")

  if echo "${DELETED}" | grep -q "DELETED"; then
    echo "✔ 사용자 '${USERNAME}' 삭제 완료"
    return 0
  else
    echo "✗ 사용자 '${USERNAME}' 삭제 실패"
    echo "  응답: ${DELETED}"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Restart the svnserve daemon — required after authz/passwd file edits.
# -----------------------------------------------------------------------------
svn_restart_service() {
  local DOCKER_PREFIX
  DOCKER_PREFIX="$(_svn_docker_exec_prefix)"

  if [[ "${SVN_DRY_RUN:-0}" == "1" ]]; then
    echo "    (dry-run) ssh ${SVN_SERVER_USER}@${SVN_SERVER_IP} \"${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} restart svnserve\""
    return 0
  fi

  echo "↻ SVN 서비스 재시작 중..."

  export SSHPASS="${SVN_SERVER_PASSWORD}"
  sshpass -e ssh -o StrictHostKeyChecking=no \
    "${SVN_SERVER_USER}@${SVN_SERVER_IP}" "
    ${DOCKER_PREFIX} exec ${DOCKER_CONTAINER} bash -c '
      SVN_PID=\$(ps -ef | grep \"svnserve -d -r\" | grep -v grep | awk \"{print \\\$2}\")
      if [ -z \"\$SVN_PID\" ]; then
        echo \"SVN service is not running\"
      else
        echo \"Stopping SVN service with PID \$SVN_PID\"
        kill -9 \$SVN_PID
        sleep 1
      fi
      echo \"Starting SVN service...\"
      svnserve -d -r ${SVN_REPO_ROOT}
      NEW_PID=\$(ps -ef | grep \"svnserve -d -r\" | grep -v grep | awk \"{print \\\$2}\")
      if [ -n \"\$NEW_PID\" ]; then
        echo \"SVN service started successfully with PID \$NEW_PID\"
      else
        echo \"Failed to start SVN service\"
        exit 1
      fi
    '
  "

  local RESULT=$?
  if [ "${RESULT}" -eq 0 ]; then
    echo "✔ SVN 서비스 재시작 완료"
  else
    echo "✗ SVN 서비스 재시작 실패"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# svn_print_usage MODE
#   Emit the caller wrapper's usage text. Invoked by -h/--help handlers.
# -----------------------------------------------------------------------------
svn_print_usage() {
  local MODE="${1:-create}"
  local label="추가"
  [[ "${MODE}" == "delete" ]] && label="삭제"

  cat <<USAGE
사용법: ${0##*/} [옵션]

  SVN 서버에 사용자를 ${label} 합니다.

  대상 사용자: 스크립트 상단의 USERNAMES 배열에 정의 (편집 후 실행)
  서버 설정:   같은 디렉토리의 *.conf 파일 (example-project.conf | projectbh.conf | secondary-project.conf)
  공용 로직:   scripts/svn/lib/svn-user-manager.sh

옵션:
  --dry-run     mutating ssh 호출 (authz / passwd 수정 + svnserve 재시작) 을
                출력만 하고 실행하지 않음. 사전 검증 + 존재 여부 조회는 그대로.
  -h, --help    이 도움말을 표시하고 종료

동작 요약:
  1) sshpass / SSH 연결 / Docker 컨테이너 가동 여부 사전 검증
  2) USERNAMES 배열을 순회하며 사용자 ${label} (authz / passwd 파일 수정)
  3) 변경이 발생한 경우에만 svnserve 데몬 재시작
USAGE
}

# -----------------------------------------------------------------------------
# svn_run_main MODE [args...]   (MODE = create | delete)
#   Iterate USERNAMES, perform the work, and restart svnserve only when
#   something actually changed. Extra args supported: -h / --help only.
# -----------------------------------------------------------------------------
svn_run_main() {
  local MODE="${1:-}"
  case "${MODE}" in
    create|delete) ;;
    *)
      echo "✗ 알 수 없는 MODE: '${MODE}' (create | delete 만 지원)" >&2
      return 1
      ;;
  esac
  shift

  # Extra option parsing — -h/--help / --dry-run.
  SVN_DRY_RUN="${SVN_DRY_RUN:-0}"
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        svn_print_usage "${MODE}"
        exit 0
        ;;
      --dry-run)
        SVN_DRY_RUN=1
        shift
        ;;
      *)
        echo "✗ 알 수 없는 옵션: '$1' ('-h' 로 도움말 확인)" >&2
        return 1
        ;;
    esac
  done
  export SVN_DRY_RUN

  if [[ -z "${USERNAMES[*]:-}" ]]; then
    echo "✗ USERNAMES 배열이 비어 있습니다 — 스크립트 상단에서 정의하세요" >&2
    return 1
  fi

  svn_check_prerequisites

  local label="추가" worker="svn_user_create"
  if [[ "${MODE}" == "delete" ]]; then
    label="삭제"
    worker="svn_user_delete"
  fi

  echo "▸ SVN 사용자 ${label} 작업 시작..."

  local CHANGED=false
  local USERNAME="" RESULT=""
  for USERNAME in "${USERNAMES[@]}"; do
    echo "----------------------------------------"
    echo "▸ 처리 대상: ${USERNAME}"

    set +e
    "${worker}" "${USERNAME}"
    RESULT=$?
    set -e

    case "${RESULT}" in
      0) CHANGED=true; echo "✔ ${USERNAME} ${label} 성공" ;;
      2) echo "◆ ${USERNAME} 변경 없음 (이미 ${label} 된 상태)" ;;
      *) echo "✗ ${USERNAME} 처리 실패" ;;
    esac
    echo "----------------------------------------"
  done

  if [[ "${CHANGED}" == "true" ]]; then
    echo "▸ 변경 감지 — SVN 서비스 재시작..."
    svn_restart_service
  else
    echo "◆ 변경 사항 없음 — 서비스 재시작 생략"
  fi

  echo "★ SVN 사용자 ${label} 작업 완료"
}
