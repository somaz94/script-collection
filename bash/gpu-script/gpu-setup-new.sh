#!/bin/bash

# Configuration Variables
# ---------------------
# NFS Configuration
NFS_SERVER_IP="10.77.101.25"        # IP address of the NFS server
NFS_SHARE_PATH="/nfs/application"   # Path to the shared directory on NFS server
MOUNT_POINT="/home/somaz/application" # Local mount point for NFS share

# CUDA Configuration
# ----------------
# Version specifications for NVIDIA components
CUDA_VERSION="cuda-11-8"            # CUDA version to install
CUDA_TOOLKIT="cuda-toolkit-11-8"    # CUDA toolkit version
NVIDIA_DRIVER="nvidia-driver-550"    # NVIDIA driver version
CUDNN_VERSION="8.6.0.163"           # cuDNN version
CUDNN_CUDA_VERSION="cuda11"         # cuDNN CUDA compatibility version

# Download URLs
# ------------
# URLs for downloading NVIDIA components
CUDNN_URL="https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-${CUDNN_VERSION}_${CUDNN_CUDA_VERSION}-archive.tar.xz"
CUDA_PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin"
CUDA_KEY_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub"
CUDA_REPO="deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"
CUDNN_ARCHIVE="cudnn-linux-x86_64-${CUDNN_VERSION}_${CUDNN_CUDA_VERSION}-archive"

# Package Installation
# ------------------
# Install standard system packages required for GPU setup
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl wget git python3 python3-venv python3-pip python3-tk libgl1 libglib2.0-0

# NFS Client Setup
# --------------
# Check and install nfs-common if not present
if ! dpkg -l | grep -qw nfs-common; then
    echo "Installing nfs-common..."
    sudo apt-get install -y nfs-common
    sleep 1
fi

# Network Connectivity Check
# ------------------------
# Wait for network connectivity to NFS server
while ! ping -c 1 -W 1 $NFS_SERVER_IP; do
    echo "Waiting for $NFS_SERVER_IP - network interface might be down..."
    sleep 1
done

# NFS Mount Configuration
# ---------------------
# Mount NFS share if not already mounted
if ! mount | grep -q "$MOUNT_POINT"; then
    echo "Mounting NFS share..."
    mkdir -p $MOUNT_POINT
    sudo mount -t nfs $NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT
    # Add to fstab for persistent mounting
    if ! grep -q "$NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT nfs" /etc/fstab; then
        echo "$NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT nfs defaults 0 0" | sudo tee -a /etc/fstab
    fi
else
    echo "NFS share is already mounted."
fi

# NVIDIA Driver Installation
# ------------------------
# Install NVIDIA driver if not already installed
if ! nvidia-smi > /dev/null 2>&1; then
    echo "Installing NVIDIA driver..."
    sudo apt-get install -y ubuntu-drivers-common $NVIDIA_DRIVER
fi

# CUDA Installation
# ---------------
# Install CUDA toolkit if not already installed
if ! nvcc --version > /dev/null 2>&1; then
    echo "Installing CUDA..."
    wget $CUDA_PIN_URL
    sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
    sudo apt-key adv --fetch-keys $CUDA_KEY_URL
    sudo add-apt-repository "$CUDA_REPO" -y
    sudo apt-get update -y
    sudo apt-get install -y $CUDA_VERSION $CUDA_TOOLKIT
    echo '##cuda##' >> $MOUNT_POINT/.bashrc
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> $MOUNT_POINT/.bashrc
fi

# cuDNN Installation
# ----------------
# Install cuDNN if not already installed
if [ ! -f "/usr/include/cudnn.h" ]; then
    echo "Installing cuDNN..."
    wget $CUDNN_URL
    tar xvf ${CUDNN_ARCHIVE}.tar.xz
    sudo cp -P ${CUDNN_ARCHIVE}/include/cudnn*.h /usr/include/
    sudo cp -P ${CUDNN_ARCHIVE}/lib/libcudnn* /usr/lib/x86_64-linux-gnu/
    sudo chmod a+r /usr/include/cudnn*.h /usr/lib/x86_64-linux-gnu/libcudnn*
    sudo ldconfig
    rm ${CUDNN_ARCHIVE}.tar.xz
    rm -r ${CUDNN_ARCHIVE}
fi

# Environment Setup
# --------------
# Set CUDA paths in environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
