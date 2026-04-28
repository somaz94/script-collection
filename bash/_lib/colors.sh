# =============================================================================
# scripts/lib/colors.sh — 공용 ANSI 색상 변수
# =============================================================================
# scripts/ 하위 bash 스크립트들이 공유하는 ANSI 색상 변수 모음.
# TTY 가 아니거나 NO_COLOR 환경변수가 설정된 경우 모든 변수를 빈 문자열로 둠.
#
# 사용:
#   source "$(dirname "${BASH_SOURCE[0]}")/<상대경로>/lib/colors.sh"
#
# 멱등성을 위해 가드 처리 — 한 스크립트에서 여러 모듈이 source 해도 안전.
# =============================================================================

[[ -n "${__SCRIPTS_LIB_COLORS_LOADED:-}" ]] && return 0
__SCRIPTS_LIB_COLORS_LOADED=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  NC=$'\033[0m'
else
  RED=
  GREEN=
  YELLOW=
  BLUE=
  CYAN=
  BOLD=
  DIM=
  NC=
fi
