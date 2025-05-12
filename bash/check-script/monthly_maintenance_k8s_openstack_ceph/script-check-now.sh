#!/usr/bin/env bash

# OpenStack Environment Configuration
# -------------------------------
# Set up OpenStack authentication and API endpoints
# These variables are required for OpenStack CLI operations
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=somaz
export OS_AUTH_URL=http://keystone.openstack.svc.cluster.local:8080/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2

# Date and Path Variables
# ---------------------
# Set up date-based variables for file naming and organization
echo "daily-csv-"$(date +"%Y-%m-%d_%Hh_%Mm.txt") > /tmp/daily-checklist-D1
echo $(date +"%Y-%m") > /tmp/daily-checklist-D2
DATE1=$(cat /tmp/daily-checklist-D1)
DATE2=$(cat /tmp/daily-checklist-D2)
scpath="/home/somaz/monthly_maintenance/"

# System Information Collection
# --------------------------
# Get list of hypervisors and Kubernetes namespaces
hyplist=$(/usr/bin/openstack hypervisor list | awk 'NR>3 {print $4}')
kubenss=$(/usr/local/bin/kubectl get ns | awk 'NR > 1 {print $1}')

# Environment Configuration
# ----------------------
# Load server list and set Ceph master node
servlist=$(cat /home/somaz/monthly_maintenance/serverlist.txt)
cephmaster=r-ceph-farm-01

# Directory Setup
# -------------
# Create monthly directory for reports
mkdir -p $scpath/$DATE2

# Resource Usage Collection
# ----------------------
# Collect CPU, Memory, and disk usage statistics from all servers
rm -f /tmp/serverstats
for serv in $servlist; do
  ssh $serv $'\
  vmstat 1 2 | awk -v hostname=$HOSTNAME \'NR==4 {printf "%-25s CPU Usage = %.2f % \tContext Switch = %-10s",hostname,$13,$12}\' ; \
  uptime | awk -F \'average:\' \'{printf"load average: %s\\n",$2}\' ; \
  free | grep Mem | awk -v hostname=$HOSTNAME \'{ printf("%-25s Mem Total(GB): %-10.0f Mem Used(GB): %-10.0f Mem Used(%): %.2f %\\n",hostname,$2/1024/1024,$3/1024/1024, $3/$2*100.0) }\' ; \
  df -h / | tail -1 | awk -v hostname=$HOSTNAME \'{printf "%-20s\t%s\t%s\t%s\t%s\\n",hostname,$2,$3,$4,$5}\' ' >> /tmp/serverstats
done

# CPU Usage Report
# -------------
echo "############ CPU"
cat /tmp/serverstats | grep CPU
echo ""

# Memory Usage Report
# ----------------
echo "############ MEM"
cat /tmp/serverstats | grep Mem
echo ""

# VM Distribution Check
# ------------------
# Check number of running VMs on each hypervisor
echo "############ 각 노드별 Running 중인 VM 수 확인"
rm -f /tmp/opst_running_vms
for hyp in $hyplist; do
  /usr/bin/nova list --all --host=$hyp | grep Running | wc -l | awk -v hypname=$hyp '{printf "%-20s running VMs = %s\n",hypname,$1}' >> /tmp/opst_running_vms
done
cat /tmp/opst_running_vms | sort -k1
echo ""

# Ceph Storage Status
# ----------------
# Check Ceph storage usage and health
echo "############ ceph 사용량 확인"
ssh $cephmaster "sudo ceph df"
echo ""

# Storage Usage Report
# -----------------
# Check storage usage across different systems
echo "############ Storage별 사용량(간략)"
echo "### ceph"
ssh $cephmaster "sudo ceph df" | awk 'NR==3{printf"%s/%s (%s%)\n",$3,$1,$4}'
echo ""

# OSD Usage Check
# ------------
# Check usage of the largest OSD
echo "############ 가장 큰 osd의 사용량"
ssh $cephmaster "sudo ceph osd df" | egrep -v 'VAR|TOTAL' | sort -rnk8 | awk 'NR==1 {printf "Largest osd usage = %s %\n",$8}'
echo ""

# Ceph Health Check
# -------------
# Check detailed Ceph cluster health
echo "############ ceph 상태 확인"
ssh $cephmaster "sudo ceph health detail"
echo ""

# OSD Usage Report
# -------------
# Report usage for all OSDs
echo "############ osd 사용량"
ssh $cephmaster "sudo ceph osd df" | egrep -v 'VAR|TOTAL' | sort -rnk8 | awk '{printf "osd ID %-2s = %s %\n",$1,$8}'
echo ""

# Root Disk Usage
# -------------
# Check root disk usage on all hosts
echo "############ host local root disk usage"
df -h | head -1 | awk '{printf "%-20s\t%s\t%s\t%s\t%s\n","hostname",$2,$3,$4,$5}'
cat /tmp/serverstats | grep -v 'CPU\|Mem' | sort -rnk5
echo ""

