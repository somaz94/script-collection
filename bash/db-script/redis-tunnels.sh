#!/bin/bash

# 첫 번째 터널 실행
/usr/bin/ssh -N -i /home/ec2-user/.ssh/id_rsa \
    -L 0.0.0.0:<Used Port>:<Redis Endpoint>:6379 \
    ec2-user@<VM Private IP> &

# 두 번째 터널 실행
/usr/bin/ssh -N -i /home/ec2-user/.ssh/id_rsa \
    -L 0.0.0.0:<Used Port>:<Redis Endpoint>::6379 \
    ec2-user@<VM Private IP> &

wait
