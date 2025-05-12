#!/usr/bin/env python3

# GitLab Upgrade Script
# -------------------
# This script automates the process of upgrading GitLab to a specified version.
# It handles package updates, installation, and service reconfiguration.

import os
import time

# Target GitLab version for upgrade
version = "16.3.4-ce.0"  # write your update version

print("Upgrading to GitLab {}".format(version))

# Update package lists
os.system("sudo apt update")

# Install specific GitLab version
os.system("sudo apt-get install -y gitlab-ce={}".format(version))

# Wait for installation to complete
time.sleep(10)

# Reconfigure GitLab with new version
os.system("sudo gitlab-ctl reconfigure")
time.sleep(10)

# Restart GitLab services
os.system("sudo gitlab-ctl restart")
time.sleep(10)

print("Upgrade completed")
