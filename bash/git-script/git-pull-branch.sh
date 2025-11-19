#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Option parsing
FORCE_MODE=false
STASH_MODE=false
INTERACTIVE_MODE=false
BRANCHES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --stash)
            STASH_MODE=true
            shift
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        -b|--branch)
            if [ -n "$2" ]; then
                IFS=',' read -ra BRANCH_LIST <<< "$2"
                for branch in "${BRANCH_LIST[@]}"; do
                    BRANCHES+=("$(echo "$branch" | xargs)") # trim whitespace
                done
                shift 2
            else
                echo "Error: --branch requires a value (comma-separated list)"
                exit 1
            fi
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Force pull (reset to remote)"
            echo "  --stash              Automatically stash uncommitted changes"
            echo "  --interactive        Handle conflicts interactively"
            echo "  -b, --branch LIST    Comma-separated list of branches to pull"
            echo "                       Example: -b main,develop,feature/new"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Pull current branch in all repos"
            echo "  $0 -b main,develop                   # Pull main and develop branches"
            echo "  $0 -b main --stash                   # Pull main branch with auto-stash"
            echo "  $0 -b main,develop --interactive     # Interactive mode for conflicts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=== Enhanced Git Pull All Script ===${NC}"

# Display target branches
if [ ${#BRANCHES[@]} -gt 0 ]; then
    echo -e "${CYAN}🎯 Target branches: ${BRANCHES[*]}${NC}"
else
    echo -e "${CYAN}🎯 Target: Current branch in each repository${NC}"
fi
echo ""

# Save current directory
ORIGINAL_DIR=$(pwd)

# Success/failure/conflict counters
SUCCESS_COUNT=0
ERROR_COUNT=0
CONFLICT_COUNT=0
SKIPPED_COUNT=0
BRANCH_NOT_FOUND_COUNT=0
DIRTY_COUNT=0

# Record repositories with issues
CONFLICT_REPOS=()
BRANCH_NOT_FOUND_REPOS=()
DIRTY_REPOS=()

# Function: Get user input
ask_user() {
    local prompt="$1"
    local default="$2"
    echo -ne "${YELLOW}${prompt} [${default}]: ${NC}"
    read -r response
    echo "${response:-$default}"
}

# Function: Check if branch exists (local or remote)
check_branch_exists() {
    local branch="$1"
    local repo_name="$2"
    
    # Check if branch exists locally
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        return 0
    fi
    
    # Check if branch exists on remote
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "${YELLOW}   ⚠️  Branch '$branch' not found in $repo_name${NC}"
    return 1
}

# Function: Switch to branch (create if needed from remote)
switch_to_branch() {
    local branch="$1"
    local repo_name="$2"
    
    # If already on the target branch
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" = "$branch" ]; then
        echo -e "${BLUE}   Already on branch: $branch${NC}"
        return 0
    fi
    
    # Try to checkout existing local branch
    if git checkout "$branch" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Switched to local branch: $branch${NC}"
        return 0
    fi
    
    # Try to checkout and track remote branch
    if git checkout -b "$branch" "origin/$branch" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Created and switched to branch: $branch (tracking origin/$branch)${NC}"
        return 0
    fi
    
    echo -e "${RED}   ❌ Failed to switch to branch: $branch${NC}"
    return 1
}

# Function: Check git status
check_git_status() {
    local repo_name="$1"
    
    # Check for detached HEAD
    if ! git symbolic-ref HEAD >/dev/null 2>&1; then
        echo -e "${RED}⚠️  ${repo_name}: In detached HEAD state${NC}"
        return 1
    fi
    
    # Check for uncommitted changes
    if git status --porcelain | grep -q .; then
        echo -e "${YELLOW}⚠️  ${repo_name}: Working directory not clean${NC}"
        if [ "$STASH_MODE" = true ]; then
            echo -e "${BLUE}   Stashing changes...${NC}"
            if git stash push -m "Auto-stash before pull $(date)"; then
                echo -e "${GREEN}   ✅ Changes stashed${NC}"
                return 0
            else
                echo -e "${RED}   ❌ Failed to stash changes${NC}"
                return 1
            fi
        elif [ "$INTERACTIVE_MODE" = true ]; then
            response=$(ask_user "Stash changes and proceed? (y/n/s)" "n")
            case "$response" in
                y|Y)
                    if git stash push -m "Interactive stash before pull $(date)"; then
                        echo -e "${GREEN}   ✅ Changes stashed${NC}"
                        return 0
                    else
                        echo -e "${RED}   ❌ Failed to stash changes${NC}"
                        return 1
                    fi
                    ;;
                s|S)
                    echo -e "${YELLOW}   Skipping this repository${NC}"
                    return 2
                    ;;
                *)
                    echo -e "${YELLOW}   Skipping this repository${NC}"
                    return 2
                    ;;
            esac
        else
            echo "   Run 'git status' in this directory to see uncommitted changes"
            return 3  # Special code for dirty working directory
        fi
    fi
    
    return 0
}

