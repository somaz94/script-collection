#!/bin/bash

# Harbor Image Cleanup Script
# -------------------------
# This script cleans up old images from a specific Harbor project
# It keeps the most recent images and deletes older ones based on the specified count

# -- DEFINE GLOBAL VARIABLES --

# Default configuration values
DEFAULT_HARBOR_URL=""                            # Default Harbor registry URL
DEFAULT_HARBOR_PROTOCOL=""                       # Default protocol (http/https) for Harbor API
DEFAULT_HARBOR_USER=""                           # Default Harbor admin username
DEFAULT_HARBOR_PASS=""                           # Default Harbor admin password
DEFAULT_PROJECT_NAME=""                          # Default Harbor project name to clean up
DEFAULT_IMAGES_TO_KEEP=100                       # Default number of newest images to keep
DEFAULT_BATCH_SIZE=10                            # Default number of images to delete in parallel
DEFAULT_DEBUG=false                              # Default debug mode setting (verbose logging when true)
DEFAULT_DRY_RUN=false                            # Default dry run mode (no actual deletion when true)
DEFAULT_AUTO_CONFIRM=false                       # Default auto confirm setting (skip confirmation prompts when true)
DEFAULT_REPOSITORIES=("")                        # Default repositories to process within the project

# Colors for output
RED='\033[0;31m'                                 # Red color for error messages
GREEN='\033[0;32m'                               # Green color for success messages
YELLOW='\033[1;33m'                              # Yellow color for warnings and info messages
NC='\033[0m' # No Color                          # Reset terminal color

# -- FUNCTIONS --

# Print help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help              Show this help message and exit"
    echo "  -d, --debug             Enable debug mode"
    echo "  --dry-run               Don't actually delete images, just print what would be deleted"
    echo "  --auto-confirm          Skip confirmation and automatically delete images"
    echo "  -k, --keep N            Keep the newest N images (default: $DEFAULT_IMAGES_TO_KEEP)"
    echo "  -p, --project NAME      Harbor project name (default: $DEFAULT_PROJECT_NAME)"
    echo "  -r, --repo NAME         Repository name (e.g., somaz). Can be specified multiple times."
    echo "                          Use 'all' to process all repositories in the project."
    echo "  -b, --batch-size N      Number of images to delete in parallel (default: $DEFAULT_BATCH_SIZE)"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run -k 50 -p <project> -r <repo> -b 20"
    echo "  $0 -p <project> -r <repo1> -r <repo2> -k 20 --auto-confirm"
    echo "  $0 -p <project> -r all -k 50"
}

# Debug function
debug_print() {
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}DEBUG: $1${NC}"
    fi
}

# Function to validate if required commands exist
check_requirements() {
    local missing_commands=()
    
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        echo -e "${RED}Error: The following required commands are missing:${NC}"
        printf '%s\n' "${missing_commands[@]}"
        exit 1
    fi
}

# Function to validate configuration
validate_config() {
    if [ -z "$HARBOR_URL" ] || [ -z "$HARBOR_USER" ] || [ -z "$HARBOR_PASS" ] || [ -z "$PROJECT_NAME" ]; then
        echo -e "${RED}Error: Please fill in all configuration variables in the script${NC}"
        exit 1
    fi
    
    if [[ "$HARBOR_PROTOCOL" != "http" && "$HARBOR_PROTOCOL" != "https" ]]; then
        echo -e "${RED}Error: HARBOR_PROTOCOL must be either 'http' or 'https'${NC}"
        exit 1
    fi
}

# -- PARSE COMMAND LINE ARGUMENTS --
parse_arguments() {
    local print_help=false
    local repo_set=false
    
    # Initialize empty REPOSITORIES array
    REPOSITORIES=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -h|--help)
                print_help=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            -k|--keep)
                IMAGES_TO_KEEP="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -b|--batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            -r|--repo)
                REPOSITORIES+=("$2")
                repo_set=true
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                print_help=true
                shift
                ;;
        esac
    done
    
    # Display help if requested
    if [ "$print_help" = true ]; then
        show_help
        exit 0
    fi
    
    # Set default repositories if none specified
    if [ ${#REPOSITORIES[@]} -eq 0 ]; then
        REPOSITORIES=("${DEFAULT_REPOSITORIES[@]}")
    fi
}

# -- INITIALIZE CONFIGURATION --
initialize_config() {
    # Set default values if not specified
    HARBOR_URL="${HARBOR_URL:-$DEFAULT_HARBOR_URL}"
    HARBOR_PROTOCOL="${HARBOR_PROTOCOL:-$DEFAULT_HARBOR_PROTOCOL}"
    HARBOR_USER="${HARBOR_USER:-$DEFAULT_HARBOR_USER}"
    HARBOR_PASS="${HARBOR_PASS:-$DEFAULT_HARBOR_PASS}"
    PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}"
    IMAGES_TO_KEEP="${IMAGES_TO_KEEP:-$DEFAULT_IMAGES_TO_KEEP}"
    DEBUG="${DEBUG:-$DEFAULT_DEBUG}"
    AUTO_CONFIRM="${AUTO_CONFIRM:-$DEFAULT_AUTO_CONFIRM}"
    DRY_RUN="${DRY_RUN:-$DEFAULT_DRY_RUN}"
    BATCH_SIZE="${BATCH_SIZE:-$DEFAULT_BATCH_SIZE}"
    
    # Make sure BATCH_SIZE is at least 1
    if [ "$BATCH_SIZE" -lt 1 ]; then
        echo -e "${YELLOW}Invalid batch size $BATCH_SIZE, setting to 1${NC}"
        BATCH_SIZE=1
    fi
}

# Function to get authentication token
get_auth_token() {
    local token
    local url="${HARBOR_PROTOCOL}://${HARBOR_URL}/service/token"
    echo -e "${YELLOW}Attempting to get token from: $url${NC}"
    
    # Debug: Print the full curl command
    debug_print "Curl command: curl -s -k -X POST -H \"Content-Type: application/x-www-form-urlencoded\" -d \"principal=$HARBOR_USER&password=***\" \"$url\""
    
    local response
    response=$(curl -s -k -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "principal=$HARBOR_USER&password=$HARBOR_PASS" \
        "$url")
    
    # Debug: Print raw response
    debug_print "Raw response: $response"
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid JSON response from server${NC}"
        echo "$response"
        return 1
    fi
    
    token=$(echo "$response" | jq -r '.token')
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo -e "${RED}Error: Failed to get authentication token${NC}"
        echo -e "${RED}Response from server:${NC}"
        echo "$response"
        return 1
    fi
    
    echo "$token"
}

