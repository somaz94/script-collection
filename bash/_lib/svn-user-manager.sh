# =============================================================================
# scripts/lib/svn-user-manager.sh — SVN 사용자 생성/삭제 공용 로직
# =============================================================================
# Project M / SecondaryProject 양쪽 SVN 서버에 공유되는 사용자 관리 로직.
# 호출 측 (svn/*.sh) 은 다음 순서로 사용:
#
#   1) source "<상대경로>/lib/svn-user-manager.sh"
#   2) source "<상대경로>/svn/<서버>.conf"  (변수 정의)
#   3) USERNAMES=( ... ) 배열 정의
#   4) svn_run_main create   # 또는 delete
#
# 호출 측이 정의해야 하는 변수 (conf 파일에서 source 됨):
#   SVN_SERVER_IP, SVN_SERVER_USER, SVN_SERVER_PASSWORD,
#   DOCKER_CONTAINER, DOCKER_NEEDS_SUDO, DOCKER_BIN, ENABLE_CONTAINER_CHECK,
#   SVN_CONF_PATH, SVN_AUTHZ_FILE, SVN_PASSWD_FILE,
#   SVN_USER_PASSWORD, SVN_REPO_ROOT
#
# 멱등성을 위한 가드.
# =============================================================================

[[ -n "${__SCRIPTS_LIB_SVN_USER_MANAGER_LOADED:-}" ]] && return 0
__SCRIPTS_LIB_SVN_USER_MANAGER_LOADED=1

# -----------------------------------------------------------------------------
# 내부 helper — 원격에서 docker exec 를 실행할 때 prefix 를 구성
# -----------------------------------------------------------------------------
# 기준:
#   - DOCKER_NEEDS_SUDO=true  → "echo '$PASS' | sudo -S /usr/local/bin/docker"
#   - DOCKER_NEEDS_SUDO=false → "docker"
# 원격 SSH heredoc 안에서 그대로 interpolate 되어 사용됨.
_svn_docker_exec_prefix() {
  if [[ "${DOCKER_NEEDS_SUDO:-false}" == "true" ]]; then
    printf "echo '%s' | sudo -S %s" "${SVN_SERVER_PASSWORD}" "${DOCKER_BIN:-/usr/local/bin/docker}"
  else
    printf '%s' "${DOCKER_BIN:-docker}"
  fi
}

# -----------------------------------------------------------------------------
# 사전 검증 — sshpass 설치, SSH 연결, 컨테이너 가동 여부
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
#   반환: 0 = 신규 추가됨, 2 = 이미 존재 (변경 없음), 1 = 실패
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
#   반환: 0 = 삭제 성공, 2 = 존재하지 않음 (변경 없음), 1 = 실패
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
# svnserve 데몬 재시작 — 인증 파일 변경 후 적용을 위해 호출
# -----------------------------------------------------------------------------
svn_restart_service() {
  local DOCKER_PREFIX
  DOCKER_PREFIX="$(_svn_docker_exec_prefix)"

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
#   호출 측 wrapper 의 사용법을 출력. -h/--help 처리 시 사용.
# -----------------------------------------------------------------------------
svn_print_usage() {
  local MODE="${1:-create}"
  local label="추가"
  [[ "${MODE}" == "delete" ]] && label="삭제"

  cat <<USAGE
사용법: ${0##*/} [옵션]

  SVN 서버에 사용자를 ${label} 합니다.

  대상 사용자: 스크립트 상단의 USERNAMES 배열에 정의 (편집 후 실행)
  서버 설정:   같은 디렉토리의 *.conf 파일 (example-project.conf | secondary-project.conf)
  공용 로직:   scripts/lib/svn-user-manager.sh

옵션:
  -h, --help    이 도움말을 표시하고 종료

동작 요약:
  1) sshpass / SSH 연결 / Docker 컨테이너 가동 여부 사전 검증
  2) USERNAMES 배열을 순회하며 사용자 ${label} (authz / passwd 파일 수정)
  3) 변경이 발생한 경우에만 svnserve 데몬 재시작
USAGE
}

# -----------------------------------------------------------------------------
# svn_run_main MODE [args...]   (MODE = create | delete)
#   USERNAMES 배열을 순회하며 작업 수행 후, 변경이 있었던 경우만 svnserve 재시작.
#   추가 인자: -h / --help 만 지원
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

  # 추가 옵션 파싱 (현재는 -h/--help 만 지원)
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        svn_print_usage "${MODE}"
        exit 0
        ;;
      *)
        echo "✗ 알 수 없는 옵션: '$1' ('-h' 로 도움말 확인)" >&2
        return 1
        ;;
    esac
  done

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
  local USERNAME RESULT
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
