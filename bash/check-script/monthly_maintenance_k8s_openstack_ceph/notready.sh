#!/usr/bin/env bash

recipient="somaz@gmail.com"
STATE=$(kubectl get node |grep 'NotReady' |awk '{print $2}')
hostname=$(kubectl get node |grep 'NotReady' |awk '{print $1}')
name=$(hostname)
 
if [ "${STATE}" == "NotReady" ];then
    touch /$HOME/monthly_maintenance/send_mail
    echo "${hostname}" "${STATE}" >> /home/somaz/monthly_maintenance/send_mail
    #echo "${STATE}" >> /home/somaz/monthly_maintenance/send_mail
    #sudo cat /home/somaz/monthly_maintenance/send_mail | sudo /usr/sbin/sendmail -s "Node NotReady"  ${recipient}
    sudo cat /$HOME/monthly_maintenance/send_mail | sudo mail -s "$(hostname) Node NotReady" ${recipient}
    sudo rm -f /$HOME/monthly_maintenance/send_mail
    exit 0
    echo ""
    exit 0
fi
