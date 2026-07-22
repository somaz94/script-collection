#!/bin/bash

set -euo pipefail # stop fail

version=19.1.2-ce.0

echo "Upgrading to GitLab $version"
apt-get update
apt-get install -y gitlab-ce=$version
gitlab-ctl reconfigure     
gitlab-ctl restart
gitlab-ctl status
