# =============================================================================
# scripts/lib/es-helpers.sh — Elasticsearch / Kibana 공용 헬퍼
# =============================================================================
# elasticsearch/ 하위 스크립트들이 공유하는 helper 함수 모음.
# - es_curl:                       curl 호출에 -s -k -u 자동 부여
# - es_pretty_json:                JSON 응답을 python3 으로 pretty-print
# - es_fetch_password_from_k8s:    kubectl 로 secret 의 비밀번호를 가져옴
#
# 사용:
#   source "$(dirname "${BASH_SOURCE[0]}")/<상대경로>/lib/es-helpers.sh"
#
# 멱등성을 위해 가드 처리 — 한 스크립트에서 여러 모듈이 source 해도 안전.
# =============================================================================

[[ -n "${__SCRIPTS_LIB_ES_HELPERS_LOADED:-}" ]] && return 0
__SCRIPTS_LIB_ES_HELPERS_LOADED=1

# es_curl USER PASS <curl_args...>
#   curl 호출에 표준 옵션 (`-s -k -u USER:PASS`) 을 자동 추가.
#   나머지 인자는 그대로 curl 에 전달.
#
# 사용 예시:
#   # ES API
#   es_curl "$EU" "$EP" "$ES_HOST/_cat/indices?v"
#   es_curl "$EU" "$EP" -X DELETE "$ES_HOST/$INDEX"
#
#   # Kibana API (kbn-xsrf 헤더는 호출 측에서 추가)
#   es_curl "$KU" "$KP" -H 'kbn-xsrf: true' "$KIBANA_HOST/api/saved_objects/_find"
es_curl() {
  local user="$1" pass="$2"
  shift 2
  curl -s -k -u "${user}:${pass}" "$@"
}

# es_pretty_json [json_string]
#   인자 또는 stdin 의 JSON 을 python3 -m json.tool 로 pretty-print.
#   python3 가 없거나 JSON 파싱 실패 시 원본을 그대로 출력 (fallback).
es_pretty_json() {
  if (( $# > 0 )); then
    if command -v python3 >/dev/null 2>&1; then
      printf '%s' "$1" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$1"
    else
      printf '%s\n' "$1"
    fi
  else
    if command -v python3 >/dev/null 2>&1; then
      python3 -m json.tool 2>/dev/null || cat
    else
      cat
    fi
  fi
}

# es_fetch_password_from_k8s NAMESPACE SECRET [KEY]
#   k8s secret 의 <KEY> (기본: password) 를 base64 decode 해서 stdout 으로 출력.
#   실패 시 stderr 로 에러 메시지 + 비0 종료.
#
# 사용 예시:
#   PASSWORD=$(es_fetch_password_from_k8s monitoring elasticsearch-master-credentials password) \
#     || exit 1
es_fetch_password_from_k8s() {
  local ns="$1" secret="$2" key="${3:-password}"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo "✗ kubectl 이 없어 secret 조회 불가" >&2
    return 1
  fi

  local val
  val=$(kubectl -n "${ns}" get secret "${secret}" \
    -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d 2>/dev/null)

  if [[ -z "${val}" ]]; then
    echo "✗ secret ${ns}/${secret} 의 ${key} 키를 가져오지 못했습니다" >&2
    return 1
  fi

  printf '%s' "${val}"
}
