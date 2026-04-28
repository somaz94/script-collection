# =============================================================================
# scripts/lib/prompts.sh — 공용 프롬프트/검증 유틸리티
# =============================================================================
# scripts/ 하위 bash 스크립트들이 공유하는 helper 함수 모음.
# - confirm_yes_no:    y/N 확인 프롬프트 (기본 N)
# - confirm_typed_word: 특정 단어를 정확히 입력해야 통과하는 확인 프롬프트
# - require_commands:  필수 명령어 일괄 존재 확인
# - format_human_size: 바이트 → 사람이 읽기 쉬운 크기 문자열
#
# 사용:
#   source "$(dirname "${BASH_SOURCE[0]}")/<상대경로>/lib/prompts.sh"
#
# colors.sh 와 함께 source 하면 색상 변수 (YELLOW/RED/NC 등) 가 사용됨.
# colors.sh 가 없어도 동작하도록 변수 미정의시 빈 문자열로 처리.
#
# 멱등성을 위해 가드 처리 — 한 스크립트에서 여러 모듈이 source 해도 안전.
# =============================================================================

[[ -n "${__SCRIPTS_LIB_PROMPTS_LOADED:-}" ]] && return 0
__SCRIPTS_LIB_PROMPTS_LOADED=1

# colors.sh 미로딩시 빈 문자열로 fallback
: "${YELLOW:=}" "${RED:=}" "${GREEN:=}" "${NC:=}"

# 사용자에게 y/N 확인을 요청. 기본값은 No.
# 인자: $1 = 표시할 메시지 (예: "정말 삭제하시겠습니까?")
# 반환: 0 = yes, 1 = no/취소
confirm_yes_no() {
  local message="${1:-계속하시겠습니까?}"
  local reply
  printf '%s%s (y/N): %s' "${YELLOW}" "${message}" "${NC}"
  read -r reply
  [[ "${reply}" =~ ^[Yy]$ ]]
}

# 특정 단어를 정확히 입력해야 통과하는 확인 프롬프트.
# 되돌릴 수 없는 위험 작업에서 사용 (예: 인덱스 삭제).
# 인자: $1 = 메시지, $2 = 입력해야 할 단어 (대소문자 구분)
# 반환: 0 = 일치, 1 = 불일치
confirm_typed_word() {
  local message="${1:-계속하려면 정확히 입력하세요}"
  local expected="${2:-CONFIRM}"
  local reply
  printf '%s%s (%s 입력): %s' "${YELLOW}" "${message}" "${expected}" "${NC}"
  read -r reply
  [[ "${reply}" == "${expected}" ]]
}

# 필수 명령어 일괄 존재 확인.
# 인자: 명령어 이름들을 가변 인자로
# 동작: 누락된 명령이 있으면 stderr 로 안내 후 exit 1
require_commands() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done

  if (( ${#missing[@]} > 0 )); then
    printf '%s✗ 다음 필수 명령어가 누락되었습니다:%s\n' "${RED}" "${NC}" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    return 1
  fi
}

# 바이트를 사람이 읽기 쉬운 단위로 변환 (B / KiB / MiB / GiB).
# 인자: $1 = 바이트 (정수)
# 출력: stdout 으로 변환된 문자열
format_human_size() {
  local bytes="${1:-0}"
  if (( bytes >= 1073741824 )); then
    printf '%.1f GiB\n' "$(echo "scale=2; ${bytes} / 1073741824" | bc)"
  elif (( bytes >= 1048576 )); then
    printf '%.1f MiB\n' "$(echo "scale=2; ${bytes} / 1048576" | bc)"
  elif (( bytes >= 1024 )); then
    printf '%.1f KiB\n' "$(echo "scale=2; ${bytes} / 1024" | bc)"
  else
    printf '%d B\n' "${bytes}"
  fi
}
