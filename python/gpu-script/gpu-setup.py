#!/usr/bin/env python3

# GPU Setup and Configuration Script
# -------------------------------
# This script automates the installation and configuration of NVIDIA GPU drivers,
# CUDA toolkit, and cuDNN libraries. It also handles NFS mounting and logging.

import os
import subprocess
import requests
import tarfile
import shutil
from datetime import datetime

# Configuration Variables
# ---------------------
# Directory and file paths for monitoring and logging
watch_dir = '/root/somaz'                    # Directory to monitor for changes
sync_target_dir = '/data/local-somaz/'       # Target directory for synchronization
log_file_path = '/root/sync-script/sync.log' # Path for log file

# NFS Configuration
# ---------------
# Network File System settings for mounting shared storage
nfs_server_ip = '10.77.101.25'              # NFS server IP address
nfs_share_path = '/nfs/application'         # NFS share path on server
mount_point = '/home/somaz/application'     # Local mount point

# NVIDIA Driver Configuration
# ------------------------
# Settings for NVIDIA driver installation
nvidia_driver_package = 'nvidia-driver-550'  # NVIDIA driver package name

# CUDA Configuration
# ----------------
# Settings for CUDA toolkit installation
cuda_toolkit_version = 'cuda-11-8'          # CUDA toolkit version
cuda_repository_key_url = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub'
cuda_repository = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/'
cuda_pin_file_url = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin'

# cuDNN Configuration
# ----------------
# Settings for cuDNN library installation
cudnn_archive_url = 'https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86-64-8.6.0.163_cuda11-archive.tar.xz'

def log_message(message):
    """Log messages to the specified log file with timestamp.
    
    Args:
        message (str): Message to be logged
    """
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file_path, 'a') as log_file:
        log_file.write(f"[{current_time}] {message}\n")

def install_nvidia_cuda():
    """Install NVIDIA drivers and CUDA toolkit.
    
    This function checks for existing installations and installs:
    - NVIDIA drivers if not present
    - CUDA toolkit if not present
    - Required repository keys and configurations
    """
    # Check and install NVIDIA driver if not present
    if subprocess.run(['nvidia-smi'], stdout=subprocess.DEVNULL).returncode != 0:
        print("Installing NVIDIA driver...")
        subprocess.run(['sudo', 'apt-get', 'install', '-y', nvidia_driver_package])

    # Check and install CUDA toolkit if not present
    if subprocess.run(['nvcc', '--version'], stdout=subprocess.DEVNULL).returncode != 0:
        print("Installing CUDA...")
        # Download and apply the CUDA repository pin
        r = requests.get(cuda_pin_file_url)
        with open('cuda-repository-pin-600', 'wb') as f:
            f.write(r.content)
        subprocess.run(['sudo', 'mv', 'cuda-repository-pin-600', '/etc/apt/preferences.d/'])
        
        # Add CUDA repository and install toolkit
        subprocess.run(['sudo', 'apt-key', 'adv', '--fetch-keys', cuda_repository_key_url])
        subprocess.run(['sudo', 'add-apt-repository', f"deb {cuda_repository} /", '-y'])
        subprocess.run(['sudo', 'apt-get', 'update'])
        subprocess.run(['sudo', 'apt-get', 'install', '-y', cuda_toolkit_version])

def install_cudnn():
    """Install NVIDIA cuDNN libraries.
    
    This function:
    - Downloads cuDNN archive
    - Extracts and installs libraries
    - Sets appropriate permissions
    - Updates library cache
    - Cleans up temporary files
    """
    if not os.path.exists('/usr/include/cudnn.h'):
        print("Downloading cuDNN...")
        r = requests.get(cudnn_archive_url, stream=True)
        with open('cudnn.tar.xz', 'wb') as f:
            for chunk in r.iter_content(chunk_size=128):
                f.write(chunk)
        
        print("Extracting cuDNN...")
        with tarfile.open('cudnn.tar.xz', 'r:xz') as tar:
            tar.extractall(path='./cudnn')

        print("Installing cuDNN...")
        # Copy header files and libraries
        subprocess.run(['sudo', 'cp', '-P', './cudnn/cuda/include/cudnn*.h', '/usr/include/'])
        subprocess.run(['sudo', 'cp', '-P', './cudnn/cuda/lib64/libcudnn*', '/usr/lib/x86_64-linux-gnu/'])
        subprocess.run(['sudo', 'chmod', 'a+r', '/usr/include/cudnn*.h', '/usr/lib/x86_64-linux-gnu/libcudnn*'])
        subprocess.run(['sudo', 'ldconfig'])
        
        # Clean up temporary files
        os.remove('cudnn.tar.xz')
        shutil.rmtree('./cudnn')

def main():
    """Main function to install packages and configure settings.
    
    This function orchestrates the entire setup process:
    1. Installs required packages
    2. Checks network and mounts NFS
    3. Installs NVIDIA drivers and CUDA
    4. Installs cuDNN libraries
    """
    install_packages()
    check_network_and_mount()
    install_nvidia_cuda()
    install_cudnn()

if __name__ == "__main__":
    main()
