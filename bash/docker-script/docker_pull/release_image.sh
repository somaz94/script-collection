#! /usr/bin/env bash

# Image variables
tag=""
harbor=""

# Environment variables
zone=$(pwd)
relese_chart=$(cat $zone/relese_chart.txt)

# Create directory for images
mkdir -p $zone/image/$tag

# Collect release images
cd $zone/image/$tag
for image in $relese_chart
do
sudo docker pull $harbor/$image:$tag
echo $image >> commitid.txt
sudo docker inspect $harbor/$image:$tag |grep -i git_commit >> commitid.txt
sudo docker save -o $image.tar $harbor/$image:$tag
done
