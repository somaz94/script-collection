#!/bin/bash

version=16.3.4-ce.0  # write your update version

# # 백업 생성 (선택적)
# echo "Creating backup before upgrade..."
# sudo gitlab-rake gitlab:backup:create

# 현재 버전 확인
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

# 업그레이드 후 상태 확인
echo "Checking GitLab status..."
sudo gitlab-ctl status

# 업그레이드 후 버전 확인
echo "New GitLab version"
sudo gitlab-rake gitlab:env:info

echo "Upgrade completed"