# Function to get repository list
get_repositories() {
    local url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories"
    local response

    # Move this debug output to debug_print instead of echo
    debug_print "Fetching repositories from: $url"

    debug_print "Curl command: curl -s -k -u \"$HARBOR_USER:***\" \"$url\""
    response=$(curl -s -k -u "$HARBOR_USER:$HARBOR_PASS" "$url")

    debug_print "Raw response: $response"

    # Handle case when response is not JSON
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid JSON response from server${NC}"
        echo "$response"
        return 1
    fi

    # Check for error message in response
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}Error from server: $error_msg${NC}"
        return 1
    fi

    # Extract repository names and remove project prefix
    # For example: "projectm/game/cache" -> "game/cache"
    echo "$response" | jq -r '.[].name' | sed "s|^$PROJECT_NAME/||" | grep -v "^$"
}

# Function to get image tags for a repository using the Harbor V2 API
get_image_tags() {
    local repo=$1
    local fullrepo="$repo"  # Full repository path
    local page_size=100  # Number of images per page
    local all_images=""
    local total_count=0
    
    echo -e "${YELLOW}Fetching images from repository: $fullrepo${NC}"
    
    # Repository may be in format "game/cache" - need proper encoding
    local repo_encoded=$(echo "$repo" | sed 's|/|%2F|g')
    local api_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_encoded/artifacts"
    
    echo -e "${YELLOW}Using Harbor V2 API: $api_url${NC}"
    
    # Get the total count first to know how many pages to fetch
    local total_items=0
    local count_response=$(curl -s -k -H "Accept: application/json" -u "$HARBOR_USER:$HARBOR_PASS" "$api_url?page=1&page_size=1")
    
    # Check if we get a valid response
    if ! echo "$count_response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid JSON response from server${NC}"
        # Try alternative encoding
        repo_encoded=$(echo "$repo" | sed 's|/|%252F|g')
        api_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_encoded/artifacts"
        echo -e "${YELLOW}Trying alternative encoding: $api_url${NC}"
        count_response=$(curl -s -k -H "Accept: application/json" -u "$HARBOR_USER:$HARBOR_PASS" "$api_url?page=1&page_size=1")
        
        if ! echo "$count_response" | jq . >/dev/null 2>&1; then
            echo -e "${RED}Error: Invalid JSON response from server with alternative encoding${NC}"
            # Try with project name prefix
            repo_encoded=$(echo "$repo" | sed 's|/|%2F|g')
            api_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$PROJECT_NAME%2F$repo_encoded/artifacts"
            echo -e "${YELLOW}Trying with project prefix: $api_url${NC}"
            count_response=$(curl -s -k -H "Accept: application/json" -u "$HARBOR_USER:$HARBOR_PASS" "$api_url?page=1&page_size=1")
            
            if ! echo "$count_response" | jq . >/dev/null 2>&1; then
                echo -e "${RED}Failed to get valid response from Harbor API${NC}"
                return
            fi
        fi
    fi
    
    # Try to get count from headers
    local header_info=$(curl -s -k -I -u "$HARBOR_USER:$HARBOR_PASS" "$api_url?page=1&page_size=1")
    if echo "$header_info" | grep -i "x-total-count" > /dev/null; then
        total_items=$(echo "$header_info" | grep -i "x-total-count" | awk '{print $2}' | tr -d '\r')
        echo -e "${GREEN}Total artifacts from header: $total_items${NC}"
    else
        # Fallback to counting in the response if we can
        if echo "$count_response" | jq -e '.metadata.total' >/dev/null 2>&1; then
            total_items=$(echo "$count_response" | jq -r '.metadata.total')
            echo -e "${GREEN}Total artifacts from metadata: $total_items${NC}"
        elif echo "$count_response" | jq -e '.total' >/dev/null 2>&1; then
            total_items=$(echo "$count_response" | jq -r '.total')
            echo -e "${GREEN}Total artifacts from total field: $total_items${NC}"
        fi
    fi
    
    # Determine number of pages needed
    if [ -z "$total_items" ] || [ "$total_items" = "null" ] || [ "$total_items" -eq 0 ]; then
        echo -e "${YELLOW}Could not determine total artifact count, using default max pages${NC}"
        total_items=500  # Reasonable default
    fi
    
    local pages_needed=$(( (total_items + page_size - 1) / page_size ))
    echo -e "${YELLOW}Need to fetch $pages_needed pages (max $page_size items per page)${NC}"
    
    # Limit to reasonable number to avoid excessive requests
    if [ "$pages_needed" -gt 10 ]; then
        echo -e "${YELLOW}Limiting to 10 pages to avoid excessive requests${NC}"
        pages_needed=10
    fi
    
    # Fetch artifacts page by page
    for ((page=1; page<=pages_needed; page++)); do
        echo -e "${YELLOW}Fetching page $page of $pages_needed${NC}"
        local page_url="$api_url?page=$page&page_size=$page_size&with_tag=true&with_label=false"
        
        # Get the current page of artifacts
        local response=$(curl -s -k -H "Accept: application/json" -u "$HARBOR_USER:$HARBOR_PASS" "$page_url")
        
        # Check if we got a valid response
        if ! echo "$response" | jq . >/dev/null 2>&1; then
            echo -e "${RED}Error: Invalid JSON response from server for page $page${NC}"
            continue
        fi
        
        # Check if response is an array
        local is_array=$(echo "$response" | jq 'if type=="array" then true else false end')
        
        # Extract artifacts from response
        local artifacts=""
        if [ "$is_array" = "true" ]; then
            artifacts="$response"
        else
            # Extract items array if response is an object
            if echo "$response" | jq -e '.items' >/dev/null 2>&1; then
                artifacts=$(echo "$response" | jq '.items')
            else
                echo -e "${RED}Error: No artifacts found in response${NC}"
                continue
            fi
        fi
        
        # Count artifacts in this page
        local page_count=$(echo "$artifacts" | jq '. | length')
        echo -e "${GREEN}Found $page_count artifacts in page $page${NC}"
        
        if [ "$page_count" -eq 0 ]; then
            echo -e "${YELLOW}No artifacts in page $page, stopping pagination${NC}"
            break
        fi
        
        # Process artifacts
        for ((i=0; i<page_count; i++)); do
            # Extract digest and push time
            local digest=$(echo "$artifacts" | jq -r ".[$i].digest")
            
            # Skip if digest is invalid
            if [ -z "$digest" ] || [ "$digest" = "null" ]; then
                continue
            fi
            
            # Validate digest format - must have sha256: prefix
            if ! [[ "$digest" == "sha256:"* ]]; then
                echo -e "${YELLOW}Skipping artifact with invalid digest format: $digest${NC}"
                continue
            fi
            
            # Get push time
            local push_time=""
            if echo "$artifacts" | jq -e ".[$i].push_time" >/dev/null 2>&1; then
                push_time=$(echo "$artifacts" | jq -r ".[$i].push_time")
            elif echo "$artifacts" | jq -e ".[$i].created" >/dev/null 2>&1; then
                push_time=$(echo "$artifacts" | jq -r ".[$i].created")
            else
                # Use a default timestamp 
                push_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            fi
            
            # Get tags
            local tags_count=0
            local tag_names=""
            
            if echo "$artifacts" | jq -e ".[$i].tags" >/dev/null 2>&1; then
                if echo "$artifacts" | jq -e ".[$i].tags | type == \"array\"" >/dev/null 2>&1; then
                    tags_count=$(echo "$artifacts" | jq -r ".[$i].tags | length")
                    if [ "$tags_count" -gt 0 ]; then
                        tag_names=$(echo "$artifacts" | jq -r ".[$i].tags[].name" | tr '\n' ',' | sed 's/,$//')
                    fi
                fi
            fi
            
            # Add to all_images
            all_images="${all_images}${digest}\t${push_time}\t${tags_count}\t${tag_names}\n"
            total_count=$((total_count + 1))
            
            # Debug output for first few artifacts
            if [ "$DEBUG" = true ] && [ "$i" -lt 3 ]; then
                echo -e "${YELLOW}Artifact $i - Digest: $digest, Time: $push_time, Tags: $tags_count, Names: $tag_names${NC}"
            fi
        done
    done
    
    # Return empty if no images found
    if [ -z "$all_images" ]; then
        echo -e "${YELLOW}No artifacts found for repository${NC}"
        return
    fi
    
    # Sort by push time (newest first)
    all_images=$(echo -e "$all_images" | sort -t $'\t' -k2,2r)
    echo -e "${GREEN}Total artifacts retrieved: $total_count${NC}"
    
    # Return the result
    echo -e "$all_images"
}

