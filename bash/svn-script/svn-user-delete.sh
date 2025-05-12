#!/bin/bash

# SVN Server Configuration Variables
# -------------------------------
# SVN_SERVER_IP: IP address of the SVN server
# SVN_SERVER_USER: SSH username for SVN server access
# SVN_SERVER_PASSWORD: SSH password for SVN server access
# DOCKER_CONTAINER: Name of the Docker container running SVN
# SVN_CONF_PATH: Path to SVN configuration directory
# SVN_AUTHZ_FILE: Path to SVN authorization file
# SVN_PASSWD_FILE: Path to SVN password file
SVN_SERVER_IP=""
SVN_SERVER_USER=""
SVN_SERVER_PASSWORD=""
DOCKER_CONTAINER=""
SVN_CONF_PATH=""
SVN_AUTHZ_FILE="$SVN_CONF_PATH/authz"
SVN_PASSWD_FILE="$SVN_CONF_PATH/passwd"

# List of users to be deleted
# Add or remove usernames as needed
USERNAMES=(
  test2
  test3
)

# Prerequisites Check
# -----------------
# Verify that sshpass is installed
# Required for automated SSH authentication
if ! command -v sshpass &> /dev/null; then
  echo "❌ sshpass is not installed. Please install it first."
  echo "MacOS: brew install sshpass"
  echo "Ubuntu/Debian: apt-get install sshpass"
  echo "CentOS/RHEL: yum install sshpass"
  exit 1
fi

# Server Connection Check
# ---------------------
# Verify SSH connection to SVN server
# Ensures the script can communicate with the server
echo "🔍 Checking connection to SVN server..."
export SSHPASS=$SVN_SERVER_PASSWORD
if ! sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $SVN_SERVER_USER@$SVN_SERVER_IP "echo '✅ SSH connection successful'" &> /dev/null; then
  echo "❌ Could not connect to SVN server at $SVN_SERVER_IP"
  exit 1
fi
echo "✅ Successfully connected to SVN server"

# Docker Container Check
# --------------------
# Verify that the SVN Docker container is running
# Required for SVN operations
echo "🔍 Checking Docker container..."
DOCKER_RUNNING=$(sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP "docker ps | grep $DOCKER_CONTAINER || echo 'not running'")
if [[ "$DOCKER_RUNNING" == "not running" ]]; then
  echo "❌ Docker container $DOCKER_CONTAINER is not running on SVN server!"
  exit 1
fi
echo "✅ Docker container $DOCKER_CONTAINER is running"

