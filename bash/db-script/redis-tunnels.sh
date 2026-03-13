#!/bin/bash

# Start first tunnel
/usr/bin/ssh -N -i /home/ec2-user/.ssh/id_rsa \
    -L 0.0.0.0:<Used Port>:<Redis Endpoint>:6379 \
    ec2-user@<VM Private IP> &

# Start second tunnel
/usr/bin/ssh -N -i /home/ec2-user/.ssh/id_rsa \
    -L 0.0.0.0:<Used Port>:<Redis Endpoint>::6379 \
    ec2-user@<VM Private IP> &

wait
