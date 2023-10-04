#!/bin/bash

############ Hostname Process
echo "############ Hostname Process"
ps -ef|grep Hostname|grep -v grep
echo ""

############ CPU
echo "############ CPU"
echo -n "CPU Usage: "
top -b -n1 | grep -Po '[0-9.]+ id' | awk '{print 100-$1}'
echo ""

############ LOAD AVG
echo "############ LOAD AVG"
uptime | awk -F 'average:' '{printf"Load Average: %s",$2}'
echo ""
echo ""

############ Mem Usage
echo "############ Mem Usage"
free -h
#free -h|grep Mem|awk '{print "Toal: "$2 "\tUsed: " $3 "\tFree: " $4}'
echo ""

############ Disk Usage
echo "############ Disk Usage"
df -Th
echo ""

############ Network Usage
echo "########### Network Usage"
dstat -lcdngy 1 5
echo ""

############ Container Status
echo "########### Container Status"
sudo docker ps
echo ""

############ Hostname Status
echo "########### Hostname Status"
STATUS_CODE=$(curl -o /dev/null -w "%{http_code}" "http://Hostname URL")
if [ $STATUS_CODE == 200 ]; then
	echo ""
	echo "Hostname 200 OK"
fi
echo ""


