#!/bin/bash

# 스크립트 시작 메시지 출력
echo "Stable Diffusion WebUI 인스턴스 재시작 스크립트 실행 중..."

# 모든 Python 프로세스 종료
echo "모든 Python 프로세스 종료 중..."
ps aux | grep python3 | grep -v grep | awk '{print $2}' | xargs kill -9

# 잠시 대기 (필요 시 조정)
sleep 5

# GPU 개수 파악
gpu_count=$(nvidia-smi -L | wc -l)

# 인스턴스 및 포트 시작 번호
start_port=7860

for (( gpu=0; gpu<gpu_count; gpu++ ))
do
    # 현재 GPU에 대한 nohup 파일 이름 설정
    nohup_file="nohup_${start_port}.out"

    # 기존 nohup 파일이 있으면 삭제
    if [[ -f $nohup_file ]]; then
        echo "기존 로그 파일 ${nohup_file} 삭제 중..."
        rm $nohup_file
    fi

    # CUDA_VISIBLE_DEVICES를 설정하여 각 GPU에 인스턴스 실행
    echo "GPU ${gpu} 에서 포트 ${start_port} 로 Stable Diffusion WebUI 인스턴스 실행 중..."
    CUDA_VISIBLE_DEVICES=$gpu nohup ./webui.sh --listen --port $start_port > $nohup_file 2>&1 &

    # 다음 포트 번호로 업데이트
    ((start_port++))
done

echo "모든 Stable Diffusion WebUI 인스턴스가 재시작되었습니다."
