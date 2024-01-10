#!/bin/bash

# 스크립트 디버깅을 활성화합니다.
set -x

# 필터링할 날짜 범위를 설정합니다.
START_DATE="2023-12-21T00:00:00Z" 
END_DATE="2024-01-04T23:59:59Z"
PROJECT_ID="" # 프로젝트 ID
FILE_URL="" # 버킷 전체경로

# gcloud 명령어를 사용하여 200 OK 및 206 Partial Content 로그를 필터링하고 추출합니다.
# 로그 데이터는 시간순으로 정렬됩니다.
gcloud logging read "resource.type=http_load_balancer AND httpRequest.requestUrl=\"$FILE_URL\" AND (httpRequest.status=200 OR httpRequest.status=206) AND timestamp >= \"$START_DATE\" AND timestamp <= \"$END_DATE\"" --project $PROJECT_ID --format="json" > setup_logs.json

# jq를 사용하여 타임스탬프를 추출하고 정렬합니다.
jq '.[] | .timestamp' setup_logs.json | sort | uniq > setup_unique_timestamps.txt

# 유니크한 다운로드 횟수를 계산합니다. 
# 각 타임스탬프를 확인하고, 1분 이내의 타임스탬프는 중복으로 간주하여 제거합니다.
previous_timestamp=""
count=0
while IFS= read -r timestamp; do
    # 따옴표를 제거하고 Z를 UTC로 변환합니다.
    cleaned_timestamp=$(echo $timestamp | tr -d '"' | sed 's/Z$/UTC/')
    current_timestamp=$(date -d "$cleaned_timestamp" +%s)
    if [[ -z "$previous_timestamp" || $((current_timestamp - previous_timestamp)) -gt 60 ]]; then
        ((count++))
    fi
    previous_timestamp=$current_timestamp
done < setup_unique_timestamps.txt

echo "Unique downloads: $count"
