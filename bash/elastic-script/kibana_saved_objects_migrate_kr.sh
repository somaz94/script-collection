#!/bin/bash

###################
# 글로벌 변수 #
###################

# SOURCE Kibana (구 스택, monitoring ns)
SOURCE_HOST="https://kibana.example.com"
SOURCE_USER="elastic"
# Empty -> auto-fetch from k8s secret monitoring/elasticsearch-master-credentials
SOURCE_PASSWORD=""

# TARGET Kibana (신 스택, logging ns, ECK)
TARGET_HOST="https://kibana-eck.example.com"
TARGET_USER="elastic"
TARGET_PASSWORD="CHANGE_ME"

# Saved object types to migrate (comma-separated)
SAVED_OBJECT_TYPES="dashboard,visualization,search,index-pattern,lens,map,canvas-workpad,tag"

# NDJSON export/import file path
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
NDJSON_FILE="/tmp/kibana-saved-objects-${TIMESTAMP}.ndjson"

# Modes (set by CLI)
MODE=""
OVERWRITE=false
LIST_TARGET=false

# 도움말 출력 함수
show_help() {
  cat << EOF
사용법: $(basename "$0") [옵션]

설명:
  Kibana 인스턴스 간 Saved Objects (대시보드 / visualization / Data View /
  Lens / saved search / tag 등 정의) 를 이관합니다. 로그 문서(데이터) 는
  대상이 아닙니다 — Saved Objects 는 Kibana 내부 ".kibana_*" 시스템 인덱스에
  저장되는 설정/메타데이터입니다.

  기본 SOURCE : 구 Kibana (monitoring ns, ${SOURCE_HOST})
  기본 TARGET : 신 Kibana (logging ns, ${TARGET_HOST})

모드 (하나만 지정):
  -e, --export            SOURCE → NDJSON 파일 추출
  -I, --import            NDJSON 파일 → TARGET 으로 import
  -m, --migrate           SOURCE → NDJSON → TARGET 일괄 이관 (권장)
  -l, --list              SOURCE 의 Saved Object 타입별 개수 조회
      --list-target       TARGET 의 Saved Object 타입별 개수 조회

연결 옵션:
      --source URL               SOURCE Kibana host (기본: ${SOURCE_HOST})
      --source-user USER         SOURCE user (기본: ${SOURCE_USER})
      --source-password PW       SOURCE password
                                 (비어있으면 monitoring/elasticsearch-master-credentials
                                  secret 에서 자동 획득)
      --target URL               TARGET Kibana host (기본: ${TARGET_HOST})
      --target-user USER         TARGET user (기본: ${TARGET_USER})
      --target-password PW       TARGET password (기본: ${TARGET_PASSWORD})

데이터 옵션:
  -f, --file PATH         NDJSON 파일 경로
                          (기본: /tmp/kibana-saved-objects-YYYYMMDD-HHMMSS.ndjson)
  -t, --types LIST        쉼표로 구분된 타입 목록
                          (기본: ${SAVED_OBJECT_TYPES})
  -o, --overwrite         Import 시 충돌하는 객체를 덮어씀 (기본: skip)

기타:
  -h, --help              이 도움말 출력

예시:
  $(basename $0) --list                                       # 구 Kibana 에 뭐가 있는지 미리보기
  $(basename $0) --list-target                                # 신 Kibana 현황 확인
  $(basename $0) --migrate                                    # 구→신 일괄 이관 (권장)
  $(basename $0) --migrate --overwrite                        # 충돌 시 덮어쓰기
  $(basename $0) --export -f ./kibana-export.ndjson           # NDJSON 파일로 추출만
  $(basename $0) --import -f ./kibana-export.ndjson --overwrite  # 저장된 파일로 import만
  $(basename $0) --migrate --types "dashboard,lens,tag"       # 일부 타입만 이관

참고:
- SOURCE 가 HTTPS + self-signed cert 여도 -k 옵션으로 검증 생략합니다.
- Import 는 확인 프롬프트 후 수행됩니다.
- 권장 실행 순서: --list → --migrate → --list-target 으로 검증.
EOF
  exit 0
}

###################
# 공통 함수 #
###################

