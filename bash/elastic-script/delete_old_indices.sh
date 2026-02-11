#!/bin/bash

###################
# Global Variables #
###################

# Elasticsearch connection settings
ELASTIC_USER="elastic"
ELASTIC_PASSWORD=""
ELASTIC_HOST=""

# Index names to clean (array)
INDEX_NAMES=()

# Default indices to clean if none specified
# Example: DEFAULT_INDICES=("logstash-*" "filebeat-*" "metricbeat-*")
# Leave empty to require explicit index specification
DEFAULT_INDICES=()

# Retention period settings
# Minimum number of days to keep data
MIN_RETENTION_DAYS=7
# Default retention period in days
RETENTION_DAYS=90

# Force merge flag
FORCE_MERGE=false

# Delete index flag
DELETE_INDEX=false

# Date format
TODAY=$(date +%Y.%m.%d)

# Function to display help message
show_help() {
    cat << EOF
Usage: $(basename $0) [OPTIONS] [INDEX_NAMES...]

Delete old documents from specified Elasticsearch indices based on retention period.

Options:
  -h, --help              Show this help message
  -d, --days DAYS         Number of days to retain data (default: ${RETENTION_DAYS}, minimum: ${MIN_RETENTION_DAYS})
  -i, --indices INDICES   Comma-separated list of index names to clean
  -l, --list              List all available indices
  -s, --status            Show current status of all indices
  -f, --force-merge       Force merge indices after deletion to optimize disk space
  -c, --check-settings    Check index settings (total_fields.limit, etc.)
  -u, --update-limit NUM  Update total_fields.limit for specified indices
  --delete-index          Delete entire index (WARNING: irreversible!)

Examples:
  $(basename $0) index1 index2                       # Clean specified indices (${RETENTION_DAYS} days retention)
  $(basename $0) -d 60 index1 index2                 # Clean specified indices (60 days retention)
  $(basename $0) -i "index1,index2" -d 60            # Clean indices using comma-separated list
  $(basename $0) -l                                  # List all available indices
  $(basename $0) -s                                  # Show current status of all indices
  $(basename $0) -f index1                           # Clean and force merge index1
  $(basename $0) -d 60 -f index1 index2              # Clean with 60 days retention and force merge
  $(basename $0) -c index1                           # Check index1 settings
  $(basename $0) -c -i "index1,index2"               # Check multiple index settings
  $(basename $0) -u 2000 index1                      # Update total_fields.limit to 2000
  $(basename $0) -u 2000 -i "index1,index2"          # Update limit for multiple indices
  $(basename $0) --delete-index index1               # Delete entire index1
  $(basename $0) --delete-index -i "index1,index2"   # Delete multiple indices

Note: 
- You must specify at least one index to clean
- Minimum retention period is ${MIN_RETENTION_DAYS} days for safety
- Use -l option to list all available indices first
- --delete-index option completely removes the index and is irreversible!
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -i|--indices)
            IFS=',' read -ra INDEX_NAMES <<< "$2"
            shift 2
            ;;
        -l|--list)
            echo "Available indices:"
            curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" "$ELASTIC_HOST/_cat/indices?v" | awk 'NR>1 {print $3}' | sort
            exit 0
            ;;
        -s|--status)
            echo "Current status of all indices:"
            curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" "$ELASTIC_HOST/_cat/indices"
            exit 0
            ;;
        -f|--force-merge)
            FORCE_MERGE=true
            shift
            ;;
        -c|--check-settings)
            CHECK_SETTINGS=true
            shift
            ;;
        -u|--update-limit)
            UPDATE_LIMIT="$2"
            shift 2
            ;;
        --delete-index)
            DELETE_INDEX=true
            shift
            ;;
        -*)
            echo "Unknown option $1" >&2
            echo "Try '$(basename $0) --help' for more information." >&2
            exit 1
            ;;
        *)
            INDEX_NAMES+=("$1")
            shift
            ;;
    esac
done

