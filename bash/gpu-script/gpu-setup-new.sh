#!/bin/bash

## Configuration Variables
NFS_SERVER_IP="10.77.101.25"
NFS_SHARE_PATH="/nfs/application"
MOUNT_POINT="/home/somaz/application"
CUDA_VERSION="cuda-11-8"
CUDA_TOOLKIT="cuda-toolkit-11-8"
NVIDIA_DRIVER="nvidia-driver-550"
CUDNN_URL="https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz"
CUDA_PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin"
CUDA_KEY_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub"
CUDA_REPO="deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"

## Install Standard Package ##
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl wget git python3 python3-venv python3-pip python3-tk libgl1 libglib2.0-0

# Check and install nfs-common if not installed
if ! dpkg -l | grep -qw nfs-common; then
    echo "Installing nfs-common..."
    sudo apt-get install -y nfs-common
    sleep 1
fi

# Wait for the network to be up
while ! ping -c 1 -W 1 $NFS_SERVER_IP; do
    echo "Waiting for $NFS_SERVER_IP - network interface might be down..."
    sleep 1
done

## Mount Setting ##
if ! mount | grep -q "$MOUNT_POINT"; then
    echo "Mounting NFS share..."
    mkdir -p $MOUNT_POINT
    sudo mount -t nfs $NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT
    # Add to fstab if not already present
    if ! grep -q "$NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT nfs" /etc/fstab; then
        echo "$NFS_SERVER_IP:$NFS_SHARE_PATH $MOUNT_POINT nfs defaults 0 0" | sudo tee -a /etc/fstab
    fi
else
    echo "NFS share is already mounted."
fi

## Install Nvidia-driver, CUDA, and cuDNN if not already installed
if ! nvidia-smi &gt; /dev/null 2&gt;&amp;1; then
    echo "Installing NVIDIA driver..."
    sudo apt-get install -y ubuntu-drivers-common $NVIDIA_DRIVER
fi

## Install CUDA
if ! nvcc --version &gt; /dev/null 2&gt;&amp;1; then
    echo "Installing CUDA..."
    wget $CUDA_PIN_URL
    sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
    sudo apt-key adv --fetch-keys $CUDA_KEY_URL
    sudo add-apt-repository "$CUDA_REPO" -y
    sudo apt-get update -y
    sudo apt-get install -y $CUDA_VERSION $CUDA_TOOLKIT
    echo '##cuda##' &gt;&gt; $MOUNT_POINT/.bashrc
    echo 'export PATH=/usr/local/cuda/bin:$PATH' &gt;&gt; $MOUNT_POINT/.bashrc
fi

# Check for cuDNN
if [ ! -f "/usr/include/cudnn.h" ]; then
    echo "Installing cuDNN..."
    wget $CUDNN_URL
    tar xvf cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz
    sudo cp -P cudnn-linux-x86_64-8.6.0.163_cuda11-archive/include/cudnn*.h /usr/include/
    sudo cp -P cudnn-linux-x86_64-8.6.0.163_cuda11-archive/lib/libcudnn* /usr/lib/x86_64-linux-gnu/
    sudo chmod a+r /usr/include/cudnn*.h /usr/lib/x86_64-linux-gnu/libcudnn*
    sudo ldconfig
    rm cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz
    rm -r cudnn-linux-x86_64-8.6.0.163_cuda11-archive
fi

# Setting Env
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