# Function to delete an image
delete_image() {
    local repo=$1
    local digest=$2
    
    # Validate digest format before proceeding
    if [ -z "$digest" ]; then
        echo -e "${RED}Error: Empty digest, skipping deletion${NC}"
        return 1
    fi
    
    # Enhanced validation: Ensure digest has proper format
    if ! [[ "$digest" == "sha256:"* ]]; then
        echo -e "${RED}Error: Invalid digest format: $digest, missing sha256: prefix, skipping deletion${NC}"
        return 1
    fi
    
    # Extract just the digest part (in case there's trailing data)
    digest=$(echo "$digest" | awk '{print $1}' | tr -d '\r' | tr -d '\n')
    
    # Debug mode
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}Deleting image with digest: $digest from repository: $PROJECT_NAME/$repo${NC}"
    fi
    
    # If in DRY_RUN mode, don't actually delete
    if [ "$DRY_RUN" = true ]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${YELLOW}DRY RUN MODE: Would delete image with digest: $digest (no actual deletion)${NC}"
        fi
        return 0
    fi
    
    # Encode the repository name for URL
    local repo_encoded=$(echo "$repo" | sed 's|/|%2F|g')
    
    # Try a direct API call with proper headers and specific method
    local delete_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_encoded/artifacts/$digest"
    
    # 디버그 모드일 때만 자세한 로그 출력
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}Attempting deletion with URL: $delete_url${NC}"
        echo -e "${YELLOW}Using basic authentication${NC}"
    fi
    
    # Debug: Show curl command
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}Debug: curl -v -k -X DELETE -u \"$HARBOR_USER:***\" $delete_url${NC}"
    fi
    
    # Execute the delete request
    local http_code
    
    http_code=$(curl -s -k -X DELETE \
        -u "$HARBOR_USER:$HARBOR_PASS" \
        -w "%{http_code}" -o /dev/null \
        "$delete_url")
    
    # Debug mode
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    fi
    
    # Check if deletion was successful
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        # Debug mode
        if [ "$DEBUG" = true ]; then
            echo -e "${GREEN}Successfully deleted image with digest: $digest (HTTP Status: $http_code)${NC}"
        fi
        return 0
    elif [ "$http_code" -eq 404 ]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${YELLOW}Artifact not found: $digest (HTTP Status: 404)${NC}"
        fi
        # Return success if artifact is already gone
        return 0
    else
        if [ "$DEBUG" = true ]; then
            echo -e "${RED}Failed to delete image: $digest (HTTP Status: $http_code)${NC}"
            
            # Try an alternative approach - check if registry v2 API works better
            echo -e "${YELLOW}Trying registry v2 API instead...${NC}"
            
            # Registry v2 API DELETE endpoint
            local registry_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/v2/$PROJECT_NAME/$repo/manifests/$digest"
            echo -e "${YELLOW}Using registry v2 API: $registry_url${NC}"
            
            local registry_code=$(curl -s -k -X DELETE \
                -u "$HARBOR_USER:$HARBOR_PASS" \
                -w "%{http_code}" -o /dev/null \
                "$registry_url")
            
            echo -e "${YELLOW}Registry API Status: $registry_code${NC}"
            
            if [ "$registry_code" -ge 200 ] && [ "$registry_code" -lt 300 ] || [ "$registry_code" -eq 404 ]; then
                echo -e "${GREEN}Successfully deleted image with registry v2 API: $digest (HTTP Status: $registry_code)${NC}"
                return 0
            else
                echo -e "${RED}Failed to delete with registry v2 API: $digest (HTTP Status: $registry_code)${NC}"
                return 1
            fi
        else
            # 디버그 모드가 아닐 때는 간단한 에러 메시지만
            echo -e "${RED}Failed to delete image: $digest${NC}"
            return 1
        fi
    fi
}

# Function to ask user for confirmation
confirm_deletion() {
    local repo=$1
    local total_images=$2
    local keep_count=$3
    local delete_count=$4
    
    echo -e "\n${YELLOW}============== DELETION CONFIRMATION ==============${NC}"
    echo -e "${YELLOW}Repository: $PROJECT_NAME/$repo${NC}"
    echo -e "${YELLOW}Total images: $total_images${NC}"
    echo -e "${YELLOW}Images to keep: $keep_count (newest images)${NC}"
    echo -e "${YELLOW}Images to delete: $delete_count (oldest images)${NC}"
    echo -e "${YELLOW}=====================================${NC}"
    
    # Check if running in dry run mode
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE: Would delete $delete_count images (not actually deleting)${NC}"
        return 1
    fi
    
    # Automatic confirmation
    if [ "$AUTO_CONFIRM" = true ]; then
        echo -e "${YELLOW}Auto-confirmation enabled. Proceeding with deletion...${NC}"
        return 0
    fi
    
    # Manual confirmation with timeout
    local answer
    echo -e "${YELLOW}Do you want to delete these images? (y/n) [Default: n in 10s]:${NC}"
    read -t 10 answer </dev/tty
    echo ""
    
    # Process the answer
    case "$answer" in
        [Yy]* ) 
            echo -e "${GREEN}Confirmed. Proceeding with deletion...${NC}"
            return 0
            ;;
        * ) 
            echo -e "${YELLOW}Deletion cancelled or no input received.${NC}"
            return 1
            ;;
    esac
}

