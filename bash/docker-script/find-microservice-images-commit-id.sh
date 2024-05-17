#/bin/bash
##################################
# GLOVAL VARIABLES
VERSION="0.2"
AUTHOR="jwizard"
TODAY_YMD_HIS=`date "+%Y.%m.%d %H:%I:%S"`
TODAY=`date "+%m%d"`
NAMESPACE=somaz
OUTPUT_FILENAME=display_ms_output_$TODAY.txt
MESSAGE_EMPTY="[[ === NO DATA === ]]"
MESSAGE_DEPRECATED_15="[[ === DEPRECATED after 1.1.0.15 === ]]"
DEBUG=N
##################################
# Release Notes
# 0.1  : initialized
# 0.2  : added plat-ms-metering pod
##################################

# FrontEnd - 2 (SUCCESS)
ARRAY_MS+=("" "")
# Application BackEnd - 12 (SUCCESS)
ARRAY_MS+=("" "" "" "" "" "" "" "" "" "" "" "" "")
# Platform BackEnd - 9 (SUCCESS)
ARRAY_MS+=("" "" "" "" "" "" "" "" "")
# Management - 3 (SUCCESS)
ARRAY_MS+=("" "" "")

# Virtualization - 1 (FAILED)
#ARRAY_MS+=("somaz-libvirt")
# Logging - (FAILED)
#ARRAY_MS+=("somaz-logging-kibana" "somaz-logging-fluent-bit" "somaz-logging-elasticsearch-client" "somaz-logging-elasticsearch-curator" "somaz-logging-elasticsearch-exporter" "tenant-grafana")

##################################

echo "[[ ===== START : $TODAY_YMD_HIS - find somaz microservice commit_id, ver:$VERSION created by $AUTHOR ===== ]]"
echo "[[ ===== START : $TODAY_YMD_HIS - find somaz microservice commit_id, ver:$VERSION created by $AUTHOR ===== ]]" >> $OUTPUT_FILENAME

for APP_MS in "${ARRAY_MS[@]}"; do
	
	echo "INFO] APP_MS : $APP_MS"
	echo "COMMAND] kubectl get po -n$NAMESPACE \| grep $APP_MS \| head -n1 \| awk ' {print $1} '"
	POD_NAME=$(kubectl get po -n$NAMESPACE | grep $APP_MS | head -n1 | awk ' {print $1} ')
	if ( [[ "$DEBUG" == "Y" ]] ); then echo "INFO] POD_NAME : $POD_NAME" ; fi
	if [ -z "$POD_NAME" ] ; then 
		if ( [[ "$APP_MS" == "plat-ms-scheduler" ]] ); then
			echo "$APP_MS,$MESSAGE_DEPRECATED_15" >> $OUTPUT_FILENAME
		else
			echo "$APP_MS,$MESSAGE_EMPTY" >> $OUTPUT_FILENAME
		fi
		continue;
	fi

	echo "COMMAND] kubectl describe po -n$NAMESPACE $POD_NAME \| grep 'Image:' \| awk ' {print $2}' "
	IMAGE_NAME_WITH_REGISTRY=$(kubectl describe po -n$NAMESPACE $POD_NAME | grep 'Image:' | awk ' {print $2} ')
	if ( [[ "$DEBUG" == "Y" ]] ); then echo "INFO] IMAGE_NAME_WITH_REGISTRY : $IMAGE_NAME_WITH_REGISTRY" ; fi

	echo "COMMAND] sudo docker image inspect $IMAGE_NAME_WITH_REGISTRY \| grep GIT_COMMIT \| sed -n 1p \| awk ' {print $2} ' \| cut -c 2-41 "
	COMMIT_ID=$(sudo docker image inspect $IMAGE_NAME_WITH_REGISTRY | grep GIT_COMMIT | sed -n 1p | awk ' {print $2} ' | cut -c 2-41 ) 
	if ( [[ "$DEBUG" == "Y" ]] ); then echo "INFO] $APP_MS,$IMAGE_NAME_WITH_REGISTRY,$COMMIT_ID" ; fi

	if [ -z "$COMMIT_ID" ] ; then
		echo "$APP_MS,$IMAGE_NAME_WITH_REGISTRY,$MESSAGE_EMPTY" >> $OUTPUT_FILENAME
	else
		echo "$APP_MS,$IMAGE_NAME_WITH_REGISTRY,$COMMIT_ID" >> $OUTPUT_FILENAME
	fi
done

echo "[[ ===== END : $TODAY_YMD_HIS - find somaz microservice commit_id version:$VERSION by $AUTHOR ===== ]]"
echo "[[ ===== END : $TODAY_YMD_HIS - find somaz microservice commit_id version:$VERSION by $AUTHOR ===== ]]" >> $OUTPUT_FILENAME

