#!/bin/bash
## Install Standard Package ##
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl wget git python3 python3-venv python3-pip python3-tk libgl1 libglib2.0-0

# Check if nfs-common is installed
if ! dpkg -l | grep -qw nfs-common; then
    echo "Installing nfs-common..."
    sudo apt-get install -y nfs-common
    sleep 1
fi

# Wait for the network to be up before attempting to mount
while ! ping -c 1 -W 1 10.77.101.25; do
    echo "Waiting for 10.77.101.25 - network interface might be down..."
    sleep 1
done

## Mount Setting ##
if ! mount | grep -q '/home/somaz/application'; then
    echo "Mounting NFS share..."
    mkdir -p /home/somaz/application
    sudo mount -t nfs 10.77.101.25:/nfs/application /home/somaz/application
    # Add to fstab if not already present to ensure re-mounting on reboot
    if ! grep -q '10.77.101.25:/nfs/application /home/somaz/application nfs' /etc/fstab; then
        echo "10.77.101.25:/nfs/application /home/somaz/application nfs defaults 0 0" | sudo tee -a /etc/fstab
    fi
else
    echo "NFS share is already mounted."
fi

## Install Nvidia-driver, CUDA, and cuDNN if not already installed
if ! nvidia-smi > /dev/null 2>&1; then
    echo "Installing NVIDIA driver..."
    sudo apt-get update -y
    sudo apt-get install -y ubuntu-drivers-common 
    sudo apt-get install -y nvidia-driver-550
fi

## Install Cuda
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

# Check for cuDNN
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

# Setting Env
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Checking GPU and CUDA version
echo "Checking GPU version..." > /home/somaz/application/gpu_check.txt
sudo nvidia-smi >> /home/somaz/application/gpu_check.txt
echo "" >> /home/somaz/application/gpu_check.txt # Add an empty line for spacing

echo "Checking CUDA version..." >> /home/somaz/application/gpu_check.txt
/usr/local/cuda/bin/nvcc --version >> /home/somaz/application/gpu_check.txt
echo "" >> /home/somaz/application/gpu_check.txt # Add another empty line for spacing


# Compiling and running the CuDNN test to verify CuDNN installation
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

nvcc -o /home/somaz/application/cudnn_test /home/somaz/application/cudnn_test.cpp -lcudnn

# Checking if the compiled executable exists, then running it
echo "Checking if the compiled CuDNN test executable exists, then running it..." >> /home/somaz/application/gpu_check.txt
if [ -f "/home/somaz/application/cudnn_test" ]; then
    /home/somaz/application/cudnn_test >> /home/somaz/application/gpu_check.txt
else
    echo "CuDNN test executable not found." >> /home/somaz/application/gpu_check.txt
fi

# Starting script message
echo "Starting Stable Diffusion WebUI instances..."

# Change directory to Stable Diffusion WebUI
cd /home/somaz/application/stable-diffusion-webui || exit

# Calculate the number of GPUs
gpu_count=$(nvidia-smi -L | wc -l)

# Initial port number for the instances
start_port=7861

for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # Set the name for the current GPU's nohup file
    nohup_file="/home/somaz/application/stable-diffusion-webui/nohup_${start_port}.out"

    # Set CUDA_VISIBLE_DEVICES to run an instance for each GPU
    echo "Launching Stable Diffusion WebUI instance on GPU ${gpu} at port ${start_port}..."
    sudo -u somaz sh -c "CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh --listen --port $start_port > $nohup_file 2>&1 &"

    # Update to the next port number
    ((start_port++))
done

echo "All Stable Diffusion WebUI instances have been started."

