#!/usr/bin/env bash


############ OpenStack env
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=somaz
export OS_AUTH_URL=http://keystone.openstack.svc.cluster.local:8080/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2


############ 지역변수 선언
echo "daily-csv-"$(date +"%Y-%m-%d_%Hh_%Mm.txt") > /tmp/daily-checklist-D1
echo $(date +"%Y-%m") > /tmp/daily-checklist-D2
DATE1=$(cat /tmp/daily-checklist-D1)
DATE2=$(cat /tmp/daily-checklist-D2)
scpath="/home/somaz/monthly_maintenance/"
hyplist=$(/usr/bin/openstack hypervisor list | awk 'NR>3 {print $4}')
kubenss=$(/usr/local/bin/kubectl get ns | awk 'NR > 1 {print $1}')


############ 환경별 변수
servlist=$(cat /home/somaz/monthly_maintenance/serverlist.txt)
cephmaster=r-ceph-farm-01


############ 하위디렉토리 생성
mkdir -p $scpath/$DATE2


############ CPU, MEM, root disk 수집
rm -f /tmp/serverstats
for serv in $servlist; do
  ssh $serv $'\
  vmstat 1 2 | awk -v hostname=$HOSTNAME \'NR==4 {printf "%-25s CPU Usage = %.2f % \tContext Switch = %-10s",hostname,$13,$12}\' ; \
  uptime | awk -F \'average:\' \'{printf"load average: %s\\n",$2}\' ; \
  free | grep Mem | awk -v hostname=$HOSTNAME \'{ printf("%-25s Mem Total(GB): %-10.0f Mem Used(GB): %-10.0f Mem Used(%): %.2f %\\n",hostname,$2/1024/1024,$3/1024/1024, $3/$2*100.0) }\' ; \
  df -h / | tail -1 | awk -v hostname=$HOSTNAME \'{printf "%-20s\t%s\t%s\t%s\t%s\\n",hostname,$2,$3,$4,$5}\' ' >> /tmp/serverstats
done

############ CPU
echo "############ CPU"
cat /tmp/serverstats | grep CPU
echo ""

############ MEM
echo "############ MEM"
cat /tmp/serverstats | grep Mem
echo ""


############ 각edu-control-01ing 중인 VM 수 확인
echo "############ 각 노드별 Running 중인 VM 수 확인"
rm -f /tmp/opst_running_vms
for hyp in $hyplist; do
  /usr/bin/nova list --all --host=$hyp | grep Running | wc -l | awk -v hypname=$hyp '{printf "%-20s running VMs = %s\n",hypname,$1}' >> /tmp/opst_running_vms
done
cat /tmp/opst_running_vms | sort -k1
echo ""


############ ceph 사용량 확인
echo "############ ceph 사용량 확인"
ssh $cephmaster "sudo ceph df"
echo ""


############ nova, nova2의 current_subscription_ratio
#echo "############ nova, nova2의 current_subscription_ratio"
#echo "### nova current_subscription_ratio / max_over_subscription_ratio"
#printf "%s / %s\n" $(expr $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs1 | grep provisioned_capacity_gb | tail -1 | awk -F "provisioned_capacity_gb: " '{print $2}' | awk -F',' '{print $1}') / $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs1 | awk -F "total_capacity_gb': " '{print $2}' | tail -1 | awk -F'.' '{print $1}')) $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs1 | awk -F "max_over_subscription_ratio': " '{print $2}' | tail -1 | awk -F'.' '{print $1}')
#echo "### nova2 current_subscription_ratio / max_over_subscription_ratio"
#printf "%s / %s\n" $(expr $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs2 | grep provisioned_capacity_gb | tail -1 | awk -F "provisioned_capacity_gb: " '{print $2}' | awk -F',' '{print $1}') / $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs2 | awk -F "total_capacity_gb': " '{print $2}' | tail -1 | awk -F'.' '{print $1}')) $(/usr/local/bin/kubectl -n openstack logs $(/usr/local/bin/kubectl -n openstack get po -o wide | grep cinder-scheduler | head -1 | awk '{print $1}') | grep nfs2 | awk -F "max_over_subscription_ratio': " '{print $2}' | tail -1 | awk -F'.' '{print $1}')
#echo ""


############ Storage별 사용량(간략)
echo "############ Storage별 사용량(간략)"
echo "### ceph"
ssh $cephmaster "sudo ceph df" | awk 'NR==3{printf"%s/%s (%s%)\n",$3,$1,$4}'
echo ""
#echo "### NetApp nova volume"
#ssh viewonly@$netappIP volume show -fields size,used,available,percent-used | grep nova | awk '{printf"%s vol : %s/%s (%s)\n",$2,$5,$3,$6}'
#echo ""


############ 가장 큰 osd의 사용량
echo "############ 가장 큰 osd의 사용량"
ssh $cephmaster "sudo ceph osd df" | egrep -v 'VAR|TOTAL' | sort -rnk8 | awk 'NR==1 {printf "Largest osd usage = %s %\n",$8}'
echo ""


############ ceph 상태 확인
echo "############ ceph 상태 확인"
ssh $cephmaster "sudo ceph health detail"
echo ""


############ osd 사용량
echo "############ osd 사용량"
ssh $cephmaster "sudo ceph osd df" | egrep -v 'VAR|TOTAL' | sort -rnk8 | awk '{printf "osd ID %-2s = %s %\n",$1,$8}'
echo ""


