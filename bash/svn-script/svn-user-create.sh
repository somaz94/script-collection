#!/usr/bin/env bash
# Generic SVN user-management wrapper — synced from gitlab-project (sanitized).
# Edit the USERNAMES array below, then run:
#   ./svn-user-create.sh         # creates the listed users
#   ./svn-user-create.sh -h      # show help
#
# Server settings are inlined below; for multiple servers, copy this file and edit.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../_lib/svn-user-manager.sh"

# --- Inline server config (was example-project.conf in the source repo) -----------
SVN_SERVER_IP="192.0.2.10"
SVN_SERVER_USER="user"
SVN_SERVER_PASSWORD="CHANGE_ME"

# SVN Docker 컨테이너 정보
DOCKER_CONTAINER="project_m_svn"

# Docker 명령 실행 방식
# - DOCKER_NEEDS_SUDO=true 인 경우: `echo PASS | sudo -S DOCKER_BIN exec ...` 형태로 실행
# - false 인 경우: 원격 사용자 권한으로 직접 docker 명령 실행
DOCKER_NEEDS_SUDO="false"
DOCKER_BIN="docker"

# 컨테이너 가동 여부 검증 단계 활성화 (sudo 환경에서는 SSH 호출이 추가 password
# prompt 를 유발할 수 있어 false 권장)
ENABLE_CONTAINER_CHECK="true"

# SVN 설정 파일 경로 (컨테이너 내부)
SVN_CONF_PATH="/data/svn/conf"
SVN_AUTHZ_FILE="${SVN_CONF_PATH}/authz"
SVN_PASSWD_FILE="${SVN_CONF_PATH}/passwd"

# 신규 사용자 기본 비밀번호 (passwd 파일에 기록됨)
SVN_USER_PASSWORD="CHANGE_ME"

# svnserve 데몬 재시작 시 사용할 저장소 루트 경로
SVN_REPO_ROOT="/data/svn/"

# --- Target usernames — edit this array before running --------------------
USERNAMES=(
  example_user
)

svn_run_main create "$@"
