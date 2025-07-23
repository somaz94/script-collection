#!/bin/bash

# 개선된 NFS 백업 스크립트
# - Elasticsearch 등 동적 파일 제외 처리
# - rsync 종료 코드 24 (파일 사라짐) 허용
# - 더 나은 에러 핸들링

# 설정
LOGFILE="/var/log/nfs-backup.log"
ERROR_LOG="/var/log/nfs-backup-error.log"
SOURCE="/mnt/nfs/"
DESTINATION="/mnt/nfs_backup/"
EXCLUDE_FILE="/etc/nfs-backup-exclude.txt"
MAX_LOG_SIZE=10485760  # 10MB

# 제외 파일 패턴 설정 (필요에 따라 수정 가능)
EXCLUDE_PATTERNS=(
    # Elasticsearch 동적 파일들 (가장 문제가 되는 것들만)
    "monitoring/elasticsearch*/indices/*/*/index/*.tmp"
    "monitoring/elasticsearch*/indices/*/*/index/*_Lucene90FieldsIndex*.tmp"
    
    # 임시 파일들
    "**/*.tmp"
    "**/*.swp"
    "**/.DS_Store"
    
    # 로그 파일들 (필요시 주석 해제)
    # "**/*.log"
    # "**/*.log.*"
    
    # 기타 동적 파일들
    "**/lost+found/"
    "**/.nfs*"
    
    # 사용자 정의 제외 패턴 (필요시 추가)
    # "projectm/logs/*.log"
    # "*/cache/*"
    # "*/tmp/*"
)

# 로그 파일 크기 체크 및 로테이션
rotate_log() {
    local log_file="$1"
    if [[ -f "$log_file" ]] && [[ $(stat -c%s "$log_file") -gt $MAX_LOG_SIZE ]]; then
        mv "$log_file" "${log_file}.old"
        touch "$log_file"
        chmod 644 "$log_file"
    fi
}

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

warn_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOGFILE"
}

# 제외 파일 생성
create_exclude_file() {
    if [[ ! -f "$EXCLUDE_FILE" ]]; then
        log "제외 파일 목록 생성: $EXCLUDE_FILE"
        
        # 제외 파일 헤더 생성
        cat > "$EXCLUDE_FILE" << 'EOF'
# NFS 백업 제외 파일 목록
# 이 파일은 자동으로 생성되었습니다.
# 필요에 따라 수동으로 편집할 수 있습니다.
# 
# 패턴 형식:
# - **/*.tmp : 모든 하위 디렉토리의 .tmp 파일
# - dir/subdir/* : 특정 디렉토리의 모든 파일
# - */logs/*.log : 임의 디렉토리의 logs 폴더 내 .log 파일

EOF
        
        # 제외 패턴 추가
        echo "# === 제외 패턴 ===" >> "$EXCLUDE_FILE"
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            # 주석이 아닌 패턴만 추가
            if [[ ! "$pattern" =~ ^[[:space:]]*# ]]; then
                echo "$pattern" >> "$EXCLUDE_FILE"
            fi
        done
        
        # 추가 설정 섹션
        cat >> "$EXCLUDE_FILE" << 'EOF'

# === 수동 추가 패턴 ===
# 아래에 추가로 제외할 패턴을 입력하세요:

EOF
        
        chmod 644 "$EXCLUDE_FILE"
        log "제외 파일 생성 완료: $(wc -l < "$EXCLUDE_FILE")개 패턴"
    else
        log "기존 제외 파일 사용: $EXCLUDE_FILE"
    fi
    
    # 제외 파일 내용 확인 (디버그용)
    local exclude_count=$(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^[[:space:]]*$' | wc -l)
    log "적용될 제외 패턴 수: $exclude_count개"
}

# rsync 종료 코드 해석
interpret_rsync_exit_code() {
    local exit_code=$1
    case $exit_code in
        0)
            log "rsync 완료: 성공"
            return 0
            ;;
        24)
            warn_log "rsync 완료: 일부 파일이 전송 중 사라짐 (정상적인 상황 - Elasticsearch 등)"
            return 0
            ;;
        23)
            error_log "rsync 실패: 일부 파일 전송 실패"
            return 1
            ;;
        12)
            error_log "rsync 실패: 프로토콜 데이터 스트림 오류"
            return 1
            ;;
        11)
            error_log "rsync 실패: 파일 I/O 오류"
            return 1
            ;;
        10)
            error_log "rsync 실패: 소켓 I/O 오류"
            return 1
            ;;
        *)
            error_log "rsync 실패: 알 수 없는 오류 (종료 코드: $exit_code)"
            return 1
            ;;
    esac
}