# Function to list available repositories
list_repositories() {
    echo -e "\n${GREEN}Available repositories in project $PROJECT_NAME:${NC}"
    
    local repos=$(get_repositories)
    if [ -z "$repos" ] || [ "$repos" = "[]" ]; then
        echo -e "${YELLOW}No repositories found in project $PROJECT_NAME${NC}"
        return 1
    fi
    
    # Print the repository names
    echo "$repos" | while read -r repo; do
        [ -z "$repo" ] && continue
        echo "- $repo"
    done
    
    # Return repository names for programmatic use
    echo "$repos"
    return 0
}

# Function to check Harbor API version
check_harbor_api() {
    echo -e "${YELLOW}Checking Harbor API version...${NC}"
    
    # Send GET request to Harbor API
    local version_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/systeminfo"
    
    # Debug: Show URL
    debug_print "Requesting system info from: $version_url"
    
    # Add Accept header and increased timeout
    local version_response=$(curl -s -k -m 30 \
        -H "Accept: application/json" \
        -u "$HARBOR_USER:$HARBOR_PASS" "$version_url")
    
    # Debug: Show response
    debug_print "Response: $version_response"
    
    # Check if response is JSON
    if ! echo "$version_response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid JSON response from server when checking API version${NC}"
        echo "$version_response"
        return 1
    fi
    
    # Extract version info
    local harbor_version=$(echo "$version_response" | jq -r '.harbor_version' 2>/dev/null)
    if [ -n "$harbor_version" ] && [ "$harbor_version" != "null" ]; then
        echo -e "${GREEN}Harbor version: $harbor_version${NC}"
    else
        echo -e "${YELLOW}Harbor version not found in response${NC}"
    fi
    
    # Check API version
    if echo "$version_response" | jq -e '.api_version' >/dev/null 2>&1; then
        local api_version=$(echo "$version_response" | jq -r '.api_version')
        echo -e "${GREEN}API version: $api_version${NC}"
    else
        echo -e "${YELLOW}API version not found in response${NC}"
    fi
    
    return 0
}

# Function to list all repositories
list_all_repositories() {
    echo -e "${YELLOW}Listing all repositories in project: $PROJECT_NAME${NC}"
    
    local repos=$(get_repositories)
    if [ -z "$repos" ]; then
        echo -e "${RED}Error: Failed to get repository list${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Found $(echo "$repos" | grep -v "^$" | wc -l | tr -d ' ') repositories${NC}"
    
    # Print repository list
    echo -e "${YELLOW}Available repositories:${NC}"
    echo "$repos"
    
    return 0
}

# Function to get repository information with artifact counts
get_repository_info() {
    local url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories?page=1&page_size=100"
    local response
    
    echo -e "${YELLOW}Fetching repository information from: $url${NC}"
    
    # Output diagnostic information
    echo -e "${YELLOW}==== DIAGNOSTIC INFORMATION ====${NC}"
    echo -e "${YELLOW}Harbor URL: $HARBOR_URL${NC}"
    echo -e "${YELLOW}Project: $PROJECT_NAME${NC}"
    echo -e "${YELLOW}Protocol: $HARBOR_PROTOCOL${NC}"
    
    # Try a simple HEAD request first
    echo -e "${YELLOW}Testing connection with HEAD request...${NC}"
    local head_status=$(curl -s -k -o /dev/null -w "%{http_code}" -I -u "$HARBOR_USER:$HARBOR_PASS" "$url")
    echo -e "${YELLOW}HEAD request status: $head_status${NC}"
    
    # Use verbose curl for diagnostics
    echo -e "${YELLOW}Detailed connection information:${NC}"
    curl -v -k -o /dev/null -u "$HARBOR_USER:$HARBOR_PASS" "$url" 2>&1 | grep -E "Connected to|< HTTP|> GET"
    echo -e "${YELLOW}==== END DIAGNOSTIC INFORMATION ====${NC}"
    
    # Add Accept header and increased timeout
    response=$(curl -s -k -m 30 \
        -H "Accept: application/json" \
        -u "$HARBOR_USER:$HARBOR_PASS" "$url")
    
    # Debug: Print raw response
    debug_print "Raw response: $response"
    
    # Validate JSON response
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid JSON response from server${NC}"
        echo "$response"
        
        # Try adding a timeout and different accept header
        echo -e "${YELLOW}Retrying with explicit accept header and timeout...${NC}"
        response=$(curl -s -k -m 30 \
            -H "Accept: application/json" \
            -u "$HARBOR_USER:$HARBOR_PASS" "$url")
            
        if ! echo "$response" | jq . >/dev/null 2>&1; then
            echo -e "${RED}Failed to get valid JSON response after retry${NC}"
            # Return empty JSON array as fallback
            echo "[]"
            return 1
        fi
    fi
    
    # Check for error message in response
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}Error from server: $error_msg${NC}"
        # Return empty JSON array as fallback
        echo "[]"
        return 1
    fi
    
    # Ensure we have valid JSON array
    if ! echo "$response" | jq 'if type=="array" then true else false end' | grep -q true; then
        echo -e "${YELLOW}Response is not a JSON array, attempting to extract items...${NC}"
        if echo "$response" | jq -e '.items' >/dev/null 2>&1; then
            response=$(echo "$response" | jq '.items')
        else
            echo -e "${RED}Cannot extract repository data from response${NC}"
            # Return empty JSON array as fallback
            echo "[]"
            return 1
        fi
    fi
    
    # Return the full response
    echo "$response"
}