# Function: Execute git pull and handle conflicts
perform_pull() {
    local repo_name="$1"
    local branch="$2"
    
    if [ "$FORCE_MODE" = true ]; then
        echo -e "${PURPLE}   Force mode: Resetting to remote...${NC}"
        if git fetch origin && git reset --hard "origin/$branch"; then
            echo -e "${GREEN}   ✅ Force pulled successfully${NC}"
            return 0
        else
            echo -e "${RED}   ❌ Force pull failed${NC}"
            return 1
        fi
    fi
    
    # Fetch latest changes
    if ! git fetch origin; then
        echo -e "${RED}   ❌ Failed to fetch from origin${NC}"
        return 1
    fi
    
    # Attempt normal pull
    if git pull origin "$branch" 2>/tmp/git_pull_error_$$; then
        echo -e "${GREEN}   ✅ Pull successful${NC}"
        return 0
    else
        local error_msg=$(cat /tmp/git_pull_error_$$ 2>/dev/null)
        rm -f /tmp/git_pull_error_$$
        
        # Check for conflicts
        if echo "$error_msg" | grep -q "CONFLICT\|Automatic merge failed"; then
            echo -e "${RED}   ⚔️  Merge conflict detected!${NC}"
            CONFLICT_REPOS+=("$repo_name ($branch)")
            
            if [ "$INTERACTIVE_MODE" = true ]; then
                echo -e "${YELLOW}   Conflict files:${NC}"
                git status --porcelain | grep "^UU\|^AA\|^DD" || git diff --name-only --diff-filter=U
                
                response=$(ask_user "How to handle? (resolve/abort/skip)" "skip")
                case "$response" in
                    resolve|r)
                        echo -e "${BLUE}   Opening merge tool... (exit when done)${NC}"
                        git mergetool
                        if git status --porcelain | grep -q "^UU\|^AA\|^DD"; then
                            echo -e "${RED}   ❌ Conflicts still remain${NC}"
                            return 1
                        else
                            echo -e "${GREEN}   ✅ Conflicts resolved, committing...${NC}"
                            git commit --no-edit
                            return 0
                        fi
                        ;;
                    abort|a)
                        git merge --abort
                        echo -e "${YELLOW}   ⏪ Merge aborted${NC}"
                        return 1
                        ;;
                    *)
                        echo -e "${YELLOW}   ⏭️  Skipping conflict resolution${NC}"
                        return 1
                        ;;
                esac
            else
                echo -e "${YELLOW}   💡 To resolve: cd ${repo_name} && git checkout $branch && git status${NC}"
                return 1
            fi
        else
            echo -e "${RED}   ❌ Pull failed: ${error_msg}${NC}"
            return 1
        fi
    fi
}

