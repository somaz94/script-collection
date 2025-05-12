#!/bin/bash

# Debug Mode
# ---------
# Enable command execution tracing for debugging
set -x

# Date Range Configuration
# ---------------------
# Define the time period for log analysis
# Format: ISO 8601 with UTC timezone
START_DATE="2023-12-21T00:00:00Z" 
END_DATE="2024-01-04T23:59:59Z"

# GCP Configuration
# --------------
# Set Google Cloud Platform project and file details
PROJECT_ID="" # GCP Project ID
FILE_URL="" # Full path to the file in GCS bucket

# Log Retrieval
# -----------
# Query Google Cloud Logging for HTTP load balancer logs
# Filter criteria:
# - Resource type: HTTP load balancer
# - URL: Matches specified file path
# - Status: 200 (OK) or 206 (Partial Content)
# - Time range: Between START_DATE and END_DATE
# Results are sorted chronologically
gcloud logging read "resource.type=http_load_balancer AND httpRequest.requestUrl=\"$FILE_URL\" AND (httpRequest.status=200 OR httpRequest.status=206) AND timestamp >= \"$START_DATE\" AND timestamp <= \"$END_DATE\"" --project $PROJECT_ID --format="json" > setup_logs.json

# Timestamp Processing
# -----------------
# Extract and sort unique timestamps from logs
# Uses jq to parse JSON and extract timestamp field
jq '.[] | .timestamp' setup_logs.json | sort | uniq > setup_unique_timestamps.txt

# Download Analysis
# --------------
# Count unique downloads by analyzing timestamps
# Downloads within 1 minute are considered duplicates
previous_timestamp=""
count=0
while IFS= read -r timestamp; do
    # Clean timestamp and convert to UTC
    cleaned_timestamp=$(echo $timestamp | tr -d '"' | sed 's/Z$/UTC/')
    current_timestamp=$(date -d "$cleaned_timestamp" +%s)
    
    # Count as unique if more than 1 minute from previous download
    if [[ -z "$previous_timestamp" || $((current_timestamp - previous_timestamp)) -gt 60 ]]; then
        ((count++))
    fi
    previous_timestamp=$current_timestamp
done < setup_unique_timestamps.txt

# Results Output
# ------------
# Display total number of unique downloads
echo "Unique downloads: $count"