############ NetApp volume 사용량
#echo "############ NetApp volume 사용량"
#ssh viewonly@$netappIP volume show -fields size,used,available,percent-used | grep 'available\|nova' | awk '{printf "%-10s %-10s %-10s %-10s %s\n",$2,$3,$4,$5,$6}'
#echo ""


############ host local root disk usage
echo "############ host local root disk usage"
df -h | head -1 | awk '{printf "%-20s\t%s\t%s\t%s\t%s\n","hostname",$2,$3,$4,$5}'
cat /tmp/serverstats | grep -v 'CPU\|Mem' | sort -rnk5
echo ""

############ CloudPC app-db PVC usage
echo "############ CloudPC app-db PVC usage"
appdbs=$(/usr/local/bin/kubectl -n cloudpc get po | grep app-db-'[0-9]' | awk '{print $1}')
printf "%-20s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for appdb in $appdbs; do
  /usr/local/bin/kubectl -n cloudpc exec $appdb -- df -h /var/lib/mysql | awk -v hostname=$appdb 'NR==2{printf"%-20s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""


############ Openstack mariadb PVC usage
echo "############ Openstack mariadb PVC usage"
mariadbs=$(/usr/local/bin/kubectl -n openstack get po | grep mariadb-server-'[0-9]' | awk '{print $1}')
printf "%-20s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for mariadb in $mariadbs; do
  /usr/local/bin/kubectl -n openstack exec $mariadb -- df -h /var/lib/mysql | awk -v hostname=$mariadb 'NR==2{printf"%-20s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""


############ CloudPC prometheus PVC usage
echo "############ CloudPC prometheus PVC usage"
promeths=$(/usr/local/bin/kubectl -n cloudpc get po -o wide | grep prometheus-cloudpc-monitoring | awk '{print $1}')
printf "%-52s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for prometh in $promeths; do
  /usr/local/bin/kubectl -n cloudpc exec $prometh -c prometheus -- df -h /prometheus | awk -v hostname=$prometh 'NR==2{printf"%-52s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""


############ CloudPC elasticsearch PVC usage
echo "############ CloudPC elasticsearch PVC usage"
elastics=$(/usr/local/bin/kubectl -n cloudpc get po -o wide | grep elasticsearch-data | awk '{print $1}')
printf "%-52s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for elastic in $elastics; do
  /usr/local/bin/kubectl -n cloudpc exec $elastic -- df -h /usr/share/elasticsearch/data | awk -v hostname=$elastic 'NR==2{printf"%-52s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""

############ open files
#echo "############ open files 확인"
#echo "### ssgw1 : nginx"
#ssgw1=$(ssh $ssgwsrv1 'sudo lsof -n -u root | wc -l')
#ssgw1n=$(ssh $ssgwsrv1 "sudo bash -c 'ulimit -n'")
#echo "$ssgw1 / $ssgw1n"
#echo "### ssgw2 : nginx"
#ssgw2=$(ssh $ssgwsrv2 'sudo lsof -n -u root | wc -l')
#ssgw2n=$(ssh $ssgwsrv2 "sudo bash -c 'ulimit -n'")
#echo "$ssgw2 / $ssgw2n"
#echo ""


############ Namespace별 running 중인 모든 pod 개수
echo "############ Namespace별 running 중인 모든 pod 개수"
for kubens in $kubenss; do
  /usr/local/bin/kubectl get po -n $kubens 2> /dev/null | grep Runn | wc -l | awk -v ns="$kubens" '{printf "### namespace : %s running pods = %s\n",ns,$1}'
done
echo ""


############ Running 중인 모든 pod 중 Ready가 0인 pod 표시 (있으면 안됨)
echo "############ Ready가 0인 pod 표시"
/usr/local/bin/kubectl get po --all-namespaces -o wide | grep Running | awk 'index($3, "0")'
echo ""


############ kubernetes pod 중 모든 namespace에서 running, completed 외의 pod 확인
echo "############ Running 혹은 Completed 제외한 pod"
/usr/local/bin/kubectl get po --all-namespaces | grep -vi 'runn\|compl'
echo ""


############ 분배가 필요한 pod 확인
echo "############ 분배가 필요한 pod 확인"
for kubens in $kubenss; do
  deploys=$(/usr/local/bin/kubectl -n $kubens get deploy 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for deploy in $deploys; do
    dpl=$(/usr/local/bin/kubectl -n $kubens describe deploy $deploy | grep ReplicaSet | grep -v 'Progress\|none\|Scaling' | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "deployment" $deploy
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $dpl | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  dss=$(/usr/local/bin/kubectl -n $kubens get ds 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for ds in $dss; do
    daemon=$(/usr/local/bin/kubectl -n $kubens describe ds $ds | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "daemonset" $ds
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $daemon | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  stss=$(/usr/local/bin/kubectl -n $kubens get sts 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for sts in $stss; do
    state=$(/usr/local/bin/kubectl -n $kubens describe sts $sts | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "statefulset" $sts
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $state'.. ' | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  rss=$(/usr/local/bin/kubectl -n $kubens get rs 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for rs in $rss; do
    repl=$(/usr/local/bin/kubectl -n $kubens describe rs $rs | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "replicaset" $rs
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $repl | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
done
echo ""


############ 임시 파일 삭제
#rm -f /tmp/{daily-checklist-D1,daily-checklist-D2,serverstats,opst_running_vms}

