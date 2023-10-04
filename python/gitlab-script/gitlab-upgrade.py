import os
import time

version = "16.3.4-ce.0"  # write your update version

print("Upgrading to GitLab {}".format(version))
os.system("sudo apt update")
os.system("sudo apt-get install -y gitlab-ce={}".format(version))
time.sleep(10)
os.system("sudo gitlab-ctl reconfigure")
time.sleep(10)
os.system("sudo gitlab-ctl restart")
time.sleep(10)

print("Upgrade completed")