# Auto-fetch SOURCE password from Kubernetes secret if not set
fetch_source_password() {
    if [ -n "$SOURCE_PASSWORD" ]; then
        return 0
    fi
    echo "▸ SOURCE 암호 자동 획득 중 (monitoring/elasticsearch-master-credentials)..."
    SOURCE_PASSWORD=$(kubectl -n monitoring get secret elasticsearch-master-credentials \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
    if [ -z "$SOURCE_PASSWORD" ]; then
        echo "✗ SOURCE 암호 획득 실패. --source-password 로 직접 지정하세요." >&2
        exit 1
    fi
    echo "✓ SOURCE 암호 획득 완료"
    echo ""
}

# Build a JSON array literal from a comma-separated type list
build_types_json() {
    echo "$1" | awk -F',' '{
        for (i=1; i<=NF; i++) printf "\"%s\"%s", $i, (i==NF ? "" : ",")
    }'
}

# Pretty-print JSON response if python3 is available
pretty_json() {
    if command -v python3 >/dev/null 2>&1; then
        echo "$1" | python3 -m json.tool 2>/dev/null || echo "$1"
    else
        echo "$1"
    fi
}

###################
# 모드: List #
###################

do_list() {
    local host user pw label
    if [ "$LIST_TARGET" = true ]; then
        host="$TARGET_HOST"; user="$TARGET_USER"; pw="$TARGET_PASSWORD"
        label="TARGET ($TARGET_HOST)"
    else
        fetch_source_password
        host="$SOURCE_HOST"; user="$SOURCE_USER"; pw="$SOURCE_PASSWORD"
        label="SOURCE ($SOURCE_HOST)"
    fi

    echo "=========================================="
    echo "▸ Saved Objects 조회: $label"
    echo "=========================================="

    IFS=',' read -ra TYPES <<< "$SAVED_OBJECT_TYPES"
    local total=0
    local fail=0
    for t in "${TYPES[@]}"; do
        local resp count
        resp=$(curl -sk -u "$user:$pw" \
            -H 'kbn-xsrf: true' \
            "$host/api/saved_objects/_find?type=${t}&per_page=1&fields=id")
        count=$(echo "$resp" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
        if [ -z "$count" ]; then
            printf "  %-18s : (조회 실패)\n" "$t"
            fail=$((fail + 1))
            continue
        fi
        printf "  %-18s : %d\n" "$t" "$count"
        total=$((total + count))
    done
    echo "------------------------------------------"
    printf "  %-18s : %d\n" "TOTAL" "$total"
    echo "=========================================="
    if [ "$fail" -gt 0 ]; then
        echo "▲ ${fail}개 타입 조회 실패 — 인증/호스트 확인 필요" >&2
        exit 1
    fi
}

###################
# 모드: Export #
###################

do_export() {
    fetch_source_password

    echo "=========================================="
    echo "▸ Saved Objects Export"
    echo "=========================================="
    echo "SOURCE : $SOURCE_HOST"
    echo "타입   : $SAVED_OBJECT_TYPES"
    echo "파일   : $NDJSON_FILE"
    echo "=========================================="

    local types_json http_code
    types_json=$(build_types_json "$SAVED_OBJECT_TYPES")

    http_code=$(curl -sk -u "$SOURCE_USER:$SOURCE_PASSWORD" \
        -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
        -X POST "$SOURCE_HOST/api/saved_objects/_export" \
        -d "{\"type\":[${types_json}],\"includeReferencesDeep\":true}" \
        -o "$NDJSON_FILE" -w "%{http_code}")

    if [ "$http_code" != "200" ]; then
        echo "✗ Export 실패 (HTTP $http_code)" >&2
        if [ -s "$NDJSON_FILE" ]; then
            echo "응답 본문(앞 500B):" >&2
            head -c 500 "$NDJSON_FILE" >&2; echo >&2
        fi
        rm -f "$NDJSON_FILE"
        exit 1
    fi

    local lines
    lines=$(wc -l < "$NDJSON_FILE" | tr -d ' ')
    echo "✓ Export 완료: $NDJSON_FILE (${lines} 라인)"
    # Last NDJSON line is the summary: {"exportedCount":N,"missingRefCount":M,...}
    local summary
    summary=$(tail -1 "$NDJSON_FILE" 2>/dev/null | grep -o '"exportedCount":[0-9]*,"missingRefCount":[0-9]*' || true)
    if [ -n "$summary" ]; then
        echo "  요약: $summary"
    fi
}

###################
# 모드: Import #
###################

do_import() {
    if [ ! -f "$NDJSON_FILE" ]; then
        echo "✗ 파일을 찾을 수 없습니다: $NDJSON_FILE" >&2
        exit 1
    fi
    local lines
    lines=$(wc -l < "$NDJSON_FILE" | tr -d ' ')
    if [ "$lines" -eq 0 ]; then
        echo "✗ 파일이 비어있습니다: $NDJSON_FILE" >&2
        exit 1
    fi

    echo "=========================================="
    echo "▸ Saved Objects Import"
    echo "=========================================="
    echo "TARGET    : $TARGET_HOST"
    echo "파일      : $NDJSON_FILE (${lines} 라인)"
    if [ "$OVERWRITE" = true ]; then
        echo "충돌 처리 : overwrite (기존 객체 덮어쓰기)"
    else
        echo "충돌 처리 : skip (기본 — 기존 객체 유지)"
    fi
    echo "=========================================="
    echo ""
    read -p "Import 를 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "작업이 취소되었습니다."
        exit 0
    fi
    echo ""

    local url_params=""
    [ "$OVERWRITE" = true ] && url_params="?overwrite=true"

    local resp
    resp=$(curl -sk -u "$TARGET_USER:$TARGET_PASSWORD" \
        -H 'kbn-xsrf: true' \
        -X POST "$TARGET_HOST/api/saved_objects/_import${url_params}" \
        --form file=@"$NDJSON_FILE")

    echo "응답:"
    pretty_json "$resp"
    echo ""

    local success success_count error_count
    success=$(echo "$resp" | grep -o '"success":[a-z]*' | head -1 | cut -d: -f2)
    success_count=$(echo "$resp" | grep -o '"successCount":[0-9]*' | head -1 | cut -d: -f2)
    error_count=$(echo "$resp" | grep -o '"errors":\[' | wc -l | tr -d ' ')

    if [ "$success" = "true" ]; then
        echo "✓ Import 완료 (successCount=${success_count:-?})"
    else
        echo "✗ Import 중 에러 발생 — 위 응답의 errors[] 확인" >&2
        echo "  (기존 객체 충돌이면 --overwrite 재시도)" >&2
        exit 1
    fi
}

###################
# 모드: Migrate #
###################

do_migrate() {
    echo "=========================================="
    echo "▸ Saved Objects 일괄 이관 (SOURCE → TARGET)"
    echo "=========================================="
    echo "SOURCE : $SOURCE_HOST"
    echo "TARGET : $TARGET_HOST"
    echo "타입   : $SAVED_OBJECT_TYPES"
    echo "파일   : $NDJSON_FILE"
    echo "=========================================="
    echo ""

    do_export
    echo ""
    do_import
    echo ""
    echo "=========================================="
    echo "▸ 이관 종료 — TARGET 현황 검증 권장:"
    echo "    $(basename $0) --list-target"
    echo "=========================================="
}

###################
# 명령행 인수 파싱 #
###################

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -e|--export)
            MODE="export"; shift
            ;;
        -I|--import)
            MODE="import"; shift
            ;;
        -m|--migrate)
            MODE="migrate"; shift
            ;;
        -l|--list)
            MODE="list"; shift
            ;;
        --list-target)
            MODE="list"; LIST_TARGET=true; shift
            ;;
        --source)
            SOURCE_HOST="$2"; shift 2
            ;;
        --source-user)
            SOURCE_USER="$2"; shift 2
            ;;
        --source-password)
            SOURCE_PASSWORD="$2"; shift 2
            ;;
        --target)
            TARGET_HOST="$2"; shift 2
            ;;
        --target-user)
            TARGET_USER="$2"; shift 2
            ;;
        --target-password)
            TARGET_PASSWORD="$2"; shift 2
            ;;
        -f|--file)
            NDJSON_FILE="$2"; shift 2
            ;;
        -t|--types)
            SAVED_OBJECT_TYPES="$2"; shift 2
            ;;
        -o|--overwrite)
            OVERWRITE=true; shift
            ;;
        -*)
            echo "알 수 없는 옵션: $1" >&2
            echo "자세한 정보는 '$(basename $0) --help'를 참조하세요." >&2
            exit 1
            ;;
        *)
            echo "알 수 없는 인수: $1" >&2
            exit 1
            ;;
    esac
done

###################
# 디스패치 #
###################

if [ -z "$MODE" ]; then
    echo "오류: 모드를 지정해주세요." >&2
    echo "       --export / --import / --migrate / --list / --list-target 중 하나" >&2
    echo "자세한 정보는 '$(basename $0) --help'를 참조하세요." >&2
    exit 1
fi

case "$MODE" in
    export)  do_export ;;
    import)  do_import ;;
    migrate) do_migrate ;;
    list)    do_list ;;
esac
