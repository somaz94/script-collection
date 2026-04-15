#!/bin/bash

# Improved NFS backup script
# - Handles exclusion of dynamic files such as Elasticsearch
# - Allows rsync exit code 24 (files vanished during transfer)
# - Better error handling

# Configuration
LOGFILE="/var/log/nfs-backup.log"
ERROR_LOG="/var/log/nfs-backup-error.log"
SOURCE="/mnt/nfs/"
DESTINATION="/mnt/nfs_backup/"
EXCLUDE_FILE="/etc/nfs-backup-exclude.txt"
MAX_LOG_SIZE=10485760  # 10MB

# Exclude file pattern configuration (can be modified as needed)
EXCLUDE_PATTERNS=(
    # Elasticsearch dynamic files (only the most problematic ones)
    "monitoring/elasticsearch*/indices/*/*/index/*.tmp"
    "monitoring/elasticsearch*/indices/*/*/index/*_Lucene90FieldsIndex*.tmp"
    
    # Temporary files
    "**/*.tmp"
    "**/*.swp"
    "**/.DS_Store"
    
    # Log files (uncomment if needed)
    # "**/*.log"
    # "**/*.log.*"
    
    # Other dynamic files
    "**/lost+found/"
    "**/.nfs*"
    
    # User-defined exclude patterns (add as needed)
    # "example-project/logs/*.log"
    # "*/cache/*"
    # "*/tmp/*"
)

# Log file size check and rotation
rotate_log() {
    local log_file="$1"
    if [[ -f "$log_file" ]] && [[ $(stat -c%s "$log_file") -gt $MAX_LOG_SIZE ]]; then
        mv "$log_file" "${log_file}.old"
        touch "$log_file"
        chmod 644 "$log_file"
    fi
}

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

warn_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOGFILE"
}

# Create exclude file
create_exclude_file() {
    if [[ ! -f "$EXCLUDE_FILE" ]]; then
        log "Creating exclude file list: $EXCLUDE_FILE"
        
        # Create exclude file header
        cat > "$EXCLUDE_FILE" << 'EOF'
# NFS backup exclude file list
# This file was generated automatically.
# You can manually edit it as needed.
#
# Pattern format:
# - **/*.tmp : .tmp files in all subdirectories
# - dir/subdir/* : all files in a specific directory
# - */logs/*.log : .log files in the logs folder of any directory

EOF
        
        # Add exclude patterns
        echo "# === Exclude Patterns ===" >> "$EXCLUDE_FILE"
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            # Only add patterns that are not comments
            if [[ ! "$pattern" =~ ^[[:space:]]*# ]]; then
                echo "$pattern" >> "$EXCLUDE_FILE"
            fi
        done
        
        # Additional configuration section
        cat >> "$EXCLUDE_FILE" << 'EOF'

# === Manually Added Patterns ===
# Enter additional exclude patterns below:

EOF
        
        chmod 644 "$EXCLUDE_FILE"
        log "Exclude file creation complete: $(wc -l < "$EXCLUDE_FILE") patterns"
    else
        log "Using existing exclude file: $EXCLUDE_FILE"
    fi
    
    # Verify exclude file contents (for debugging)
    local exclude_count=$(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^[[:space:]]*$' | wc -l)
    log "Number of exclude patterns to apply: $exclude_count"
}

# Interpret rsync exit code
interpret_rsync_exit_code() {
    local exit_code=$1
    case $exit_code in
        0)
            log "rsync complete: success"
            return 0
            ;;
        24)
            warn_log "rsync complete: some files vanished during transfer (normal situation - e.g. Elasticsearch)"
            return 0
            ;;
        23)
            error_log "rsync failed: partial file transfer failure"
            return 1
            ;;
        12)
            error_log "rsync failed: protocol data stream error"
            return 1
            ;;
        11)
            error_log "rsync failed: file I/O error"
            return 1
            ;;
        10)
            error_log "rsync failed: socket I/O error"
            return 1
            ;;
        *)
            error_log "rsync failed: unknown error (exit code: $exit_code)"
            return 1
            ;;
    esac
}

