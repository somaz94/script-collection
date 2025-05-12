#!/bin/bash
  
# Enable Debug Mode
# ----------------
# Print each command before execution for debugging purposes
set -x
  
# Environment Setup
# ---------------
# Set system paths and shell
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash
 
# Search Parameters
# --------------
# Define keywords for searching memory fault logs
# M: Main keyword (hardware)
# F: Secondary keyword (dimm - Dual In-line Memory Module)
M="hardware"
F="dimm"
 
# Log Analysis
# -----------
# Count occurrences of memory fault logs in system messages
# Combines both keywords for specific memory-related issues
C=`sudo cat /var/log/messages |grep -i $M |grep -i $F |wc -l`
 
# Email Configuration
# ----------------
# List of email recipients for notifications
# Add email addresses to receive memory fault alerts
MAILTO=(
"메일주소 추가"
)
 
# Alert Condition
# -------------
# If any memory faults are found (count >= 1):
# 1. Send email notification
# 2. Include site name in subject for identification
# 3. Send to all recipients in MAILTO array
if [ $C -ge 1 ]; then
  echo "Memory Fault log found." | \
  mail -s "[Site name] Memory Fault log found" \
  "${MAILTO[@]}"
fi
