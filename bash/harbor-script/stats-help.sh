#!/bin/bash

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load modules
source "$SCRIPT_DIR/modules/harbor-config-en.sh"
source "$SCRIPT_DIR/modules/harbor-project-stats-en.sh"

# Initialize configuration
initialize_config

# Show statistics help
show_stats_help