# Pre-check function
pre_check() {
    log "=== Starting backup pre-check ==="
    
    # Check source directory
    if [[ ! -d "$SOURCE" ]]; then
        error_log "Source directory does not exist: $SOURCE"
        return 1
    fi
    
    # Check destination directory (create if it doesn't exist)
    if [[ ! -d "$DESTINATION" ]]; then
        log "Creating destination directory: $DESTINATION"
        mkdir -p "$DESTINATION"
    fi
    
    # Check disk space
    local source_size=$(du -sb "$SOURCE" | cut -f1)
    local dest_available=$(df -B1 "$DESTINATION" | tail -1 | awk '{print $4}')
    
    log "Source directory size: $(numfmt --to=iec $source_size)"
    log "Destination directory available space: $(numfmt --to=iec $dest_available)"
    
    if [[ $source_size -gt $dest_available ]]; then
        error_log "Insufficient space in destination directory! Required: $(numfmt --to=iec $source_size), Available: $(numfmt --to=iec $dest_available)"
        return 1
    fi
    
    # Check NFS mount status
    if ! mountpoint -q "$SOURCE"; then
        error_log "NFS is not mounted: $SOURCE"
        return 1
    fi
    
    # Create exclude file
    create_exclude_file
    
    log "Pre-check complete - all conditions met"
    return 0
}

