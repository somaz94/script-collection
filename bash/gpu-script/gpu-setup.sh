#!/bin/bash

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
while ! ping -c 1 -W 1 10.77.101.25; do
    echo "Waiting for 10.77.101.25 - network interface might be down..."
    sleep 1
done

# NFS Mount Configuration
# ---------------------
# Mount NFS share if not already mounted
if ! mount | grep -q '/home/somaz/application'; then
    echo "Mounting NFS share..."
    mkdir -p /home/somaz/application
    sudo mount -t nfs 10.77.101.25:/nfs/application /home/somaz/application
    # Add to fstab for persistent mounting
    if ! grep -q '10.77.101.25:/nfs/application /home/somaz/application nfs' /etc/fstab; then
        echo "10.77.101.25:/nfs/application /home/somaz/application nfs defaults 0 0" | sudo tee -a /etc/fstab
    fi
else
    echo "NFS share is already mounted."
fi

# NVIDIA Driver Installation
# ------------------------
# Install NVIDIA driver if not already installed
if ! nvidia-smi > /dev/null 2>&1; then
    echo "Installing NVIDIA driver..."
    sudo apt-get update -y
    sudo apt-get install -y ubuntu-drivers-common 
    sudo apt-get install -y nvidia-driver-550
fi

# CUDA Installation
# ---------------
# Install CUDA toolkit if not already installed
if ! nvcc --version > /dev/null 2>&1; then
    echo "Installing CUDA..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
    sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
    sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub
    sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /" -y
    sudo apt-get update -y
    sudo apt-get install -y cuda-11-8 cuda-toolkit-11-8 
    echo '##cuda##' >> /home/somaz/.bashrc
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /home/somaz/.bashrc
fi

# cuDNN Installation
# ----------------
# Install cuDNN if not already installed
if [ ! -f "/usr/include/cudnn.h" ]; then
    echo "Installing cuDNN..."
    wget https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz
    tar xvf cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz
    sudo cp -P cudnn-linux-x86_64-8.6.0.163_cuda11-archive/include/cudnn*.h /usr/include/
    sudo cp -P cudnn-linux-x86_64-8.6.0.163_cuda11-archive/lib/libcudnn* /usr/lib/x86_64-linux-gnu/
    sudo chmod a+r /usr/include/cudnn*.h /usr/lib/x86_64-linux-gnu/libcudnn*
    sudo ldconfig
    rm cudnn-linux-x86_64-8.6.0.163_cuda11-archive.tar.xz
    rm -r cudnn-linux-x86_64-8.6.0.163_cuda11-archive
fi

# Environment Setup
# --------------
# Set CUDA paths in environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# System Verification
# ----------------
# Check and record GPU and CUDA versions
echo "Checking GPU version..." > /home/somaz/application/gpu_check.txt
sudo nvidia-smi >> /home/somaz/application/gpu_check.txt
echo "" >> /home/somaz/application/gpu_check.txt

echo "Checking CUDA version..." >> /home/somaz/application/gpu_check.txt
/usr/local/cuda/bin/nvcc --version >> /home/somaz/application/gpu_check.txt
echo "" >> /home/somaz/application/gpu_check.txt

# cuDNN Verification
# ----------------
# Create and compile a test program to verify cuDNN installation
cat <<'EOF_SCRIPT' > /home/somaz/application/cudnn_test.cpp
#include <cudnn.h>
#include <iostream>

int main() {
    cudnnHandle_t cudnn;
    cudnnCreate(&cudnn);
    std::cout << "CuDNN version: " << CUDNN_VERSION << std::endl;
    cudnnDestroy(cudnn);
    return 0;
}
EOF_SCRIPT

# Compile and run cuDNN test
nvcc -o /home/somaz/application/cudnn_test /home/somaz/application/cudnn_test.cpp -lcudnn

# Verify cuDNN test results
echo "Checking if the compiled CuDNN test executable exists, then running it..." >> /home/somaz/application/gpu_check.txt
if [ -f "/home/somaz/application/cudnn_test" ]; then
    /home/somaz/application/cudnn_test >> /home/somaz/application/gpu_check.txt
else
    echo "CuDNN test executable not found." >> /home/somaz/application/gpu_check.txt
fi

# Stable Diffusion Setup
# -------------------
# Start Stable Diffusion WebUI instances for each available GPU
echo "Starting Stable Diffusion WebUI instances..."

# Navigate to Stable Diffusion WebUI directory
cd /home/somaz/application/stable-diffusion-webui || exit

# Calculate number of available GPUs
gpu_count=$(nvidia-smi -L | wc -l)

# Set initial port number for WebUI instances
start_port=7861

# Launch WebUI instance for each GPU
for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # Set log file for current instance
    nohup_file="/home/somaz/application/stable-diffusion-webui/nohup_${start_port}.out"

    # Launch WebUI instance with GPU-specific settings
    echo "Launching Stable Diffusion WebUI instance on GPU ${gpu} at port ${start_port}..."
    sudo -u somaz sh -c "CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh --listen --port $start_port > $nohup_file 2>&1 &"

    # Increment port number for next instance
    ((start_port++))
done

echo "All Stable Diffusion WebUI instances have been started."

