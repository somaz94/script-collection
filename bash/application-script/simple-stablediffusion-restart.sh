#!/bin/bash

# GPU Detection
# ------------
# Count the number of available NVIDIA GPUs
# This determines how many Stable Diffusion instances we'll start
gpu_count=$(nvidia-smi -L | wc -l)

# Port Configuration
# ----------------
# Set the starting port number for the first instance
# Each subsequent instance will use an incremented port
start_port=7861

# Instance Creation Loop
# --------------------
# Iterate through each available GPU
# Create a new Stable Diffusion instance for each GPU
for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # Log File Setup
    # -------------
    # Create a unique log file name for each instance
    # Format: ai_nohup_[port_number].out
    nohup_file="/data/ai/stable-diffusion-webui/ai_nohup_${start_port}.out"

    # Instance Launch
    # -------------
    # Start a new Stable Diffusion instance with specific configurations:
    # - CUDA_VISIBLE_DEVICES: Assigns the instance to a specific GPU
    # - -f: Force restart
    # - --listen: Enables network access to the WebUI
    # - --port: Assigns a unique port number
    # - --api: Enables API access
    # - --disable-safe-unpickle: Disables safe unpickling
    # - --xformers: Enables xformers optimization
    # - --medvram: Uses medium VRAM optimization
    # - --no-half-vae: Disables half precision for VAE
    # - --enable-insecure-extension-access: Allows insecure extension access
    # - --skip-torch-cuda-test: Skips CUDA compatibility test
    echo "Launching Stable Diffusion WebUI instance on GPU ${gpu} at port ${start_port}..."
    sudo -u root sh -c "CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh -f --listen --port $start_port --api --disable-safe-unpickle --xformers --medvram --no-half-vae --enable-insecure-extension-access --skip-torch-cuda-test  > $nohup_file 2>&1 &"

    # Port Increment
    # ------------
    # Increment the port number for the next instance
    # Ensures each instance has a unique port
    ((start_port++))
done

# Completion Message
# ----------------
# Notify user that all instances have been started
echo "All Stable Diffusion WebUI instances have been started."
