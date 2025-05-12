#!/bin/bash

# Script Purpose
# -------------
# This script restarts all Stable Diffusion WebUI instances across available GPUs
# Each instance runs on a different GPU with a unique port number

# Initial Message
# -------------
# Display script execution start message
echo "Stable Diffusion WebUI 인스턴스 재시작 스크립트 실행 중..."

# Process Cleanup
# -------------
# Kill all existing Python processes to ensure clean restart
# This prevents port conflicts and ensures fresh instances
echo "모든 Python 프로세스 종료 중..."
ps aux | grep python3 | grep -v grep | awk '{print $2}' | xargs kill -9

# Wait for processes to fully terminate
# This delay ensures all processes are properly cleaned up
sleep 5

# GPU Detection
# ------------
# Count the number of available NVIDIA GPUs
# This determines how many instances we'll start
gpu_count=$(nvidia-smi -L | wc -l)

# Port Configuration
# ----------------
# Set the starting port number for the first instance
# Each subsequent instance will use an incremented port
start_port=7860

# Instance Creation Loop
# --------------------
# Iterate through each available GPU
# Create a new Stable Diffusion instance for each GPU
for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # Log File Setup
    # -------------
    # Create a unique log file name for each instance
    # Format: nohup_[port_number].out
    nohup_file="nohup_${start_port}.out"

    # Log File Cleanup
    # --------------
    # Remove existing log file if present
    # This prevents log file size issues and ensures clean logs
    if [[ -f $nohup_file ]]; then
        echo "기존 로그 파일 ${nohup_file} 삭제 중..."
        rm $nohup_file
    fi

    # Instance Launch
    # -------------
    # Start a new Stable Diffusion instance with specific configurations:
    # - CUDA_VISIBLE_DEVICES: Assigns the instance to a specific GPU
    # - --listen: Enables network access to the WebUI
    # - --port: Assigns a unique port number
    # - nohup: Runs the process in the background
    # - Output redirection: Captures all output in the log file
    echo "GPU ${gpu} 에서 포트 ${start_port} 로 Stable Diffusion WebUI 인스턴스 실행 중..."
    CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh --listen --port $start_port > $nohup_file 2>&1 &

    # Port Increment
    # ------------
    # Increment the port number for the next instance
    # Ensures each instance has a unique port
    ((start_port++))
done

# Completion Message
# ----------------
# Notify user that all instances have been restarted
echo "모든 Stable Diffusion WebUI 인스턴스가 재시작되었습니다."
