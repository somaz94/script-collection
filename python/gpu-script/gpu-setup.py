import os
import subprocess
import requests
import tarfile

# Configuration variables
watch_dir = '/root/somaz'
sync_target_dir = '/data/local-somaz/'
log_file_path = '/root/sync-script/sync.log'
nfs_server_ip = '10.77.101.25'
nfs_share_path = '/nfs/application'
mount_point = '/home/somaz/application'
nvidia_driver_package = 'nvidia-driver-550'
cuda_toolkit_version = 'cuda-11-8'
cuda_repository_key_url = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub'
cuda_repository = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/'
cuda_pin_file_url = 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin'
cudnn_archive_url = 'https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86-64-8.6.0.163_cuda11-archive.tar.xz'

def log_message(message):
    """ Log messages to the specified log file. """
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file_path, 'a') as log_file:
        log_file.write(f"[{current_time}] {message}\n")

def install_nvidia_cuda():
    """ Install NVIDIA drivers and CUDA toolkit. """
    if subprocess.run(['nvidia-smi'], stdout=subprocess.DEVNULL).returncode != 0:
        print("Installing NVIDIA driver...")
        subprocess.run(['sudo', 'apt-get', 'install', '-y', nvidia_driver_package])

    if subprocess.run(['nvcc', '--version'], stdout=subprocess.DEVNULL).returncode != 0:
        print("Installing CUDA...")
        # Download and apply the CUDA repository pin
        r = requests.get(cuda_pin_file_url)
        with open('cuda-repository-pin-600', 'wb') as f:
            f.write(r.content)
        subprocess.run(['sudo', 'mv', 'cuda-repository-pin-600', '/etc/apt/preferences.d/'])
        
        # Add CUDA repository
        subprocess.run(['sudo', 'apt-key', 'adv', '--fetch-keys', cuda_repository_key_url])
        subprocess.run(['sudo', 'add-apt-repository', f"deb {cuda_repository} /", '-y'])
        subprocess.run(['sudo', 'apt-get', 'update'])
        subprocess.run(['sudo', 'apt-get', 'install', '-y', cuda_toolkit_version])

def install_cudnn():
    """ Install NVIDIA cuDNN libraries. """
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
        subprocess.run(['sudo', 'cp', '-P', './cudnn/cuda/include/cudnn*.h', '/usr/include/'])
        subprocess.run(['sudo', 'cp', '-P', './cudnn/cuda/lib64/libcudnn*', '/usr/lib/x86_64-linux-gnu/'])
        subprocess.run(['sudo', 'chmod', 'a+r', '/usr/include/cudnn*.h', '/usr/lib/x86_64-linux-gnu/libcudnn*'])
        subprocess.run(['sudo', 'ldconfig'])
        
        # Clean up the downloaded and extracted files
        os.remove('cudnn.tar.xz')
        shutil.rmtree('./cudnn')

def main():
    """ Main function to install packages and configure settings. """
    install_packages()
    check_network_and_mount()
    install_nvidia_cuda()
    install_cudnn()

if __name__ == "__main__":
    main()
