#!/usr/bin/env bash

# Email Configuration
# ----------------
# Set the recipient email address for notifications
recipient="somaz@gmail.com"

# Node Status Check
# --------------
# Get the status of nodes that are not ready
# Extract both the status and hostname of not ready nodes
STATE=$(kubectl get node |grep 'NotReady' |awk '{print $2}')
hostname=$(kubectl get node |grep 'NotReady' |awk '{print $1}')
name=$(hostname)
 
# Node Status Processing
# -------------------
# If any node is in NotReady state:
# 1. Create a notification file
# 2. Record the hostname and status
# 3. Send an email notification
# 4. Clean up the temporary file
if [ "${STATE}" == "NotReady" ];then
    # Create notification file
    touch /$HOME/monthly_maintenance/send_mail
    
    # Record node information
    echo "${hostname}" "${STATE}" >> /home/somaz/monthly_maintenance/send_mail
    
    # Send email notification
    # Note: Commented out alternative email sending method
    #echo "${STATE}" >> /home/somaz/monthly_maintenance/send_mail
    #sudo cat /home/somaz/monthly_maintenance/send_mail | sudo /usr/sbin/sendmail -s "Node NotReady"  ${recipient}
    sudo cat /$HOME/monthly_maintenance/send_mail | sudo mail -s "$(hostname) Node NotReady" ${recipient}
    
    # Cleanup
    sudo rm -f /$HOME/monthly_maintenance/send_mail
    exit 0
    echo ""
    exit 0
fi