# Function to extract artifact count for a repository
get_artifact_count() {
    local repo=$1
    local repo_info=$2
    
    # First check if repo_info is empty or invalid
    if [ -z "$repo_info" ] || [ "$repo_info" = "[]" ]; then
        echo -e "${RED}No repository information available${NC}"
        echo "0"
        return 1
    fi
    
    # First try exact match with projectm/repo format
    local full_repo_path="$PROJECT_NAME/$repo"
    local count
    
    echo -e "${YELLOW}Looking for artifact count for repository: $repo (full path: $full_repo_path)${NC}"
    
    # Use grep to pre-check if the repo name exists in the JSON to avoid jq errors
    if echo "$repo_info" | grep -q "\"$full_repo_path\""; then
        count=$(echo "$repo_info" | jq -r ".[] | select(.name==\"$full_repo_path\") | .artifact_count")
        
        if [ -n "$count" ] && [ "$count" != "null" ]; then
            echo "$count"
            return 0
        fi
    fi
    
    # Try alternative formats if the exact match failed
    echo -e "${YELLOW}No exact match for repository $repo, trying alternatives...${NC}"
    
    # Extract all repository names for debugging
    debug_print "Available repositories in response:"
    debug_print "$(echo "$repo_info" | jq -r '.[].name')"
    
    # List repositories and match by substring
    local repositories=$(echo "$repo_info" | jq -r '.[].name')
    
    # Handle empty or invalid repositories list
    if [ -z "$repositories" ]; then
        echo -e "${RED}No repositories found in API response${NC}"
        echo "0"
        return 1
    fi
    
    # Try different matching approaches
    for r in $repositories; do
        # Skip empty lines
        [ -z "$r" ] && continue
        
        # Check if repository name ends with our repo path
        if [[ "$r" == *"/$repo"* ]] || [[ "$r" == "$repo" ]]; then
            echo -e "${GREEN}Found matching repository: $r${NC}"
            count=$(echo "$repo_info" | jq -r ".[] | select(.name==\"$r\") | .artifact_count")
            
            # Check if count is a valid number
            if [[ "$count" =~ ^[0-9]+$ ]]; then
                echo "$count"
                return 0
            else
                echo -e "${YELLOW}Invalid artifact count for $r: $count${NC}"
            fi
        fi
    done
    
    # Last resort: try a direct API call to the repository to check if it exists
    local repo_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$repo"
    echo -e "${YELLOW}Trying direct repository check: $repo_url${NC}"
    
    local repo_response=$(curl -s -k -u "$HARBOR_USER:$HARBOR_PASS" "$repo_url")
    
    if echo "$repo_response" | jq . >/dev/null 2>&1; then
        if echo "$repo_response" | jq -e '.artifact_count' >/dev/null 2>&1; then
            count=$(echo "$repo_response" | jq -r '.artifact_count')
            echo -e "${GREEN}Found artifact count via direct API call: $count${NC}"
            echo "$count"
            return 0
        fi
    fi
    
    echo -e "${RED}Could not find artifact count for repository: $repo${NC}"
    echo "0"
    return 1
}

# Function to get repository info with artifact counts - Direct API approach
get_direct_repository_info() {
    local repo=$1
    echo -e "${YELLOW}Getting direct repository info for: $repo${NC}"
    
    # Try different URL formats for the repository
    local encoded_repo=$(echo "$repo" | sed 's|/|%2F|g')
    local double_encoded_repo=$(echo "$repo" | sed 's|/|%252F|g')
    
    echo -e "${YELLOW}==== REPOSITORY ENCODING ====${NC}"
    echo -e "${YELLOW}Original repo name: $repo${NC}"
    echo -e "${YELLOW}URL-encoded repo name: $encoded_repo${NC}"
    echo -e "${YELLOW}Double-encoded repo name: $double_encoded_repo${NC}"
    echo -e "${YELLOW}=============================${NC}"
    
    local url_templates=(
        # Try with project name prefix
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$PROJECT_NAME%2F$encoded_repo"
        # Try direct path
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$encoded_repo"
        # Try with double encoding
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$double_encoded_repo"
        # Try with project name prefix
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$PROJECT_NAME%2F$repo"
        # Try direct path without encoding
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$repo"
    )
    
    for url in "${url_templates[@]}"; do
        echo -e "${YELLOW}Trying repository URL: $url${NC}"
        
        # Check if URL is reachable with GET request instead of HEAD
        local head_status=$(curl -s -k -o /dev/null -w "%{http_code}" -X GET -u "$HARBOR_USER:$HARBOR_PASS" "$url")
        echo -e "${YELLOW}GET status: $head_status${NC}"
        
        if [ "$head_status" -ge 200 ] && [ "$head_status" -lt 300 ]; then
            echo -e "${GREEN}URL is accessible${NC}"
            
            # Add Accept header and increased timeout
            local response=$(curl -s -k -m 30 \
                -H "Accept: application/json" \
                -u "$HARBOR_USER:$HARBOR_PASS" "$url")
            
            # Debug response
            echo -e "${YELLOW}Response content:${NC}"
            echo "$response" | head -20
            
            # Check if response is valid JSON
            if echo "$response" | jq . >/dev/null 2>&1; then
                # Try to extract artifact count directly
                if echo "$response" | jq -e '.artifact_count' >/dev/null 2>&1; then
                    local count=$(echo "$response" | jq -r '.artifact_count')
                    echo -e "${GREEN}Found artifact count: $count${NC}"
                    echo "$count"
                    return 0
                fi
                
                # If we got valid JSON but no artifact_count, check what we have
                echo -e "${YELLOW}No artifact_count field in response, available fields:${NC}"
                echo "$response" | jq 'keys'
            else
                echo -e "${RED}Invalid JSON response${NC}"
            fi
        else
            echo -e "${RED}URL not accessible: $head_status${NC}"
        fi
    done
    
    # Try a different approach using the artifacts endpoint with count
    echo -e "${YELLOW}Trying artifacts count endpoint...${NC}"
    
    local count_url_templates=(
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$PROJECT_NAME%2F$encoded_repo/artifacts/count"
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$encoded_repo/artifacts/count"
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$double_encoded_repo/artifacts/count"
    )
    
    for url in "${count_url_templates[@]}"; do
        echo -e "${YELLOW}Trying count URL: $url${NC}"
        
        local count_response=$(curl -s -k -m 30 \
            -H "Accept: application/json" \
            -u "$HARBOR_USER:$HARBOR_PASS" "$url")
        
        echo -e "${YELLOW}Count response: $count_response${NC}"
        
        if echo "$count_response" | jq . >/dev/null 2>&1; then
            if echo "$count_response" | jq -e '.count' >/dev/null 2>&1; then
                local count=$(echo "$count_response" | jq -r '.count')
                echo -e "${GREEN}Found count: $count${NC}"
                echo "$count"
                return 0
            fi
        fi
    done
    
    # Try a different approach with the artifacts API to get header
    echo -e "${YELLOW}Trying artifacts API to get count from header...${NC}"
    
    local artifact_url_templates=(
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$PROJECT_NAME%2F$encoded_repo/artifacts?page=1&page_size=1"
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$encoded_repo/artifacts?page=1&page_size=1"
        "${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$double_encoded_repo/artifacts?page=1&page_size=1"
    )
    
    for url in "${artifact_url_templates[@]}"; do
        echo -e "${YELLOW}Trying artifacts URL: $url${NC}"
        
        # Check headers for total count using GET instead of HEAD
        local header_response=$(curl -s -k -I -X GET -u "$HARBOR_USER:$HARBOR_PASS" "$url")
        echo -e "${YELLOW}Header response: ${NC}"
        echo "$header_response"
        
        # Look for x-total-count header
        if echo "$header_response" | grep -i "x-total-count" > /dev/null; then
            local count=$(echo "$header_response" | grep -i "x-total-count" | awk '{print $2}' | tr -d '\r')
            echo -e "${GREEN}Found total count from header: $count${NC}"
            echo "$count"
            return 0
        fi
    done
    
    # Last resort: try to get the actual artifacts and count them
    echo -e "${YELLOW}Trying to fetch artifacts directly and count them...${NC}"
    
    local direct_art_url="${HARBOR_PROTOCOL}://${HARBOR_URL}/api/v2.0/projects/$PROJECT_NAME/repositories/$encoded_repo/artifacts?page=1&page_size=100"
    local art_response=$(curl -s -k -m 60 -u "$HARBOR_USER:$HARBOR_PASS" "$direct_art_url")
    
    if echo "$art_response" | jq . >/dev/null 2>&1; then
        # Check if we got an array
        if echo "$art_response" | jq 'if type=="array" then true else false end' | grep -q true; then
            local art_count=$(echo "$art_response" | jq '. | length')
            echo -e "${GREEN}Found $art_count artifacts directly${NC}"
            echo "$art_count"
            return 0
        fi
    fi
    
    echo -e "${RED}Could not determine artifact count for $repo${NC}"
    echo "0"
    return 1
}