# Collect backup statistics
collect_stats() {
    local rsync_output="$1"
    
    # Extract rsync statistics
    local total_files=$(echo "$rsync_output" | grep -o "Number of files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local created_files=$(echo "$rsync_output" | grep -o "Number of created files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local deleted_files=$(echo "$rsync_output" | grep -o "Number of deleted files: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local transferred_files=$(echo "$rsync_output" | grep -o "Number of regular files transferred: [0-9,]*" | grep -o "[0-9,]*" | tail -1)
    local total_size=$(echo "$rsync_output" | grep -o "Total file size: [0-9.,]*[KMGT]*" | tail -1)
    local transferred_size=$(echo "$rsync_output" | grep -o "Total transferred file size: [0-9.,]*[KMGT]*" | tail -1)
    
    log "=== Backup Statistics ==="
    [[ -n "$total_files" ]] && log "Total number of files: $total_files"
    [[ -n "$created_files" ]] && log "Number of created files: $created_files"
    [[ -n "$deleted_files" ]] && log "Number of deleted files: $deleted_files"
    [[ -n "$transferred_files" ]] && log "Number of transferred files: $transferred_files"
    [[ -n "$total_size" ]] && log "Total file size: $total_size"
    [[ -n "$transferred_size" ]] && log "Transferred data size: $transferred_size"
}

# Main backup function
backup_main() {
    local start_time=$(date +%s)
    log "=== NFS Backup Started ==="
    
    # Log rotation
    rotate_log "$LOGFILE"
    rotate_log "$ERROR_LOG"
    
    # Pre-check
    if ! pre_check; then
        error_log "Pre-check failed - backup aborted"
        exit 1
    fi
    
    # Save rsync output to temporary file
    local temp_output=$(mktemp)
    
    # Execute backup
    log "Starting rsync backup..."
    log "Command: rsync -avh --progress --delete --stats --partial --inplace --exclude-from=\"$EXCLUDE_FILE\" \"$SOURCE\" \"$DESTINATION\""
    
    # Execute rsync
    rsync -avh --progress --delete --stats --partial --inplace --exclude-from="$EXCLUDE_FILE" "$SOURCE" "$DESTINATION" > "$temp_output" 2>&1
    local rsync_exit_code=$?
    
    # Interpret exit code
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if interpret_rsync_exit_code $rsync_exit_code; then
        log "Backup complete!"
        log "Elapsed time: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
        
        # Collect statistics
        collect_stats "$(cat "$temp_output")"
        
        # Save detailed log (summary only if too long)
        local output_size=$(wc -c < "$temp_output")
        if [[ $output_size -gt 1048576 ]]; then  # If larger than 1MB
            log "=== rsync output summary (full output is too large) ==="
            head -50 "$temp_output" >> "$LOGFILE"
            echo "... (middle section omitted) ..." >> "$LOGFILE"
            tail -50 "$temp_output" >> "$LOGFILE"
        else
            log "=== rsync detailed output ==="
            cat "$temp_output" >> "$LOGFILE"
        fi
        
        log "=== Backup Complete ==="
        
    else
        error_log "Backup failed! (elapsed time: ${duration}s, exit code: $rsync_exit_code)"
        error_log "=== rsync error output ==="
        cat "$temp_output" >> "$ERROR_LOG"
        
        # Record error details in main log as well
        log "Backup failed - see $ERROR_LOG for details"
        
        rm -f "$temp_output"
        exit 1
    fi
    
    rm -f "$temp_output"
}

# System status logging
log_system_status() {
    log "=== System Status ==="
    log "Hostname: $(hostname)"
    log "Current user: $(whoami)"
    log "System load: $(uptime | cut -d',' -f3-)"
    log "Memory usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    log "Disk usage (source): $(df -h "$SOURCE" | tail -1 | awk '{print $5}')"
    log "Disk usage (destination): $(df -h "$DESTINATION" | tail -1 | awk '{print $5}')"
}

# Configuration management functions
show_exclude_patterns() {
    log "=== Current Exclude Pattern Settings ==="
    log "Configured exclude patterns:"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ ! "$pattern" =~ ^[[:space:]]*# ]]; then
            log "  - $pattern"
        fi
    done
    
    if [[ -f "$EXCLUDE_FILE" ]]; then
        local manual_patterns=$(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^[[:space:]]*$' | grep -v -F "$(printf '%s\n' "${EXCLUDE_PATTERNS[@]}" | grep -v '^#')")
        if [[ -n "$manual_patterns" ]]; then
            log "Manually added exclude patterns:"
            echo "$manual_patterns" | while read -r pattern; do
                log "  - $pattern"
            done
        fi
    fi
}

# Regenerate exclude file function
regenerate_exclude_file() {
    log "Regenerating exclude file..."
    if [[ -f "$EXCLUDE_FILE" ]]; then
        mv "$EXCLUDE_FILE" "${EXCLUDE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log "Existing exclude file backed up: ${EXCLUDE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    create_exclude_file
}

# Help function
show_help() {
    cat << 'EOF'
NFS Backup Script Usage:

Basic execution:
  ./nfs-backup.sh

Options:
  --show-exclude    Show current exclude patterns
  --regenerate      Regenerate exclude file
  --help           Show this help message

Configuration files:
  Exclude patterns: /etc/nfs-backup-exclude.txt
  Log file: /var/log/nfs-backup.log
  Error log: /var/log/nfs-backup-error.log

How to modify exclude patterns:
  1. Edit the EXCLUDE_PATTERNS array in the script
  2. Directly edit the /etc/nfs-backup-exclude.txt file
  3. Regenerate the exclude file with the --regenerate option

EOF
}

# Script start
main() {
    # Process command-line arguments
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
            # Default execution
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--show-exclude|--regenerate|--help]"
            exit 1
            ;;
    esac
    
    # Create log files and set permissions
    touch "$LOGFILE" "$ERROR_LOG"
    chmod 644 "$LOGFILE" "$ERROR_LOG"
    
    log_system_status
    backup_main
}

# Signal handler
cleanup() {
    log "Backup script was interrupted (signal received)"
    exit 130
}

trap cleanup SIGINT SIGTERM

# Execute
main "$@"
