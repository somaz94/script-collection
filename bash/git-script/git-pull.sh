#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Option parsing
FORCE_MODE=false
STASH_MODE=false
INTERACTIVE_MODE=false

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
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force       Force pull (reset to remote)"
            echo "  --stash       Automatically stash uncommitted changes"
            echo "  --interactive Handle conflicts interactively"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=== Enhanced Git Pull All Script ===${NC}"
echo ""

# Save current directory
ORIGINAL_DIR=$(pwd)

# Success/failure/conflict counters
SUCCESS_COUNT=0
ERROR_COUNT=0
CONFLICT_COUNT=0
SKIPPED_COUNT=0

# Record repositories with conflicts
CONFLICT_REPOS=()

# Function: Get user input
ask_user() {
    local prompt="$1"
    local default="$2"
    echo -ne "${YELLOW}${prompt} [${default}]: ${NC}"
    read -r response
    echo "${response:-$default}"
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
            return 1
        fi
    fi
    
    return 0
}

# Function: Execute git pull and handle conflicts
perform_pull() {
    local repo_name="$1"
    
    if [ "$FORCE_MODE" = true ]; then
        echo -e "${PURPLE}   Force mode: Resetting to remote...${NC}"
        local current_branch=$(git branch --show-current)
        if git fetch origin && git reset --hard "origin/$current_branch"; then
            echo -e "${GREEN}   ✅ Force pulled successfully${NC}"
            return 0
        else
            echo -e "${RED}   ❌ Force pull failed${NC}"
            return 1
        fi
    fi
    
    # Attempt normal pull
    if git pull 2>/tmp/git_pull_error_$; then
        echo -e "${GREEN}   ✅ Pull successful${NC}"
        return 0
    else
        local error_msg=$(cat /tmp/git_pull_error_$ 2>/dev/null)
        rm -f /tmp/git_pull_error_$
        
        # Check for conflicts
        if echo "$error_msg" | grep -q "CONFLICT\|Automatic merge failed"; then
            echo -e "${RED}   ⚔️  Merge conflict detected!${NC}"
            CONFLICT_REPOS+=("$repo_name")
            
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
                echo -e "${YELLOW}   💡 To resolve: cd ${repo_name} && git status${NC}"
                return 1
            fi
        else
            echo -e "${RED}   ❌ Pull failed: ${error_msg}${NC}"
            return 1
        fi
    fi
}

# Iterate through all directories in current directory
for dir in */; do
    # Check if directory exists
    if [ -d "$dir" ]; then
        # Check if .git directory exists (check if it's a git repository)
        if [ -d "$dir/.git" ]; then
            echo -e "${YELLOW}📁 Processing: ${dir%/}${NC}"
            
            # Move to the directory
            cd "$dir" || {
                echo -e "${RED}❌ Failed to enter directory: ${dir%/}${NC}"
                ERROR_COUNT=$((ERROR_COUNT + 1))
                continue
            }
            
            # Check git status
            check_git_status "${dir%/}"
            status_result=$?
            
            if [ $status_result -eq 0 ]; then
                # Execute pull
                if perform_pull "${dir%/}"; then
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                else
                    if [[ " ${CONFLICT_REPOS[*]} " =~ " ${dir%/} " ]]; then
                        CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
                    else
                        ERROR_COUNT=$((ERROR_COUNT + 1))
                    fi
                fi
            elif [ $status_result -eq 2 ]; then
                # User chose to skip
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            else
                # Status check failed
                ERROR_COUNT=$((ERROR_COUNT + 1))
            fi
            
            echo ""
            
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

# Display list of repositories with conflicts
if [ ${#CONFLICT_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}🔥 Repositories with conflicts:${NC}"
    for repo in "${CONFLICT_REPOS[@]}"; do
        echo -e "${PURPLE}   • $repo${NC}"
        echo -e "     ${YELLOW}To resolve: cd $repo && git status${NC}"
    done
    echo ""
    echo -e "${BLUE}💡 Conflict resolution tips:${NC}"
    echo -e "   1. ${YELLOW}cd <repo-name>${NC}"
    echo -e "   2. ${YELLOW}git status${NC} (see conflicted files)"
    echo -e "   3. Edit conflicted files or use ${YELLOW}git mergetool${NC}"
    echo -e "   4. ${YELLOW}git add <resolved-files>${NC}"
    echo -e "   5. ${YELLOW}git commit${NC}"
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