# Function: Process single repository
process_repository() {
    local dir="$1"
    local repo_name="${dir%/}"
    
    echo -e "${YELLOW}📁 Processing: ${repo_name}${NC}"
    
    # Move to the directory
    cd "$dir" || {
        echo -e "${RED}❌ Failed to enter directory: ${repo_name}${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    }
    
    # Fetch to ensure we have latest remote info
    git fetch origin >/dev/null 2>&1
    
    local branches_to_process=()
    
    # Determine which branches to process
    if [ ${#BRANCHES[@]} -gt 0 ]; then
        branches_to_process=("${BRANCHES[@]}")
    else
        # Use current branch
        local current_branch=$(git branch --show-current)
        if [ -n "$current_branch" ]; then
            branches_to_process=("$current_branch")
        else
            echo -e "${RED}   ❌ Could not determine current branch${NC}"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            return 1
        fi
    fi
    
    local repo_success=true
    local original_branch=$(git branch --show-current)
    
    # Process each branch
    for branch in "${branches_to_process[@]}"; do
        echo -e "${CYAN}  🌿 Processing branch: $branch${NC}"
        
        # Check if branch exists
        if ! check_branch_exists "$branch" "$repo_name"; then
            BRANCH_NOT_FOUND_REPOS+=("$repo_name ($branch)")
            BRANCH_NOT_FOUND_COUNT=$((BRANCH_NOT_FOUND_COUNT + 1))
            repo_success=false
            continue
        fi
        
        # Switch to target branch
        if ! switch_to_branch "$branch" "$repo_name"; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            repo_success=false
            continue
        fi
        
        # Check git status
        check_git_status "$repo_name"
        status_result=$?
        
        if [ $status_result -eq 0 ]; then
            # Execute pull
            if perform_pull "$repo_name" "$branch"; then
                echo -e "${GREEN}     ✅ $branch updated successfully${NC}"
            else
                if [[ " ${CONFLICT_REPOS[*]} " =~ " $repo_name ($branch) " ]]; then
                    CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
                else
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                fi
                repo_success=false
            fi
        elif [ $status_result -eq 2 ]; then
            # User chose to skip
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            repo_success=false
        elif [ $status_result -eq 3 ]; then
            # Working directory is dirty (uncommitted changes)
            DIRTY_REPOS+=("$repo_name ($branch)")
            DIRTY_COUNT=$((DIRTY_COUNT + 1))
            # Don't count as failure, just skip this branch
        else
            # Status check failed (detached HEAD or other error)
            ERROR_COUNT=$((ERROR_COUNT + 1))
            repo_success=false
        fi
    done
    
    # Switch back to original branch if specified branches were processed
    if [ ${#BRANCHES[@]} -gt 0 ] && [ -n "$original_branch" ]; then
        git checkout "$original_branch" >/dev/null 2>&1
        echo -e "${BLUE}  ↩️  Switched back to: $original_branch${NC}"
    fi
    
    if [ "$repo_success" = true ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
    
    echo ""
}

# Main execution
# Iterate through all directories in current directory
for dir in */; do
    # Check if directory exists
    if [ -d "$dir" ]; then
        # Check if .git directory exists (check if it's a git repository)
        if [ -d "$dir/.git" ]; then
            process_repository "$dir"
            
            # Return to original directory
            cd "$ORIGINAL_DIR" || {
                echo -e "${RED}❌ Failed to return to original directory${NC}"
                exit 1
            }
        else
            echo -e "${BLUE}ℹ️  Skipping ${dir%/}: Not a git repository${NC}"
        fi
    fi
done

# Result summary
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}✅ Successfully updated: $SUCCESS_COUNT repositories${NC}"
echo -e "${RED}❌ Failed: $ERROR_COUNT repositories${NC}"
echo -e "${PURPLE}⚔️  Conflicts: $CONFLICT_COUNT repositories${NC}"
echo -e "${YELLOW}⏭️  Skipped: $SKIPPED_COUNT repositories${NC}"
echo -e "${CYAN}🌿 Branch not found: $BRANCH_NOT_FOUND_COUNT cases${NC}"
echo -e "${YELLOW}⚠️  Uncommitted changes: $DIRTY_COUNT cases${NC}"

# Display list of repositories with conflicts
if [ ${#CONFLICT_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}🔥 Repositories with conflicts:${NC}"
    for repo in "${CONFLICT_REPOS[@]}"; do
        echo -e "${PURPLE}   • $repo${NC}"
        repo_name=$(echo "$repo" | cut -d'(' -f1 | xargs)
        branch_name=$(echo "$repo" | sed 's/.*(\(.*\)).*/\1/')
        echo -e "     ${YELLOW}To resolve: cd $repo_name && git checkout $branch_name && git status${NC}"
    done
fi

# Display list of repositories with missing branches
if [ ${#BRANCH_NOT_FOUND_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${CYAN}🌿 Branches not found:${NC}"
    for repo in "${BRANCH_NOT_FOUND_REPOS[@]}"; do
        echo -e "${CYAN}   • $repo${NC}"
    done
fi

# Display list of repositories with uncommitted changes
if [ ${#DIRTY_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Repositories with uncommitted changes:${NC}"
    for repo in "${DIRTY_REPOS[@]}"; do
        echo -e "${YELLOW}   • $repo${NC}"
    done
    echo -e "   ${BLUE}💡 Use --stash option to automatically stash changes before pull${NC}"
fi

if [ ${#CONFLICT_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${BLUE}💡 Conflict resolution tips:${NC}"
    echo -e "   1. ${YELLOW}cd <repo-name>${NC}"
    echo -e "   2. ${YELLOW}git checkout <branch-name>${NC}"
    echo -e "   3. ${YELLOW}git status${NC} (see conflicted files)"
    echo -e "   4. Edit conflicted files or use ${YELLOW}git mergetool${NC}"
    echo -e "   5. ${YELLOW}git add <resolved-files>${NC}"
    echo -e "   6. ${YELLOW}git commit${NC}"
fi

# Overall result evaluation
total_issues=$((ERROR_COUNT + CONFLICT_COUNT))
if [ $total_issues -eq 0 ]; then
    echo -e "${GREEN}🎉 All git repositories processed successfully!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some repositories need attention. Check the details above.${NC}"
    exit 1
fi
