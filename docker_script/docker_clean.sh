#!/bin/bash
 
#### docker exit process remove
echo "docker exit process remove"
sudo docker ps -a | grep Exit | cut -d ' ' -f 1 | xargs sudo docker rm
 
#### docker dangling image remove
echo "dangling image remove"
sudo docker rmi $(docker images --filter "dangling=true" -q --no-trunc)
