#!/bin/bash

version=16.2.3-ce.0  # write your update version

echo "Upgrading to GitLab $version"

sudo apt-get install -y gitlab-ce=$version
sleep 10
sudo gitlab-ctl reconfigure
sleep 10
sudo gitlab-ctl restart
sleep 10

echo "Upgrade completed"
