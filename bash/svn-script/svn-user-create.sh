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
# SVN_PASSWORD: Default password for new SVN users
SVN_SERVER_IP=""
SVN_SERVER_USER=""
SVN_SERVER_PASSWORD=""
DOCKER_CONTAINER=""
SVN_CONF_PATH=""
SVN_AUTHZ_FILE="$SVN_CONF_PATH/authz"
SVN_PASSWD_FILE="$SVN_CONF_PATH/passwd"
SVN_PASSWORD=""

# List of users to be created
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

# Function: Add User to SVN
# ------------------------
# Adds a user to SVN configuration files (authz and passwd)
# Parameters:
#   $1: Username to add
# Returns:
#   0: Success
#   1: Failure
#   2: User already exists
add_user_to_svn() {
  local USERNAME=$1
  local USER_WAS_ADDED=false
  
  echo "👤 Adding user '$USERNAME' to SVN with read-write permissions..."
  
  # Check if user already exists
  export SSHPASS=$SVN_SERVER_PASSWORD
  CHECK_RESULT=$(sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP "
    echo '✅ SSH connection successful'
    
    # Check user existence in both files
    AUTHZ_EXISTS=\$(docker exec $DOCKER_CONTAINER bash -c \"grep -q \\\"^$USERNAME=\\\" $SVN_AUTHZ_FILE && echo true || echo false\")
    PASSWD_EXISTS=\$(docker exec $DOCKER_CONTAINER bash -c \"grep -q \\\"^$USERNAME=\\\" $SVN_PASSWD_FILE && echo true || echo false\")
    
    echo \"AUTHZ_EXISTS=\$AUTHZ_EXISTS\"
    echo \"PASSWD_EXISTS=\$PASSWD_EXISTS\"
    
    if [ \"\$AUTHZ_EXISTS\" = \"true\" ] && [ \"\$PASSWD_EXISTS\" = \"true\" ]; then
      echo \"USER_EXISTS=BOTH\"
    else
      echo \"USER_EXISTS=NO\"
    fi
  ")
  
  echo "Check result: $CHECK_RESULT"
  
  # Skip if user already exists in both files
  if echo "$CHECK_RESULT" | grep -q "USER_EXISTS=BOTH"; then
    echo "ℹ️ User '$USERNAME' already exists in SVN configuration"
    return 2
  fi
  
  echo "🔧 User does not exist in both files, proceeding with adding..."
  
  # Add user to SVN configuration
  export SSHPASS=$SVN_SERVER_PASSWORD
  MODIFY_RESULT=$(sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP "
    echo '✅ SSH connection successful'
    
    # Execute commands in Docker container
    USER_MODIFIED=\$(docker exec $DOCKER_CONTAINER bash -c \"
      cd $SVN_CONF_PATH
      
      # Check if user exists in either file
      AUTH_EXISTS=false
      PASSWD_EXISTS=false
      MODIFIED=false
      
      if grep -q \\\"^$USERNAME=\\\" $SVN_AUTHZ_FILE; then
        echo \\\"User $USERNAME already exists in SVN authz file\\\"
        AUTH_EXISTS=true
      fi
      
      if grep -q \\\"^$USERNAME=\\\" $SVN_PASSWD_FILE; then
        echo \\\"User $USERNAME already exists in SVN passwd file\\\"
        PASSWD_EXISTS=true
      fi
      
      # Skip if user exists in both files
      if [ \\\"\$AUTH_EXISTS\\\" = \\\"true\\\" ] && [ \\\"\$PASSWD_EXISTS\\\" = \\\"true\\\" ]; then
        echo \\\"User already exists in both SVN files. No changes needed.\\\"
        exit 0
      fi
      
      # 1. Modify authz file - Set permissions
      if [ \\\"\$AUTH_EXISTS\\\" != \\\"true\\\" ]; then
        # Create backup
        cp $SVN_AUTHZ_FILE ${SVN_AUTHZ_FILE}.bak
        
        # Add user with read-write permissions
        echo \\\"$USERNAME=rw\\\" >> $SVN_AUTHZ_FILE
        
        echo \\\"Added user to SVN authz file with read-write permissions\\\"
        MODIFIED=true
      fi
      
      # 2. Modify passwd file - Set password
      if [ \\\"\$PASSWD_EXISTS\\\" != \\\"true\\\" ]; then
        # Create backup
        cp $SVN_PASSWD_FILE ${SVN_PASSWD_FILE}.bak
        
        # Add user with password
        echo \\\"$USERNAME=$SVN_PASSWORD\\\" >> $SVN_PASSWD_FILE
        
        echo \\\"Added user to SVN passwd file\\\"
        MODIFIED=true
      fi
      
      if [ \\\"\$MODIFIED\\\" = \\\"true\\\" ]; then
        echo \\\"USER_MODIFIED=true\\\"
        exit 0
      else
        echo \\\"USER_MODIFIED=false\\\"
        exit 2
      fi
    \")
    
    echo \"USER_MODIFIED output: \$USER_MODIFIED\"
    
    # Check modification status
    if echo \"\$USER_MODIFIED\" | grep -q \"USER_MODIFIED=true\"; then
      echo \"✅ User configuration modified\"
      exit 0
    else 
      if echo \"\$USER_MODIFIED\" | grep -q \"User already exists in both SVN files\"; then
        echo \"ℹ️ User already exists in both SVN files\"
        exit 2
      else
        echo \"ℹ️ No modifications were made but user might still need updates\"
        exit 0
      fi
    fi
  ")
  
  echo "Modify result exit code: $?"
  echo "Modify result output: $MODIFY_RESULT"
  
  # Check operation result
  RESULT=$?
  if [ "$RESULT" -eq 0 ]; then
    echo "✅ Successfully added or updated user '$USERNAME' in SVN configuration"
    return 0
  elif [ "$RESULT" -eq 2 ]; then
    echo "ℹ️ User '$USERNAME' already exists in SVN configuration"
    return 2
  else
    echo "❌ Failed to add user '$USERNAME' to SVN configuration"
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
  sshpass -e ssh -o StrictHostKeyChecking=no $SVN_SERVER_USER@$SVN_SERVER_IP "
    echo '✅ SSH connection successful'
    
    # Execute commands in Docker container
    docker exec $DOCKER_CONTAINER bash -c '
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
      else
        echo \"Failed to start SVN service\"
        exit 1
      fi
    '
  "
  
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

echo "🔧 Starting SVN user configuration..."

# Process Users
# ------------
# Add each user in the USERNAMES array
USER_ADDED=false
for USERNAME in "${USERNAMES[@]}"; do
  echo "----------------------------------------"
  echo "🔧 Processing user: $USERNAME"
  
  # Add user to SVN
  add_user_to_svn "$USERNAME"
  RESULT=$?
  
  if [ "$RESULT" -eq 0 ]; then
    USER_ADDED=true
    echo "✨ User added successfully"
  elif [ "$RESULT" -eq 2 ]; then
    echo "✨ User already exists, no changes needed"
  else
    echo "❌ Failed to process user"
  fi
  
  echo "✨ Done for $USERNAME"
  echo "----------------------------------------"
done

# Service Restart
# -------------
# Restart SVN service only if changes were made
if [ "$USER_ADDED" = "true" ]; then
  echo "🔧 Changes detected, restarting SVN service..."
  restart_svn_service
else
  echo "ℹ️ No changes were made, skipping service restart"
fi

echo "🎉 SVN user configuration completed" 
