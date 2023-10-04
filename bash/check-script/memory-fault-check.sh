#!/bin/bash
  
set -x
  
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash
 
M="hardware"
F="dimm"
 
C=`sudo cat /var/log/messages |grep -i $M |grep -i $F |wc -l`
 
MAILTO=(
"메일주소 추가"
)
 
 
if [ $C -ge 1 ]; then
  echo "Memory Fault log found." | \
  mail -s "[Site name] Memory Fault log found" \
  "${MAILTO[@]}"
fi
