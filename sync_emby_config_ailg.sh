#!/usr/bin/bash

if [ $3 ]; then
	EMBY_NAME=$3
else	
	EMBY_NAME=emby
fi

if [ $4 ]; then
	RESILIO_NAME=$4
else	
	RESILIO_NAME=resilio
fi

if [ $2 ]; then
	EMBY_URL=$(cat $2/emby_server.txt)
else	
	EMBY_URL=$(cat /etc/xiaoya/emby_server.txt)
fi

media_lib=$1
if [ ! -d $media_lib/config_sync ]; then
	mkdir $media_lib/config_sync
fi

SQLITE_COMMAND="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config:/emby/config -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_2="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config/data:/emby/config/data -v /tmp/emby_user.sql:/tmp/emby_user.sql  -v /tmp/emby_library_mediaconfig.sql:/tmp/emby_library_mediaconfig.sql -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_3="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config_sync/data:/emby/config/data -e LANG=C.UTF-8 ailg/ggbond:latest"

if [[ $(docker ps -a | grep -P "(^|\s)$EMBY_NAME(\s|$)") ]];then
	mount_paths=$(docker inspect $EMBY_NAME \
	| jq -r '.[0].Mounts[] | select(.Destination != "/media" and .Destination != "/config" and .Destination != "/etc/nsswitch.conf") | .Destination')
	echo $mount_paths
	printf "%s\n" "${mount_paths[@]}" > $media_lib/config/mount_paths.txt
else
	echo "您的输入有误，没有找到名字为$EMBY_NAME的容器！程序退出！"
	exit 1
fi

echo "Emby 和 Resilio关闭中 ...."
docker stop ${EMBY_NAME}
docker stop ${RESILIO_NAME}

echo "检查同步数据库完整性..."
sleep 4
if ${SQLITE_COMMAND_3} sqlite3 /emby/config/data/library.db ".tables" |grep Chapters3 > /dev/null ; then
	curl -s "${EMBY_URL}/Users?api_key=e825ed6f7f8f44ffa0563cddaddce14d"  > /tmp/emby.response
	echo -e "\033[32m同步数据库数据完整\033[0m"
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump UserDatas" > /tmp/emby_user.sql
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump ItemExtradata" > /tmp/emby_library_mediaconfig.sql
	${SQLITE_COMMAND} /emby_userdata.sh
	#read -ep "**检查sql"
	rm $media_lib/config/data/library.db*
	cp $media_lib/config_sync/data/library.db* $media_lib/config/data/
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS UserDatas;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_user.sql"
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS ItemExtradata;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_library_mediaconfig.sql"	
	docker run -it --rm --security-opt seccomp=unconfined --net=host -v $media_lib:/test -e LANG=C.UTF-8  ailg/ggbond:latest /bin/bash -c "sqlite3 /test/config/data/library.db < /test/config/media_items_all.sql"
	echo "保存用户信息完成"
	cp -rf $media_lib/config_sync/cache/* $media_lib/config/cache/
	cp -rf $media_lib/config_sync/metadata/* $media_lib/config/metadata/
	chmod -R 777 $media_lib/config/data $media_lib/config/cache $media_lib/config/metadata
	echo "复制 config_sync 至 config 完成"
	echo "Emby 和 Resilio 重启中 ...."
	docker start ${EMBY_NAME}
	docker start ${RESILIO_NAME}	
else
	echo -e "\033[35m同步数据库不完整，跳过复制...\033[0m"
	echo "Emby 和 Resilio 重启中 ...."
	docker start ${EMBY_NAME}
    docker start ${RESILIO_NAME}
	exit
fi

SINCE_TIME=$(date +"%Y-%m-%dT%H:%M:%S")
start_time=$(date +%s)
CONTAINER_NAME=${EMBY_NAME}
TARGET_LOG_LINE_SUCCESS="All entry points have started"
while true; do
	line=$(docker logs "$CONTAINER_NAME" 2>&1| tail -n 10)
	echo $line
	if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
        break
	fi
	current_time=$(date +%s)
	elapsed_time=$((current_time - start_time))
	if (( elapsed_time >= 300 )); then
		echo "程序执行超时 5分钟，终止执行"
		exit
	fi	
	sleep 3
done

EMBY_COMMAND="docker run -i --security-opt seccomp=unconfined --rm --net=host -v /tmp/emby.response:/tmp/emby.response -e LANG=C.UTF-8 ailg/ggbond:latest"
USER_COUNT=$(${EMBY_COMMAND} jq '.[].Name' /tmp/emby.response |wc -l)
for(( i=0 ; i <$USER_COUNT ; i++ ))
do
	if [[ "$USER_COUNT" > 9 ]]; then
		exit
	fi
	read -r id <<< "$(${EMBY_COMMAND} jq -r ".[$i].Id" /tmp/emby.response |tr -d [:space:])"
	read -r name <<< "$(${EMBY_COMMAND} jq -r ".[$i].Name" /tmp/emby.response |tr -d [:space:])"
	read -r policy <<< "$(${EMBY_COMMAND} jq -r ".[$i].Policy | to_entries | from_entries | tojson" /tmp/emby.response |tr -d [:space:])"
	USER_URL_2="${EMBY_URL}/Users/$id/Policy?api_key=e825ed6f7f8f44ffa0563cddaddce14d"
    	status_code=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "$policy" "$USER_URL_2")
    	if [ "$status_code" == "204" ]; then
        	echo "成功更新 $name 用户Policy"
    	else
        	echo "返回错误代码 $status_code"
    	fi
done