# CloudPC Database PVC Usage
# ----------------------
# Check PVC usage for CloudPC application databases
echo "############ CloudPC app-db PVC usage"
appdbs=$(/usr/local/bin/kubectl -n cloudpc get po | grep app-db-'[0-9]' | awk '{print $1}')
printf "%-20s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for appdb in $appdbs; do
  /usr/local/bin/kubectl -n cloudpc exec $appdb -- df -h /var/lib/mysql | awk -v hostname=$appdb 'NR==2{printf"%-20s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""

# OpenStack Database PVC Usage
# ------------------------
# Check PVC usage for OpenStack MariaDB instances
echo "############ Openstack mariadb PVC usage"
mariadbs=$(/usr/local/bin/kubectl -n openstack get po | grep mariadb-server-'[0-9]' | awk '{print $1}')
printf "%-20s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for mariadb in $mariadbs; do
  /usr/local/bin/kubectl -n openstack exec $mariadb -- df -h /var/lib/mysql | awk -v hostname=$mariadb 'NR==2{printf"%-20s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""

# CloudPC Prometheus PVC Usage
# -------------------------
# Check PVC usage for CloudPC Prometheus instances
echo "############ CloudPC prometheus PVC usage"
promeths=$(/usr/local/bin/kubectl -n cloudpc get po -o wide | grep prometheus-cloudpc-monitoring | awk '{print $1}')
printf "%-52s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for prometh in $promeths; do
  /usr/local/bin/kubectl -n cloudpc exec $prometh -c prometheus -- df -h /prometheus | awk -v hostname=$prometh 'NR==2{printf"%-52s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""

# CloudPC Elasticsearch PVC Usage
# ---------------------------
# Check PVC usage for CloudPC Elasticsearch instances
echo "############ CloudPC elasticsearch PVC usage"
elastics=$(/usr/local/bin/kubectl -n cloudpc get po -o wide | grep elasticsearch-data | awk '{print $1}')
printf "%-52s %-7s %-7s %-7s %-7s %s\n" "Pod" "Size" "Used" "Avail" "Use%" "Mounted on"
for elastic in $elastics; do
  /usr/local/bin/kubectl -n cloudpc exec $elastic -- df -h /usr/share/elasticsearch/data | awk -v hostname=$elastic 'NR==2{printf"%-52s %-7s %-7s %-7s %-7s %s\n",hostname,$2,$3,$4,$5,$6}'
done
echo ""

# Kubernetes Pod Status Check
# ------------------------
# Check running pods across all namespaces
echo "############ Namespace별 running 중인 모든 pod 개수"
for kubens in $kubenss; do
  /usr/local/bin/kubectl get po -n $kubens 2> /dev/null | grep Runn | wc -l | awk -v ns="$kubens" '{printf "### namespace : %s running pods = %s\n",ns,$1}'
done
echo ""

# Not Ready Pods Check
# -----------------
# Check for pods that are running but not ready
echo "############ Ready가 0인 pod 표시"
/usr/local/bin/kubectl get po --all-namespaces -o wide | grep Running | awk 'index($3, "0")'
echo ""

# Abnormal Pod Status Check
# ----------------------
# Check for pods that are neither running nor completed
echo "############ Running 혹은 Completed 제외한 pod"
/usr/local/bin/kubectl get po --all-namespaces | grep -vi 'runn\|compl'
echo ""

# Pod Distribution Check
# -------------------
# Check for pods that need to be redistributed across nodes
echo "############ 분배가 필요한 pod 확인"
for kubens in $kubenss; do
  # Check Deployments
  deploys=$(/usr/local/bin/kubectl -n $kubens get deploy 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for deploy in $deploys; do
    dpl=$(/usr/local/bin/kubectl -n $kubens describe deploy $deploy | grep ReplicaSet | grep -v 'Progress\|none\|Scaling' | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "deployment" $deploy
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $dpl | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  
  # Check DaemonSets
  dss=$(/usr/local/bin/kubectl -n $kubens get ds 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for ds in $dss; do
    daemon=$(/usr/local/bin/kubectl -n $kubens describe ds $ds | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "daemonset" $ds
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $daemon | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  
  # Check StatefulSets
  stss=$(/usr/local/bin/kubectl -n $kubens get sts 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for sts in $stss; do
    state=$(/usr/local/bin/kubectl -n $kubens describe sts $sts | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "statefulset" $sts
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $state'.. ' | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
  
  # Check ReplicaSets
  rss=$(/usr/local/bin/kubectl -n $kubens get rs 2> /dev/null | awk '$2 != 1 {print $1}' | awk 'NR>1 {print $1}')
  for rs in $rss; do
    repl=$(/usr/local/bin/kubectl -n $kubens describe rs $rs | head -1 | awk '{print $2}')
    printf "### namespace=%-15s resource=%-15s name=%s\n" $kubens "replicaset" $rs
    /usr/local/bin/kubectl -n $kubens get po -o wide | grep Running | grep $repl | sort -k7 | awk '{print $7}' | uniq -c | grep -v "1"
  done
done
echo ""

# Cleanup
# ------
# Remove temporary files
#rm -f /tmp/{daily-checklist-D1,daily-checklist-D2,serverstats,opst_running_vms}

