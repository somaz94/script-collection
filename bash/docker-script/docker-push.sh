#!/bin/sh

set -ex

# Write TAG
NEW_TAG=""

# Write Registry
LOCAL_REGI=""

cat /dev/null > load-image_list

# Image load
TARS=$(ls *.tar)
for TAR in ${TARS}
do
    sudo docker load < ${TAR} | grep -i 'loaded image' | awk '{print $3}' >> load-image_listdone

# Image Tag, Push, Clean
for IMAGE in `cat load-image_list`
do
    echo $IMAGE
    NEW_IMAGE=$(echo $IMAGE | sed 's/^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\///g' | awk -F : '{print $1}')

#    echo $NEW_IMAGE
    sudo docker tag $IMAGE $LOCAL_REGI/$NEW_IMAGE:$NEW_TAG

#    echo "sudo docker tag $IMAGE $LOCAL_REGI/$NEW_IMAGE:$NEW_TAG"
    sudo docker push $LOCAL_REGI/$NEW_IMAGE:$NEW_TAG || continue

    sudo docker rmi $IMAGE || continue
    sleep 1
    sudo docker rmi $LOCAL_REGI/$NEW_IMAGE:$NEW_TAG || continue

done

# prometheus image
sudo docker load < prometheus.tar
sudo docker tag quay.io/prometheus/prometheus:v2.10.0 ${LOCAL_REGI}/quay.io/prometheus/prometheus:v2.10.0
sudo docker push ${LOCAL_REGI}/quay.io/prometheus/prometheus:v2.10.0
sudo docker rmi quay.io/prometheus/prometheus:v2.10.0
sudo docker rmi ${LOCAL_REGI}/quay.io/prometheus/prometheus:v2.10.0