# 사전 체크 함수
pre_check() {
    log "=== 백업 사전 체크 시작 ==="
    
    # 소스 디렉토리 체크
    if [[ ! -d "$SOURCE" ]]; then
        error_log "소스 디렉토리가 존재하지 않습니다: $SOURCE"
        return 1
    fi
    
    # 대상 디렉토리 체크 (없으면 생성)
    if [[ ! -d "$DESTINATION" ]]; then
        log "대상 디렉토리 생성: $DESTINATION"
        mkdir -p "$DESTINATION"
    fi
    
    # 디스크 용량 체크
    local source_size=$(du -sb "$SOURCE" | cut -f1)
    local dest_available=$(df -B1 "$DESTINATION" | tail -1 | awk '{print $4}')
    
    log "소스 디렉토리 크기: $(numfmt --to=iec $source_size)"
    log "대상 디렉토리 사용 가능 공간: $(numfmt --to=iec $dest_available)"
    
    if [[ $source_size -gt $dest_available ]]; then
        error_log "대상 디렉토리 용량 부족! 필요: $(numfmt --to=iec $source_size), 사용가능: $(numfmt --to=iec $dest_available)"
        return 1
    fi
    
    # NFS 마운트 상태 체크
    if ! mountpoint -q "$SOURCE"; then
        error_log "NFS가 마운트되지 않았습니다: $SOURCE"
        return 1
    fi
    
    # 제외 파일 생성
    create_exclude_file
    
    log "사전 체크 완료 - 모든 조건 만족"
    return 0
}