# Function to process a repository
process_repository() {
    local REPO=$1
    local repo_info=$2
    
    echo -e "\n${GREEN}Processing repository: $PROJECT_NAME/$REPO${NC}"
    
    # First try to get a direct count for the repository
    echo -e "${YELLOW}Attempting to get direct artifact count...${NC}"
    local direct_count_output=$(get_direct_repository_info "$REPO")
    
    # Extract just the last line which should be the numeric count
    ARTIFACT_COUNT=$(echo "$direct_count_output" | tail -n 1)
    
    # Check if artifact count is numeric
    if ! [[ "$ARTIFACT_COUNT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid artifact count: $ARTIFACT_COUNT${NC}"
        echo -e "${YELLOW}Full output from count function:${NC}"
        echo "$direct_count_output"
        
        # Try to extract the last numeric value from the output
        ARTIFACT_COUNT=$(echo "$direct_count_output" | grep -o '[0-9]\+' | tail -1)
        echo -e "${YELLOW}Extracted numeric count: $ARTIFACT_COUNT${NC}"
        
        # Fallback to previous method if direct count failed
        if ! [[ "$ARTIFACT_COUNT" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Direct count extraction failed, trying repository info method...${NC}"
            ARTIFACT_COUNT=$(get_artifact_count "$REPO" "$repo_info")
        fi
    fi
    
    echo -e "${YELLOW}Artifact count from API: $ARTIFACT_COUNT${NC}"
    
    # If artifact count is 0 or not found, skip
    if [ -z "$ARTIFACT_COUNT" ] || [ "$ARTIFACT_COUNT" = "null" ] || [ "$ARTIFACT_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No artifacts found in repository. Skipping...${NC}"
        return
    fi
    
    # If artifact count is less than or equal to keep limit, skip
    if [ "$ARTIFACT_COUNT" -le "$IMAGES_TO_KEEP" ]; then
        echo -e "${YELLOW}Repository has $ARTIFACT_COUNT artifacts, which is less than or equal to the keep limit ($IMAGES_TO_KEEP). Skipping...${NC}"
        return
    fi
    
    # Calculate how many images to delete
    DELETE_COUNT=$((ARTIFACT_COUNT - IMAGES_TO_KEEP))
    
    echo -e "${YELLOW}Found $ARTIFACT_COUNT artifacts. Will keep the newest $IMAGES_TO_KEEP artifacts and delete the oldest $DELETE_COUNT artifacts.${NC}"
    
    # If we're just displaying stats (dry run with no image fetching), continue
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE: Would delete $DELETE_COUNT artifacts (not actually deleting)${NC}"
        return
    fi
    
    # Try to get image tags if we need to actually delete
    echo -e "${YELLOW}Fetching images from repository...${NC}"
    IMAGES=$(get_image_tags "$REPO")
    
    # Check if we successfully got any images
    if [ -z "$IMAGES" ]; then
        echo -e "${RED}Failed to fetch artifact details. Cannot proceed with deletion.${NC}"
        echo -e "${YELLOW}The API reports $ARTIFACT_COUNT artifacts exist, but we couldn't fetch them.${NC}"
        return
    fi
    
    # Remove empty lines and calculate actual image count
    IMAGES=$(echo -e "$IMAGES" | grep -v "^$")
    TOTAL_IMAGES=$(echo -e "$IMAGES" | wc -l | tr -d ' \t')
    
    echo -e "${YELLOW}Successfully fetched $TOTAL_IMAGES artifacts of the reported $ARTIFACT_COUNT${NC}"
    
    # Handle case when we got fewer images than reported by API
    if [ "$TOTAL_IMAGES" -lt "$ARTIFACT_COUNT" ]; then
        echo -e "${YELLOW}Warning: Fetched fewer artifacts ($TOTAL_IMAGES) than reported by API ($ARTIFACT_COUNT)${NC}"
        
        # Update ARTIFACT_COUNT based on what we actually fetched
        echo -e "${YELLOW}Updating artifact count to match what was actually fetched: $TOTAL_IMAGES${NC}"
        ARTIFACT_COUNT=$TOTAL_IMAGES
        
        # Check if we have enough artifacts to perform cleanup
        if [ "$TOTAL_IMAGES" -lt "$IMAGES_TO_KEEP" ]; then
            echo -e "${RED}Unable to fetch enough artifacts to perform cleanup (fetched: $TOTAL_IMAGES, need: $IMAGES_TO_KEEP)${NC}"
            
            # Offer to proceed with what we have by adjusting keep count
            if [ "$AUTO_CONFIRM" = true ]; then
                echo -e "${YELLOW}Auto-confirm enabled, adjusting images to keep to match available count...${NC}"
                # Adjust keep count to a percentage of what we found (keep 80% of what we have)
                ADJUSTED_KEEP_COUNT=$(( TOTAL_IMAGES * 80 / 100 ))
                if [ "$ADJUSTED_KEEP_COUNT" -eq 0 ]; then
                    ADJUSTED_KEEP_COUNT=1  # Keep at least one
                fi
                echo -e "${YELLOW}Adjusting images to keep from $IMAGES_TO_KEEP to $ADJUSTED_KEEP_COUNT${NC}"
                IMAGES_TO_KEEP=$ADJUSTED_KEEP_COUNT
            else
                # Ask user what to do
                local answer
                echo -e "${YELLOW}Options:${NC}"
                echo -e "${YELLOW}1. Continue with fetched artifacts by adjusting keep count (will keep $((TOTAL_IMAGES * 80 / 100)) newest artifacts)${NC}"
                echo -e "${YELLOW}2. Continue with a custom keep count (you'll specify how many to keep)${NC}"
                echo -e "${YELLOW}3. Skip this repository${NC}"
                echo -e "${YELLOW}Enter choice [1/2/3] (default: 3 in 10s):${NC}"
                read -t 10 answer </dev/tty
                
                case "$answer" in
                    1) 
                        echo -e "${GREEN}Continuing with adjusted keep count...${NC}"
                        # Adjust keep count to 80% of what we found
                        ADJUSTED_KEEP_COUNT=$(( TOTAL_IMAGES * 80 / 100 ))
                        if [ "$ADJUSTED_KEEP_COUNT" -eq 0 ]; then
                            ADJUSTED_KEEP_COUNT=1  # Keep at least one
                        fi
                        echo -e "${YELLOW}Adjusting images to keep from $IMAGES_TO_KEEP to $ADJUSTED_KEEP_COUNT${NC}"
                        IMAGES_TO_KEEP=$ADJUSTED_KEEP_COUNT
                        ;;
                    2)
                        echo -e "${YELLOW}Enter how many artifacts to keep (must be less than $TOTAL_IMAGES):${NC}"
                        read custom_keep </dev/tty
                        if [[ "$custom_keep" =~ ^[0-9]+$ ]] && [ "$custom_keep" -lt "$TOTAL_IMAGES" ]; then
                            echo -e "${YELLOW}Setting images to keep to $custom_keep${NC}"
                            IMAGES_TO_KEEP=$custom_keep
                        else
                            echo -e "${RED}Invalid input. Using default of 80% of available artifacts...${NC}"
                            ADJUSTED_KEEP_COUNT=$(( TOTAL_IMAGES * 80 / 100 ))
                            if [ "$ADJUSTED_KEEP_COUNT" -eq 0 ]; then
                                ADJUSTED_KEEP_COUNT=1  # Keep at least one
                            fi
                            echo -e "${YELLOW}Adjusting images to keep from $IMAGES_TO_KEEP to $ADJUSTED_KEEP_COUNT${NC}"
                            IMAGES_TO_KEEP=$ADJUSTED_KEEP_COUNT
                        fi
                        ;;
                    *) 
                        echo -e "${YELLOW}Skipping repository...${NC}"
                        return
                        ;;
                esac
            fi
        fi
    fi
    
    # Recalculate how many to delete based on actual count and keep threshold
    DELETE_COUNT=$((ARTIFACT_COUNT - IMAGES_TO_KEEP))
    
    # Double-check that we have something to delete
    if [ "$DELETE_COUNT" -le 0 ]; then
        echo -e "${YELLOW}After adjustments, nothing to delete (keeping $IMAGES_TO_KEEP out of $ARTIFACT_COUNT). Skipping...${NC}"
        return
    fi
    
    echo -e "${YELLOW}Will delete $DELETE_COUNT artifacts of the $ARTIFACT_COUNT fetched (keeping newest $IMAGES_TO_KEEP).${NC}"
    
    # List of images to delete (oldest first)
    echo -e "${YELLOW}Images to delete (oldest first):${NC}"
    IMAGES_TO_DELETE=$(echo -e "$IMAGES" | tail -n $DELETE_COUNT)
    
    # Clean the IMAGES_TO_DELETE by filtering out any lines that don't contain valid digests
    # A valid digest typically starts with "sha256:" followed by a hex string
    IMAGES_TO_DELETE_FILTERED=""
    while IFS=$'\t' read -r DIGEST PUSH_TIME TAGS_COUNT TAG_NAMES; do
        # Skip invalid or empty lines
        if [ -z "$DIGEST" ]; then
            continue
        fi
        
        # Strict validation: Must have sha256: prefix and be of appropriate length
        if [[ "$DIGEST" == "sha256:"* ]] && [[ ${#DIGEST} -ge 70 ]]; then
            # Only include the digest, not the additional tab-separated data
            IMAGES_TO_DELETE_FILTERED="${IMAGES_TO_DELETE_FILTERED}${DIGEST}\n"
        else
            echo -e "${YELLOW}Skipping invalid digest format: $DIGEST${NC}"
        fi
    done <<< "$IMAGES_TO_DELETE"
    
    # Replace with filtered version
    IMAGES_TO_DELETE="$IMAGES_TO_DELETE_FILTERED"
    
    # Recount how many we'll actually delete after filtering
    FILTERED_DELETE_COUNT=$(echo -e "$IMAGES_TO_DELETE" | grep -v "^$" | wc -l | tr -d ' \t')
    if [ "$FILTERED_DELETE_COUNT" -ne "$DELETE_COUNT" ]; then
        echo -e "${YELLOW}After filtering invalid digests, will delete $FILTERED_DELETE_COUNT artifacts (was $DELETE_COUNT)${NC}"
        DELETE_COUNT=$FILTERED_DELETE_COUNT
    fi
    
    # Check if we have any images to delete after filtering
    if [ "$DELETE_COUNT" -le 0 ]; then
        echo -e "${YELLOW}No valid artifacts to delete after filtering. Skipping...${NC}"
        return
    fi
    
    # Show only digests
    echo -e "${YELLOW}Digests to delete:${NC}"
    echo -e "$IMAGES_TO_DELETE" | head -5
    if [ "$DELETE_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}(and $(($DELETE_COUNT - 5)) more...)${NC}"
    fi
    
    # Ask user for deletion confirmation
    if confirm_deletion "$REPO" "$ARTIFACT_COUNT" "$IMAGES_TO_KEEP" "$DELETE_COUNT"; then
        delete_images_in_batches "$REPO" "$IMAGES_TO_DELETE" "$DELETE_COUNT"
    else
        echo -e "${YELLOW}Deletion cancelled for repository: $PROJECT_NAME/$REPO${NC}"
    fi
}

# Function to delete images in batches
delete_images_in_batches() {
    local REPO=$1
    local IMAGES_TO_DELETE=$2
    local DELETE_COUNT=$3
    
    echo -e "${GREEN}Proceeding with deletion...${NC}"
    # Delete from oldest images first
    DELETED_COUNT=0
    FAILED_COUNT=0
    
    # Make sure BATCH_SIZE is at least 1
    if [ "$BATCH_SIZE" -lt 1 ]; then
        echo -e "${YELLOW}Invalid batch size $BATCH_SIZE, setting to 1${NC}"
        BATCH_SIZE=1
    fi
    
    # Display batch size
    echo -e "${YELLOW}Using batch size: $BATCH_SIZE (processing $BATCH_SIZE images at a time)${NC}"
    
    # Collect all digests
    DIGESTS=()
    while read -r line; do
        [ -z "$line" ] && continue
        # Clean up the digest
        digest=$(echo "$line" | tr -d '\r' | tr -d '\n' | xargs)
        [ -z "$digest" ] && continue
        DIGESTS+=("$digest")
    done < <(echo -e "$IMAGES_TO_DELETE")
    
    TOTAL_DIGESTS=${#DIGESTS[@]}
    echo -e "${GREEN}Found $TOTAL_DIGESTS digests to process in batches of $BATCH_SIZE${NC}"
    
    # Process in batches
    BATCH_NUM=0
    for ((i=0; i<TOTAL_DIGESTS; i+=$BATCH_SIZE)); do
        BATCH_NUM=$((BATCH_NUM+1))
        BATCH_START=$i
        BATCH_END=$((i+BATCH_SIZE-1))
        [ $BATCH_END -ge $TOTAL_DIGESTS ] && BATCH_END=$((TOTAL_DIGESTS-1))
        
        echo -e "${YELLOW}Processing batch $BATCH_NUM (digests $((BATCH_START+1))-$((BATCH_END+1)) of $TOTAL_DIGESTS)${NC}"
        
        # 병렬 처리를 순차 처리로 변경
        for ((j=BATCH_START; j<=BATCH_END; j++)); do
            DIGEST="${DIGESTS[$j]}"
            DIGEST_NUMBER=$((j+1))
            
            # 디버그 모드일 때만 자세한 출력
            if [ "$DEBUG" = true ]; then
                echo -e "${YELLOW}Processing digest $DIGEST_NUMBER/$TOTAL_DIGESTS: $DIGEST${NC}"
            else
                # 디버그 모드가 아닐 때는 진행 상황만 표시 (10개마다 한번씩)
                if [ $((DIGEST_NUMBER % 10)) -eq 0 ] || [ "$DIGEST_NUMBER" -eq "$TOTAL_DIGESTS" ]; then
                    echo -ne "\rProcessing: $DIGEST_NUMBER/$TOTAL_DIGESTS"
                fi
            fi
            
            if delete_image "$REPO" "$DIGEST"; then
                # 디버그 모드일 때만 자세한 출력
                if [ "$DEBUG" = true ]; then
                    echo -e "${GREEN}Successfully deleted digest $DIGEST_NUMBER/$TOTAL_DIGESTS${NC}"
                fi
                DELETED_COUNT=$((DELETED_COUNT+1))
            else
                # 디버그 모드일 때만 자세한 출력
                if [ "$DEBUG" = true ]; then
                    echo -e "${RED}Failed to delete digest $DIGEST_NUMBER/$TOTAL_DIGESTS${NC}"
                fi
                FAILED_COUNT=$((FAILED_COUNT+1))
            fi
        done
        
        # 디버그 모드가 아닐 때는 줄바꿈 추가
        if [ "$DEBUG" = false ]; then
            echo ""
        fi
        
        echo -e "${GREEN}Completed batch $BATCH_NUM: $DELETED_COUNT deleted, $FAILED_COUNT failed so far${NC}"
        
        # 마지막 배치가 아니면 잠시 대기
        [ $BATCH_END -lt $((TOTAL_DIGESTS-1)) ] && sleep 1
    done
    
    echo -e "${GREEN}Deletion summary: Successfully deleted $DELETED_COUNT artifacts, failed to delete $FAILED_COUNT artifacts.${NC}"
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize configuration
    initialize_config
    
    # Display startup information
    echo -e "${GREEN}Starting Harbor image cleanup...${NC}"
    if [ "$AUTO_CONFIRM" = true ]; then
        echo -e "${YELLOW}AUTO CONFIRMATION MODE: Will delete images without asking${NC}"
    fi
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE: Will not actually delete any images${NC}"
    fi
    echo -e "${YELLOW}Project: $PROJECT_NAME${NC}"
    
    # Check requirements and validate configuration
    check_requirements
    validate_config
    
    # Check Harbor API version
    check_harbor_api
    
    # Get repository info with artifact counts
    echo -e "${YELLOW}Getting repository information...${NC}"
    REPO_INFO=$(get_repository_info)
    
    # Try to get authentication token but continue with basic auth if it fails
    echo -e "${YELLOW}Getting authentication token...${NC}"
    TOKEN=$(get_auth_token)
    if [ -n "$TOKEN" ]; then
        echo -e "${GREEN}Successfully obtained authentication token${NC}"
    else
        echo -e "${YELLOW}No token obtained, will use basic authentication instead${NC}"
    fi
    
    # Check if 'all' repositories option was selected
    if [[ "${REPOSITORIES[*]}" =~ "all" ]]; then
        echo -e "${YELLOW}Processing ALL repositories in project $PROJECT_NAME${NC}"
        
        # Add informational message
        echo -e "${YELLOW}Fetching repository list...${NC}"
        
        # Get list of all repositories
        local all_repos=$(get_repositories)
        
        if [ -z "$all_repos" ]; then
            echo -e "${RED}Failed to get repository list for project $PROJECT_NAME${NC}"
            exit 1
        fi
        
        # Count valid repositories (non-empty lines)
        local repo_count=$(echo "$all_repos" | grep -v "^$" | wc -l | tr -d ' ')
        echo -e "${GREEN}Found $repo_count repositories to process${NC}"
        
        # Clear repositories array and fill with all repos
        REPOSITORIES=()
        while IFS= read -r repo; do
            [ -z "$repo" ] && continue
            REPOSITORIES+=("$repo")
        done < <(echo "$all_repos")
    fi
    
    # Display repositories to process
    echo -e "${YELLOW}Repositories to process: ${REPOSITORIES[*]}${NC}"
    echo -e "${YELLOW}Keep newest: $IMAGES_TO_KEEP images${NC}"
    echo -e "${YELLOW}Batch size: $BATCH_SIZE images at a time${NC}"
    
    # Process each repository
    for REPO in "${REPOSITORIES[@]}"; do
        [ -z "$REPO" ] && continue
        
        process_repository "$REPO" "$REPO_INFO"
    done
    
    echo -e "\n${GREEN}Cleanup completed!${NC}" 
}

# Execute main function with all arguments
main "$@" 
