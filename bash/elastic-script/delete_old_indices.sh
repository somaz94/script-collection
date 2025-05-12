#!/bin/bash

###################
# Global Variables #
###################

# Elasticsearch Configuration
# ------------------------
# Authentication and connection settings for Elasticsearch
# Update these values with your Elasticsearch credentials
ELASTIC_USER="elastic"
ELASTIC_PASSWORD=""
ELASTIC_HOST=""

# Index Configuration
# ----------------
# Pattern to match indices for deletion
# Default matches all logstash indices
INDEX_PATTERN="logstash-"

# Retention Policy
# -------------
# Define retention periods for indices
# MIN_RETENTION_DAYS: Safety threshold to prevent accidental deletion
# RETENTION_DAYS: Default period to keep indices
MIN_RETENTION_DAYS=7
RETENTION_DAYS=30

# Date Format
# ---------
# Current date in Elasticsearch index format (YYYY.MM.DD)
TODAY=$(date +%Y.%m.%d)

# Help Documentation
# --------------
# Display usage information and examples
show_help() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Delete Elasticsearch indices older than specified retention period.

Options:
    -h, --help      Show this help message
    -d, --days DAYS Number of days to retain indices (default: 30, minimum: ${MIN_RETENTION_DAYS})

Examples:
    $(basename $0)         # Delete indices older than 30 days
    $(basename $0) -d 60   # Delete indices older than 60 days
    $(basename $0) --days 60   # Same as above

Note: Minimum retention period is ${MIN_RETENTION_DAYS} days for safety.
EOF
    exit 0
}

# Command Line Argument Processing
# ----------------------------
# Parse long format arguments (--help, --days)
for arg in "$@"; do
    case $arg in
        --help)
            show_help
            ;;
        --days=*)
            RETENTION_DAYS="${arg#*=}"
            shift
            ;;
        --days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
    esac
done

# Parse short format arguments (-h, -d)
OPTIND=1
while getopts "hd:" opt; do
    case $opt in
        h) show_help
        ;;
        d) RETENTION_DAYS="$OPTARG"
        ;;
        \?) echo "Invalid option -$OPTARG" >&2
            echo "Try '$(basename $0) --help' for more information." >&2
            exit 1
        ;;
    esac
done

# Input Validation
# -------------
# Ensure RETENTION_DAYS is a valid positive number
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: Days must be a positive number" >&2
    echo "Try '$(basename $0) --help' for more information." >&2
    exit 1
fi

# Ensure RETENTION_DAYS meets minimum requirement
if [ "$RETENTION_DAYS" -lt "$MIN_RETENTION_DAYS" ]; then
    echo "Error: Retention period cannot be less than ${MIN_RETENTION_DAYS} days" >&2
    echo "Try '$(basename $0) --help' for more information." >&2
    exit 1
fi

# Date Calculation
# -------------
# Calculate threshold date based on OS type
# Different date commands for macOS and Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS date command
    THRESHOLD_DATE=$(date -v-${RETENTION_DAYS}d +%Y.%m.%d)
else
    # Linux date command
    THRESHOLD_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y.%m.%d)
fi

# Index Retrieval
# -------------
# Get list of all matching indices from Elasticsearch
# Includes error handling for failed curl command
ALL_INDICES=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" "$ELASTIC_HOST/_cat/indices?v" | awk '{print $3}' | grep "^${INDEX_PATTERN}" || echo "")

# Validate Index List
# ----------------
# Check if indices were successfully retrieved
if [ -z "$ALL_INDICES" ]; then
    echo "Error: Failed to retrieve indices or no indices found"
    exit 1
fi

# Index Deletion Process
# -------------------
# Process each index and delete if older than threshold
for INDEX in $ALL_INDICES; do
    # Extract date from index name
    INDEX_DATE=$(echo "$INDEX" | sed -E 's/logstash-(.+)/\1/')
    
    # Validate index date format
    if [[ ! "$INDEX_DATE" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
        echo "Warning: Skipping $INDEX - Invalid date format"
        continue
    fi

    # Compare dates and delete if older than threshold
    if [[ "$INDEX_DATE" < "$THRESHOLD_DATE" ]]; then
        echo "Deleting index: $INDEX (older than $THRESHOLD_DATE)"
        RESPONSE=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" -X DELETE "$ELASTIC_HOST/$INDEX")
        if [[ $? -ne 0 ]]; then
            echo "Error deleting index $INDEX: $RESPONSE"
        fi
    else
        echo "Skipping index: $INDEX (newer than or equal to $THRESHOLD_DATE)"
    fi
done
