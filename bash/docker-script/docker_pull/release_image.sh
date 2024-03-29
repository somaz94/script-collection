#! /usr/bin/env bash

#image 변수
tag=""
harbor=""

####환경변수
zone=$(pwd)
relese_chart=$(cat $zone/relese_chart.txt)

####각 디렉토리 생성
mkdir -p $zone/image/$tag

#### relese image 수집
cd $zone/image/$tag
for image in $relese_chart
do
sudo docker pull $harbor/$image:$tag
echo $image >> commitid.txt
sudo docker inspect $harbor/$image:$tag |grep -i git_commit >> commitid.txt
sudo docker save -o $image.tar $harbor/$image:$tag
done
