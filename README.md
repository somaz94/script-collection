# �� Script Collection

This repository contains a comprehensive collection of scripts for managing various software components and systems. The scripts are organized by programming language and functionality.

<br/>

## 📂 Directory Structure

<br/>

### Bash Scripts (`/bash`)
- `application-script/` 📱 - Application management and deployment scripts
- `check-script/` ✅ - System health check and monitoring scripts
  - `monthly_maintenance_k8s_openstack_ceph/` - Monthly maintenance scripts for Kubernetes, OpenStack, and Ceph
- `db-script/` 🗃️ - Database management and maintenance scripts
  - `test/` - Database testing scripts
- `docker-script/` 🐳 - Docker container management scripts
  - `docker_pull/` - Docker image pull and management scripts
- `elastic-script/` 🔍 - Elasticsearch management scripts
- `gcs-script/` ☁️ - Google Cloud Storage management scripts
- `gitlab-script/` 🦊 - GitLab CI/CD and management scripts
- `gpu-script/` 🎮 - GPU setup and management scripts
- `jenkins-script/` 🌟 - Jenkins pipeline and management scripts
  - `monthly_maintenance/` - Monthly Jenkins maintenance scripts
- `k8s-script/` ☸️ - Kubernetes management scripts
- `kubernetes-script/` ☸️ - Additional Kubernetes utilities
- `linux-script/` 🐧 - Linux system management scripts
  - `debian-ubuntu/` - Debian/Ubuntu specific scripts
  - `rhel-centos-rocky/` - RHEL/CentOS/Rocky Linux specific scripts
- `nas-script/` 💾 - NAS (Network Attached Storage) management scripts
- `openstack-script/` 🌩️ - OpenStack cloud management scripts
- `svn-script/` 📦 - SVN repository management scripts
- `sync-script/` 🔄 - File synchronization scripts

<br/>

### Go Scripts (`/go`)
- `elastic-script/` 🔍 - Elasticsearch management utilities
- `kubernetes-script/` ☸️ - Kubernetes management utilities
  - `check-node-resource/` - Node resource monitoring
  - `check-node-resources/` - Extended node resource checks
  - `check-pod-resource/` - Pod resource monitoring
  - `multi-list-pod-on-node/` - Multi-node pod listing utility

<br/>

### Python Scripts (`/python`)
- `db-script/` 🗃️ - Database management utilities
- `elastic-script/` 🔍 - Elasticsearch management utilities
- `gitlab-script/` 🦊 - GitLab automation utilities
- `gpu-script/` 🎮 - GPU management utilities
- `linux-script/` 🐧 - Linux system management utilities
  - `debian-ubuntu/` - Debian/Ubuntu specific utilities
  - `rhel-centos-rocky/` - RHEL/CentOS/Rocky Linux specific utilities
- `sync-rsync-differ-script/` 🔄 - Rsync-based synchronization utilities
- `sync-script/` 🔄 - General synchronization utilities

<br/>

## 📘 Usage Notes
- Each script directory contains specific utilities for its respective technology
- Scripts are organized by technology and operating system where applicable
- Detailed usage instructions and documentation are available within each script
- Some scripts may require specific permissions or environment setup

<br/>

## 🔧 Requirements
- Bash scripts require a Unix-like environment
- Go scripts require Go 1.x or later
- Python scripts require Python 3.x
- Additional requirements are specified in individual script files

<br/>

## 📝 Contributing
Please ensure to:
1. Add appropriate comments and documentation
2. Test scripts in relevant environments
3. Follow existing naming conventions
4. Update this README when adding new directories or major changes

