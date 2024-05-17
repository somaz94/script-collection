gpu_count=$(nvidia-smi -L | wc -l)

# Initial port number for the instances
start_port=7861

for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # Set the name for the current GPU's nohup file
    nohup_file="/data/ai/stable-diffusion-webui/ai_nohup_${start_port}.out"

    # Set CUDA_VISIBLE_DEVICES to run an instance for each GPU
    echo "Launching Stable Diffusion WebUI instance on GPU ${gpu} at port ${start_port}..."
    sudo -u root sh -c "CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh -f --listen --port $start_port --api --disable-safe-unpickle --xformers --medvram --no-half-vae --enable-insecure-extension-access --skip-torch-cuda-test  > $nohup_file 2>&1 &"

    # Update to the next port number
    ((start_port++))
done

echo "All Stable Diffusion WebUI instances have been started."