# Index settings check mode
if [ "$CHECK_SETTINGS" = true ]; then
    if [ ${#INDEX_NAMES[@]} -eq 0 ] || [ -z "${INDEX_NAMES[0]}" ]; then
        echo "Error: No indices specified for settings check." >&2
        echo "Try '$(basename $0) --help' for more information." >&2
        exit 1
    fi

    echo "=========================================="
    echo "📋 Index Settings Check"
    echo "=========================================="
    for INDEX in "${INDEX_NAMES[@]}"; do
        echo ""
        echo "▶ Index: $INDEX"
        echo "------------------------------------------"

        SETTINGS=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
            "$ELASTIC_HOST/$INDEX/_settings?flat_settings=true&pretty")

        if echo "$SETTINGS" | grep -q '"error"'; then
            echo "✗ Index not found"
            echo "---"
            continue
        fi

        TOTAL_FIELDS=$(echo "$SETTINGS" | grep '"index.mapping.total_fields.limit"' | awk -F'"' '{print $4}')
        SHARDS=$(echo "$SETTINGS" | grep '"index.number_of_shards"' | awk -F'"' '{print $4}')
        REPLICAS=$(echo "$SETTINGS" | grep '"index.number_of_replicas"' | awk -F'"' '{print $4}')
        CREATION_DATE=$(echo "$SETTINGS" | grep '"index.creation_date"' | awk -F'"' '{print $4}')

        echo "  total_fields.limit : ${TOTAL_FIELDS:-1000 (default)}"
        echo "  number_of_shards   : ${SHARDS:-N/A}"
        echo "  number_of_replicas : ${REPLICAS:-N/A}"
        if [ -n "$CREATION_DATE" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                CREATED=$(date -r $((CREATION_DATE / 1000)) '+%Y-%m-%d %H:%M:%S')
            else
                CREATED=$(date -d @$((CREATION_DATE / 1000)) '+%Y-%m-%d %H:%M:%S')
            fi
            echo "  created_at         : $CREATED"
        fi

        FIELD_COUNT=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
            "$ELASTIC_HOST/$INDEX/_mapping?pretty" | grep '"type"' | wc -l | tr -d ' ')
        echo "  mapped fields      : ~${FIELD_COUNT}"
        echo "---"
    done
    echo ""
    echo "=========================================="
    exit 0
fi

# Index settings update mode
if [ -n "$UPDATE_LIMIT" ]; then
    if ! [[ "$UPDATE_LIMIT" =~ ^[0-9]+$ ]]; then
        echo "Error: total_fields.limit must be a positive integer" >&2
        exit 1
    fi

    if [ ${#INDEX_NAMES[@]} -eq 0 ] || [ -z "${INDEX_NAMES[0]}" ]; then
        echo "Error: No indices specified for settings update." >&2
        echo "Try '$(basename $0) --help' for more information." >&2
        exit 1
    fi

    echo "=========================================="
    echo "⚙️  Index Settings Update"
    echo "=========================================="
    echo "Target indices:"
    for INDEX in "${INDEX_NAMES[@]}"; do
        echo "  • $INDEX"
    done
    echo ""
    echo "Change: total_fields.limit → $UPDATE_LIMIT"
    echo "=========================================="
    echo ""
    read -p "Are you sure you want to update these settings? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi

    echo ""
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    for INDEX in "${INDEX_NAMES[@]}"; do
        echo "Updating settings: $INDEX"

        RESPONSE=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
            -X PUT "$ELASTIC_HOST/$INDEX/_settings" \
            -H "Content-Type: application/json" \
            -d "{\"index.mapping.total_fields.limit\": $UPDATE_LIMIT}")

        if echo "$RESPONSE" | grep -q '"acknowledged":true'; then
            echo "✓ $INDEX: total_fields.limit → $UPDATE_LIMIT updated"
            ((SUCCESS_COUNT++))
        else
            echo "✗ $INDEX: Failed to update settings"
            echo "  Response: $RESPONSE"
            ((FAIL_COUNT++))
        fi
        echo "---"
    done

    echo ""
    echo "=========================================="
    echo "Settings Update Complete"
    echo "=========================================="
    echo "Success: ${SUCCESS_COUNT}"
    echo "Failed: ${FAIL_COUNT}"
    echo "Total: ${#INDEX_NAMES[@]}"
    echo "=========================================="
    exit 0
fi

# Index deletion mode
if [ "$DELETE_INDEX" = true ]; then
    # Check if indices are specified
    if [ ${#INDEX_NAMES[@]} -eq 0 ] || [ -z "${INDEX_NAMES[0]}" ]; then
        echo "Error: No indices specified for deletion." >&2
        echo "Try '$(basename $0) --help' for more information." >&2
        exit 1
    fi
    
    # Display indices to be deleted
    echo "=========================================="
    echo "⚠️  INDEX DELETION OPERATION"
    echo "=========================================="
    echo "The following indices will be completely deleted:"
    echo ""
    for INDEX in "${INDEX_NAMES[@]}"; do
        echo "  • $INDEX"
    done
    echo ""
    echo "Total: ${#INDEX_NAMES[@]} index(es) will be deleted."
    echo "=========================================="
    echo ""
    echo "⚠️  WARNING: This operation is irreversible!"
    read -p "Are you sure you want to delete these indices? (Type 'DELETE' to confirm): " -r
    echo
    if [ "$REPLY" != "DELETE" ]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo ""
    echo "Starting index deletion..."
    echo ""
    
    # Deletion counters
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    
    # Loop through and delete specified indices
    for INDEX in "${INDEX_NAMES[@]}"; do
        echo "Deleting index: $INDEX"
        
        RESPONSE=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
            -X DELETE "$ELASTIC_HOST/$INDEX" \
            -H "Content-Type: application/json")
        
        # Check if deletion was successful
        if echo "$RESPONSE" | grep -q '"acknowledged":true'; then
            echo "✓ Successfully deleted index: $INDEX"
            ((SUCCESS_COUNT++))
        else
            echo "✗ Failed to delete index: $INDEX"
            echo "Response: $RESPONSE"
            ((FAIL_COUNT++))
        fi
        echo "---"
    done
    
    echo ""
    echo "=========================================="
    echo "Index Deletion Complete"
    echo "=========================================="
    echo "Success: ${SUCCESS_COUNT}"
    echo "Failed: ${FAIL_COUNT}"
    echo "Total: ${#INDEX_NAMES[@]}"
    echo "=========================================="
    
    exit 0
fi

# Document deletion mode (original functionality)

# Validate RETENTION_DAYS
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: Days must be a positive number" >&2
    echo "Try '$(basename $0) --help' for more information." >&2
    exit 1
fi

if [ "$RETENTION_DAYS" -lt "$MIN_RETENTION_DAYS" ]; then
    echo "Error: Retention period cannot be less than ${MIN_RETENTION_DAYS} days" >&2
    echo "Try '$(basename $0) --help' for more information." >&2
    exit 1
fi

# If no indices specified, use default indices
if [ ${#INDEX_NAMES[@]} -eq 0 ]; then
    INDEX_NAMES=("${DEFAULT_INDICES[@]}")
fi

# Check if indices are actually specified (not empty)
if [ ${#INDEX_NAMES[@]} -eq 0 ] || [ -z "${INDEX_NAMES[0]}" ]; then
    echo "Error: No indices specified for cleanup." >&2
    echo "Please specify indices using one of the following methods:" >&2
    echo "  1. As arguments: $(basename $0) index1 index2" >&2
    echo "  2. Using -i option: $(basename $0) -i \"index1,index2\"" >&2
    echo "  3. Set DEFAULT_INDICES in the script" >&2
    echo "" >&2
    echo "Use '$(basename $0) -l' to list all available indices." >&2
    echo "Use '$(basename $0) --help' for more information." >&2
    exit 1
fi

# Check OS type and use appropriate date command
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    THRESHOLD_DATE=$(date -v-${RETENTION_DAYS}d -u +"%Y-%m-%dT%H:%M:%S.000Z")
else
    # Linux
    THRESHOLD_DATE=$(date -d "-${RETENTION_DAYS} days" -u +"%Y-%m-%dT%H:%M:%S.000Z")
fi

# Loop through specified indices and delete old documents
echo "Indices to clean: ${INDEX_NAMES[@]}"
echo "Retention period: ${RETENTION_DAYS} days"
echo "Will delete documents older than: $THRESHOLD_DATE"
read -p "Are you sure you want to delete old documents from these indices? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

for INDEX in "${INDEX_NAMES[@]}"; do
    echo "Processing index: $INDEX"
    
    # Delete documents older than threshold date
    DELETE_QUERY='{
        "query": {
            "range": {
                "@timestamp": {
                    "lt": "'$THRESHOLD_DATE'"
                }
            }
        }
    }'
    
    echo "Deleting old documents from $INDEX..."
    RESPONSE=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
        -X POST "$ELASTIC_HOST/$INDEX/_delete_by_query" \
        -H "Content-Type: application/json" \
        -d "$DELETE_QUERY")
    
    # Check if deletion was successful and extract deleted count
    if echo "$RESPONSE" | grep -q '"deleted"'; then
        DELETED_COUNT=$(echo "$RESPONSE" | grep -o '"deleted":[0-9]*' | cut -d':' -f2)
        echo "✓ Successfully deleted $DELETED_COUNT documents from index: $INDEX"
    else
        echo "✗ Failed to delete documents from index: $INDEX"
        echo "Response: $RESPONSE"
    fi

    # Force merge if requested
    if [ "$FORCE_MERGE" = true ]; then
        echo "Force merging index: $INDEX..."
        MERGE_RESPONSE=$(curl -s -k -u "$ELASTIC_USER:$ELASTIC_PASSWORD" \
            -X POST "$ELASTIC_HOST/$INDEX/_forcemerge?only_expunge_deletes=true" \
            -H "Content-Type: application/json")
        
        # Check if force merge was successful
        if echo "$MERGE_RESPONSE" | grep -q '"successful"'; then
            echo "✓ Successfully force merged index: $INDEX"
        else
            echo "✗ Failed to force merge index: $INDEX"
            echo "Response: $MERGE_RESPONSE"
        fi
    fi
    echo "---"
done

echo "Document cleanup process completed."