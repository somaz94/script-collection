#!/bin/bash

# 스크립트 디버깅을 활성화합니다.
set -x

# 필터링할 날짜 범위를 설정합니다.
START_DATE="2023-12-21T00:00:00Z"
END_DATE="2024-01-04T23:59:59Z"
PROJECT_ID="" # 프로젝트 ID
FILE_URL="" # 버킷 전체경로

# gcloud 명령어를 사용하여 로그를 추출합니다.
gcloud logging read "resource.type=http_load_balancer AND httpRequest.requestUrl=\"$FILE_URL\" AND (httpRequest.status=200 OR httpRequest.status=206) AND timestamp >= \"$START_DATE\" AND timestamp <= \"$END_DATE\"" --project $PROJECT_ID --format="json" > setup_logs.json

# jq를 사용하여 타임스탬프를 추출하고 정렬합니다.
jq '.[] | .timestamp' setup_logs.json | sort | uniq > setup_unique_timestamps.txt

# 일자별 다운로드 횟수를 카운트합니다.
declare -A daily_counts
declare -A last_timestamp_per_day
total_count=0

while IFS= read -r timestamp; do
    cleaned_timestamp=$(echo $timestamp | tr -d '"')
    current_timestamp=$(date -d "$cleaned_timestamp" +%s)
    date_only=$(date -d "$cleaned_timestamp" +%Y-%m-%d)

    # 일자별로 마지막 타임스탬프와의 차이 확인 (1분 이내)
    if [[ -z "${last_timestamp_per_day[$date_only]}" || $((current_timestamp - ${last_timestamp_per_day[$date_only]})) -gt 60 ]]; then
        ((daily_counts[$date_only]++))
        ((total_count++))
    fi

    last_timestamp_per_day[$date_only]=$current_timestamp
done < setup_unique_timestamps.txt

# 일자별 카운트 결과를 정렬하여 출력합니다.
for date in $(printf "%s\n" "${!daily_counts[@]}" | sort); do
    echo "$date: ${daily_counts[$date]}"
done

# 총 카운트 결과를 출력합니다.
echo "Total unique downloads: $total_count"