# 백업 통계 수집
collect_stats() {
    local rsync_output="$1"
    
    # rsync 통계 추출
    local total_files=$(echo "$rsync_output" | grep -o "Number of files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local created_files=$(echo "$rsync_output" | grep -o "Number of created files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local deleted_files=$(echo "$rsync_output" | grep -o "Number of deleted files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local transferred_files=$(echo "$rsync_output" | grep -o "Number of regular files transferred: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local total_size=$(echo "$rsync_output" | grep -o "Total file size: [0-9.,]*[KMGT]*" | tail -1)
    local transferred_size=$(echo "$rsync_output" | grep -o "Total transferred file size: [0-9.,]*[KMGT]*" | tail -1)
    
    log "=== 백업 통계 ==="
    [[ -n "$total_files" ]] && log "전체 파일 수: $total_files"
    [[ -n "$created_files" ]] && log "생성된 파일 수: $created_files"
    [[ -n "$deleted_files" ]] && log "삭제된 파일 수: $deleted_files"
    [[ -n "$transferred_files" ]] && log "전송된 파일 수: $transferred_files"
    [[ -n "$total_size" ]] && log "전체 파일 크기: $total_size"
    [[ -n "$transferred_size" ]] && log "전송된 데이터 크기: $transferred_size"
}

# 메인 백업 함수
backup_main() {
    local start_time=$(date +%s)
    log "=== NFS 백업 시작 ==="
    
    # 로그 로테이션
    rotate_log "$LOGFILE"
    rotate_log "$ERROR_LOG"
    
    # 사전 체크
    if ! pre_check; then
        error_log "사전 체크 실패 - 백업 중단"
        exit 1
    fi
    
    # 임시 파일로 rsync 출력 저장
    local temp_output=$(mktemp)
    
    # 백업 실행
    log "rsync 백업 시작..."
    log "명령어: rsync -avh --progress --delete --stats --partial --inplace --exclude-from=\"$EXCLUDE_FILE\" \"$SOURCE\" \"$DESTINATION\""
    
    # rsync 실행
    rsync -avh --progress --delete --stats --partial --inplace --exclude-from="$EXCLUDE_FILE" "$SOURCE" "$DESTINATION" > "$temp_output" 2>&1
    local rsync_exit_code=$?
    
    # 종료 코드 해석
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if interpret_rsync_exit_code $rsync_exit_code; then
        log "백업 완료!"
        log "소요 시간: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
        
        # 통계 수집
        collect_stats "$(cat "$temp_output")"
        
        # 상세 로그 저장 (너무 길면 요약만)
        local output_size=$(wc -c < "$temp_output")
        if [[ $output_size -gt 1048576 ]]; then  # 1MB 이상이면
            log "=== rsync 출력 요약 (전체 출력이 너무 큼) ==="
            head -50 "$temp_output" >> "$LOGFILE"
            echo "... (중간 생략) ..." >> "$LOGFILE"
            tail -50 "$temp_output" >> "$LOGFILE"
        else
            log "=== rsync 상세 출력 ==="
            cat "$temp_output" >> "$LOGFILE"
        fi
        
        log "=== 백업 완료 ==="
        
    else
        error_log "백업 실패! (소요시간: ${duration}초, 종료코드: $rsync_exit_code)"
        error_log "=== rsync 에러 출력 ==="
        cat "$temp_output" >> "$ERROR_LOG"
        
        # 에러 내용도 메인 로그에 기록
        log "백업 실패 - 자세한 내용은 $ERROR_LOG 참조"
        
        rm -f "$temp_output"
        exit 1
    fi
    
    rm -f "$temp_output"
}

# 시스템 상태 로깅
log_system_status() {
    log "=== 시스템 상태 ==="
    log "호스트명: $(hostname)"
    log "현재 사용자: $(whoami)"
    log "시스템 로드: $(uptime | cut -d',' -f3-)"
    log "메모리 사용률: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    log "디스크 사용률 (소스): $(df -h "$SOURCE" | tail -1 | awk '{print $5}')"
    log "디스크 사용률 (대상): $(df -h "$DESTINATION" | tail -1 | awk '{print $5}')"
}

# 설정 관리 함수들
show_exclude_patterns() {
    log "=== 현재 제외 패턴 설정 ==="
    log "설정된 제외 패턴:"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ ! "$pattern" =~ ^[[:space:]]*# ]]; then
            log "  - $pattern"
        fi
    done
    
    if [[ -f "$EXCLUDE_FILE" ]]; then
        local manual_patterns=$(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^[[:space:]]*$' | grep -v -F "$(printf '%s\n' "${EXCLUDE_PATTERNS[@]}" | grep -v '^#')")
        if [[ -n "$manual_patterns" ]]; then
            log "수동 추가된 제외 패턴:"
            echo "$manual_patterns" | while read -r pattern; do
                log "  - $pattern"
            done
        fi
    fi
}

# 제외 파일 재생성 함수
regenerate_exclude_file() {
    log "제외 파일 재생성 중..."
    if [[ -f "$EXCLUDE_FILE" ]]; then
        mv "$EXCLUDE_FILE" "${EXCLUDE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log "기존 제외 파일 백업됨: ${EXCLUDE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    create_exclude_file
}

# 도움말 함수
show_help() {
    cat << 'EOF'
NFS 백업 스크립트 사용법:

기본 실행:
  ./nfs-backup.sh

옵션:
  --show-exclude    현재 제외 패턴 표시
  --regenerate      제외 파일 재생성
  --help           이 도움말 표시

설정 파일:
  제외 패턴: /etc/nfs-backup-exclude.txt
  로그 파일: /var/log/nfs-backup.log
  에러 로그: /var/log/nfs-backup-error.log

제외 패턴 수정 방법:
  1. 스크립트 내 EXCLUDE_PATTERNS 배열 수정
  2. /etc/nfs-backup-exclude.txt 파일 직접 편집
  3. --regenerate 옵션으로 제외 파일 재생성

EOF
}

# 스크립트 시작
main() {
    # 명령행 인수 처리
    case "${1:-}" in
        --show-exclude)
            show_exclude_patterns
            exit 0
            ;;
        --regenerate)
            regenerate_exclude_file
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            # 기본 실행
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "사용법: $0 [--show-exclude|--regenerate|--help]"
            exit 1
            ;;
    esac
    
    # 로그 파일 생성 및 권한 설정
    touch "$LOGFILE" "$ERROR_LOG"
    chmod 644 "$LOGFILE" "$ERROR_LOG"
    
    log_system_status
    backup_main
}

# 시그널 핸들러
cleanup() {
    log "백업 스크립트가 중단되었습니다 (시그널 수신)"
    exit 130
}

trap cleanup SIGINT SIGTERM

# 실행
main "$@"
