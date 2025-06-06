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
gcloud logging read "resource.type=http_load_balancer AND httpRequest.requestUrl=\"$FILE_URL\" AND (httpRequest.status=200 OR httpRequest.status=206) AND timestamp >= \"$START_DATE\" AND timestamp <= \"$END_DATE\"" --project $PROJECT_ID --format="json" > setup_logs.json

# Timestamp Processing
# -----------------
# Extract and sort unique timestamps from logs
# Uses jq to parse JSON and extract timestamp field
jq '.[] | .timestamp' setup_logs.json | sort | uniq > setup_unique_timestamps.txt

# Download Analysis
# --------------
# Initialize counters for daily and total downloads
declare -A daily_counts
declare -A last_timestamp_per_day
total_count=0

# Process each timestamp
while IFS= read -r timestamp; do
    # Clean and convert timestamp
    cleaned_timestamp=$(echo $timestamp | tr -d '"')
    current_timestamp=$(date -d "$cleaned_timestamp" +%s)
    date_only=$(date -d "$cleaned_timestamp" +%Y-%m-%d)

    # Count unique downloads
    # Consider downloads within 1 minute as duplicates
    if [[ -z "${last_timestamp_per_day[$date_only]}" || $((current_timestamp - ${last_timestamp_per_day[$date_only]})) -gt 60 ]]; then
        ((daily_counts[$date_only]++))
        ((total_count++))
    fi

    # Update last timestamp for the day
    last_timestamp_per_day[$date_only]=$current_timestamp
done < setup_unique_timestamps.txt

# Results Output
# ------------
# Display daily download counts in chronological order
for date in $(printf "%s\n" "${!daily_counts[@]}" | sort); do
    echo "$date: ${daily_counts[$date]}"
done

# Display total unique downloads
echo "Total unique downloads: $total_count"