# Function: Delete User from SVN
# ----------------------------
# Removes a user from SVN configuration files (authz and passwd)
# Parameters:
#   $1: Username to delete
# Returns:
#   0: Success
#   1: Failure
#   2: User doesn't exist
delete_user_from_svn() {
  local USERNAME=$1
  
  echo "👤 Checking user '$USERNAME' in SVN..."
  
  # Check if user exists
  export SSHPASS=$SVN_SERVER_PASSWORD
  USER_EXISTS=$(sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP '
    USERNAME='$USERNAME'
    DOCKER_CONTAINER='$DOCKER_CONTAINER'
    SVN_AUTHZ_FILE='$SVN_AUTHZ_FILE'
    SVN_PASSWD_FILE='$SVN_PASSWD_FILE'
    
    echo "✅ SSH connection successful"
    
    # Check user existence in both files
    AUTH_EXISTS=$(docker exec $DOCKER_CONTAINER grep -q "^'$USERNAME'=" $SVN_AUTHZ_FILE && echo true || echo false)
    PASSWD_EXISTS=$(docker exec $DOCKER_CONTAINER grep -q "^'$USERNAME'=" $SVN_PASSWD_FILE && echo true || echo false)
    
    echo "AUTH_EXISTS=$AUTH_EXISTS, PASSWD_EXISTS=$PASSWD_EXISTS"
    
    if [ "$AUTH_EXISTS" = "false" ] && [ "$PASSWD_EXISTS" = "false" ]; then
      echo "NOT_FOUND"
    else
      echo "FOUND"
    fi
  ')
  
  echo "User exists check: $USER_EXISTS"
  
  # Skip if user doesn't exist
  if echo "$USER_EXISTS" | grep -q "NOT_FOUND"; then
    echo "⚠️ User '$USERNAME' does not exist in SVN configuration"
    return 2
  fi
  
  echo "👤 Deleting user '$USERNAME' from SVN..."
  
  # Delete user from SVN configuration
  export SSHPASS=$SVN_SERVER_PASSWORD
  DELETED=$(sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP '
    USERNAME='$USERNAME'
    DOCKER_CONTAINER='$DOCKER_CONTAINER'
    SVN_CONF_PATH='$SVN_CONF_PATH'
    SVN_AUTHZ_FILE='$SVN_AUTHZ_FILE'
    SVN_PASSWD_FILE='$SVN_PASSWD_FILE'
    
    echo "✅ SSH connection successful"
    
    # Execute commands in Docker container
    DELETED=$(docker exec $DOCKER_CONTAINER bash -c "
      cd '$SVN_CONF_PATH'
      AUTH_DELETED=false
      PASSWD_DELETED=false
      
      # Check authz file
      echo \"Checking authz file for user '$USERNAME'...\"
      grep \"^'$USERNAME'=\" '$SVN_AUTHZ_FILE' || echo \"User not found in authz file\"
      
      # Check passwd file
      echo \"Checking passwd file for user '$USERNAME'...\"
      grep \"^'$USERNAME'=\" '$SVN_PASSWD_FILE' || echo \"User not found in passwd file\"
      
      # 1. Remove user from authz file
      if grep -q \"^'$USERNAME'=\" '$SVN_AUTHZ_FILE'; then
        echo \"Found user '$USERNAME' in SVN authz file\"
        # Create backup
        cp '$SVN_AUTHZ_FILE' '$SVN_AUTHZ_FILE'.bak
        # Remove user
        sed -i \"/^'$USERNAME'=/d\" '$SVN_AUTHZ_FILE'
        # Verify removal
        if ! grep -q \"^'$USERNAME'=\" '$SVN_AUTHZ_FILE'; then
          echo \"Removed '$USERNAME' from SVN authz file\"
          AUTH_DELETED=true
        else
          echo \"Failed to remove from authz file\"
        fi
      fi
      
      # 2. Remove user from passwd file
      if grep -q \"^'$USERNAME'=\" '$SVN_PASSWD_FILE'; then
        echo \"Found user '$USERNAME' in SVN passwd file\"
        # Create backup
        cp '$SVN_PASSWD_FILE' '$SVN_PASSWD_FILE'.bak
        # Remove user
        sed -i \"/^'$USERNAME'=/d\" '$SVN_PASSWD_FILE'
        # Verify removal
        if ! grep -q \"^'$USERNAME'=\" '$SVN_PASSWD_FILE'; then
          echo \"Removed '$USERNAME' from SVN passwd file\"
          PASSWD_DELETED=true
        else
          echo \"Failed to remove from passwd file\"
        fi
      fi
      
      # Return deletion status
      if [ \"\$AUTH_DELETED\" = \"true\" ] || [ \"\$PASSWD_DELETED\" = \"true\" ]; then
        echo \"DELETED\"
      else
        echo \"FAILED\"
      fi
    ")
    
    # Output result
    echo "$DELETED"
  ')
  
  echo "Delete operation result: $DELETED"
  
  # Check deletion result
  if echo "$DELETED" | grep -q "DELETED"; then
    echo "✅ Successfully deleted user '$USERNAME' from SVN configuration"
    return 0
  else
    echo "❌ Failed to delete user '$USERNAME' from SVN configuration"
    return 1
  fi
}

# Function: Restart SVN Service
# ---------------------------
# Restarts the SVN service to apply configuration changes
# Returns:
#   0: Success
#   1: Failure
restart_svn_service() {
  echo "🔄 Restarting SVN service..."
  
  # Execute restart command via SSH
  export SSHPASS=$SVN_SERVER_PASSWORD
  sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP '
    DOCKER_CONTAINER='$DOCKER_CONTAINER'
    
    echo "✅ SSH connection successful"
    
    # Execute commands in Docker container
    RESTART_RESULT=$(docker exec $DOCKER_CONTAINER bash -c "
      # Find SVN process
      SVN_PID=\$(ps -ef | grep \"svnserve -d -r\" | grep -v grep | awk \"{print \\\$2}\")
      
      if [ -z \"\$SVN_PID\" ]; then
        echo \"SVN service is not running\"
      else
        echo \"Stopping SVN service with PID \$SVN_PID\"
        kill -9 \$SVN_PID
        sleep 1
      fi
      
      # Restart SVN service
      echo \"Starting SVN service...\"
      svnserve -d -r /data/svn/
      
      # Verify service status
      NEW_SVN_PID=\$(ps -ef | grep \"svnserve -d -r\" | grep -v grep | awk \"{print \\\$2}\")
      if [ -n \"\$NEW_SVN_PID\" ]; then
        echo \"SVN service started successfully with PID \$NEW_SVN_PID\"
        exit 0
      else
        echo \"Failed to start SVN service\"
        exit 1
      fi
    ")
    
    echo "$RESTART_RESULT"
    exit $?
  '
  
  # Check restart result
  RESULT=$?
  if [ "$RESULT" -eq 0 ]; then
    echo "✅ Successfully restarted SVN service"
  else
    echo "❌ Failed to restart SVN service"
    return 1
  fi
  
  return 0
}

echo "🔧 Starting SVN user deletion..."

# Process Users
# ------------
# Delete each user in the USERNAMES array
USER_DELETED=false
for USERNAME in "${USERNAMES[@]}"; do
  echo "----------------------------------------"
  echo "🔧 Processing user: $USERNAME"
  
  # Delete user from SVN
  delete_user_from_svn "$USERNAME"
  RESULT=$?
  
  if [ "$RESULT" -eq 0 ]; then
    USER_DELETED=true
    echo "✨ User deleted successfully"
  elif [ "$RESULT" -eq 2 ]; then
    echo "✨ User doesn't exist, no changes needed"
  else
    echo "❌ Failed to process user"
  fi
  
  echo "✨ Done for $USERNAME"
  echo "----------------------------------------"
done

# Service Restart
# -------------
# Restart SVN service only if changes were made
if [ "$USER_DELETED" = "true" ]; then
  echo "🔧 Changes detected, restarting SVN service..."
  restart_svn_service
else
  echo "ℹ️ No changes were made, skipping service restart"
fi

echo "🎉 SVN user deletion completed" 
