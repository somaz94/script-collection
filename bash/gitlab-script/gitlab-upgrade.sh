#!/bin/bash

version=16.3.4-ce.0  # write your update version

# # Create backup (optional)
# echo "Creating backup before upgrade..."
# sudo gitlab-rake gitlab:backup:create

# Check current version
echo "Current GitLab version"
sudo gitlab-rake gitlab:env:info

echo "Upgrading to GitLab $version"
sudo apt update
sudo apt-get install -y gitlab-ce=$version
sleep 10
sudo gitlab-ctl reconfigure
sleep 10
sudo gitlab-ctl restart
sleep 10

# Check status after upgrade
echo "Checking GitLab status..."
sudo gitlab-ctl status

# Check version after upgrade
echo "New GitLab version"
sudo gitlab-rake gitlab:env:info

echo "Upgrade completed"
