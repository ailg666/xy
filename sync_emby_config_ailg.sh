#!/bin/bash
data=$(date +"%Y-%m-%d %H:%M:%S")

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
	xiaoya_config_dir=$2
else
	EMBY_URL=$(cat /etc/xiaoya/emby_server.txt)
	xiaoya_config_dir=/etc/xiaoya
fi

media_lib=$1
if [ ! -d $media_lib/config_sync ]; then
	mkdir $media_lib/config_sync
fi

#local_sha=$(docker inspect --format='{{index .RepoDigests 0}}' ailg/ggbond:latest  |cut -f2 -d:)
#remote_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/ggbond/tags/latest"|grep -o '"digest":"[^"]*' | grep -o '[^"]*$' |tail -n1 |cut -f2 -d:)
#if [ ! "$local_sha" == "$remote_sha" ]; then
#	docker rmi ailg/ggbond:latest
#    docker pull ailg/ggbond:latest
#fi

docker rmi ailg/ggbond:latest
docker pull ailg/ggbond:latest

docker_exist=$(docker images |grep ailg/ggbond )
if [ -z "$docker_exist" ]; then
	echo "拉取镜像失败，请检查网络，或者翻墙后再试"
	exit 1
fi

SQLITE_COMMAND="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config:/emby/config -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_2="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config/data:/emby/config/data -v /tmp/emby_user.sql:/tmp/emby_user.sql  -v /tmp/emby_library_mediaconfig.sql:/tmp/emby_library_mediaconfig.sql -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_3="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/temp/config/data:/emby/config/data -e LANG=C.UTF-8 ailg/ggbond:latest"

if [[ $(docker ps -a | grep -E "(^|\s)$EMBY_NAME(\s|$)") ]];then
	#mount_paths=$(docker inspect $EMBY_NAME \
	| jq -r '.[0].Mounts[] | select(.Destination != "/media" and .Destination != "/config" and .Destination != "/etc/nsswitch.conf") | .Destination')
	#echo $mount_paths
	#printf "%s\n" "${mount_paths[@]}" > $media_lib/config/mount_paths.txt
	docker inspect $EMBY_NAME | grep Destination | grep -vE "/config|/media|/etc/nsswitch.conf" | awk -F\" '{print $4}' > $media_lib/config/mount_paths.txt
else
	echo "您的输入有误，没有找到名字为$EMBY_NAME的容器！程序退出！"
	exit 1
fi
curl -s "${EMBY_URL}/Users?api_key=e825ed6f7f8f44ffa0563cddaddce14d"  > /tmp/emby.response
echo "$data Emby 和 Resilio关闭中 ...."
docker stop ${EMBY_NAME}

sleep 4

#旧数据备份并清除旧数据库
${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump UserDatas" > /tmp/emby_user.sql
${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump ItemExtradata" > /tmp/emby_library_mediaconfig.sql
${SQLITE_COMMAND} /emby_userdata.sh
#read -ep "**检查sql"
mv  $media_lib/config/data/library.db $media_lib/config/data/library.org.db
[[ -f $media_lib/config/data/library.db-wal ]] && mv $media_lib/config/data/library.db-wal $media_lib/config/data/library.db-wal.bak
[[ -f $media_lib/config/data/library.db-shm ]] && mv $media_lib/config/data/library.db-shm $media_lib/config/data/library.db-shm.bak
rm $media_lib/config/data/library.db*
	
# 下载解压新config数据
if command -v ifconfig > /dev/null 2>&1; then
	docker0=$(ifconfig docker0 | awk '/inet / {print $2}' | sed 's/addr://')
else
	docker0=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d '/' -f 1)
fi
echo -e "测试xiaoya的联通性..."
if curl -siL http://127.0.0.1:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
	xiaoya_addr="http://127.0.0.1:5678"
elif curl -siL http://${docker0}:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
	xiaoya_addr="http://${docker0}:5678"
else
	if [ -s ${xiaoya_config_dir}/docker_address.txt ]; then
		docker_address=$(head -n1 ${xiaoya_config_dir}/docker_address.txt)
		if curl -siL http://${docker_address}:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
			xiaoya_addr=${docker_address}
		else
			ERROR "请检查xiaoya是否正常运行后再试"
			exit 1
		fi
	else
		ERROR "请先配置 ${CONFIG_DIR}/docker_address.txt 后重试"
		exit 1
	fi
fi
echo -e "连接小雅地址为 ${xiaoya_addr}"
docker run -i \
	--security-opt seccomp=unconfined \
	--rm \
	--net=host \
	-v ${media_lib}:/media \
	-v ${xiaoya_config_dir}:/etc/xiaoya \
	--workdir=/media/temp \
	-e LANG=C.UTF-8 \
	ailg/ggbond:latest \
	aria2c -o config.mp4 --continue=true -x6 --conditional-get=true --allow-overwrite=true "${xiaoya_addr}/d/元数据/config.mp4"
# 在temp下面解压，最终新config文件路径为temp/config
docker run -i \
	--security-opt seccomp=unconfined \
	--rm \
	--net=host \
	-v ${media_lib}:/media \
	-v ${xiaoya_config_dir}:/etc/xiaoya \
	--workdir=/media/temp \
	-e LANG=C.UTF-8 \
	ailg/ggbond:latest \
	7z x -aoa -mmt=16 config.mp4
echo -e "下载解压元数据完成"

echo "$data 检查同步数据库完整性..."
sleep 4
if ${SQLITE_COMMAND_3} sqlite3 /emby/config/data/library.db ".tables" |grep Chapters3 > /dev/null ; then
	
	echo -e "\033[32m$data 同步数据库数据完整\033[0m"
	cp -f $media_lib/temp/config/data/library.db* $media_lib/config/data/
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS UserDatas;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_user.sql"
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS ItemExtradata;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_library_mediaconfig.sql"	
	docker run -it --rm --security-opt seccomp=unconfined --net=host -v $media_lib:/test -e LANG=C.UTF-8  ailg/ggbond:latest /bin/bash -c "sqlite3 /test/config/data/library.db < /test/config/media_items_all.sql"
	echo "$data 保存用户信息完成"
	mkdir -p $media_lib/config/cache
	mkdir -p $media_lib/config/metadata
	cp -rf $media_lib/temp/config/cache/* $media_lib/config/cache/
	cp -rf $media_lib/temp/config/metadata/* $media_lib/config/metadata/
    rm -f $media_lib/config/*.sql
    rm -f $media_lib/config/mount_paths.txt
	rm -rf $media_lib/temp/config/*
	echo "$data 复制 config_sync 至 config 完成"
	
	chmod -R 777 $media_lib/config/data $media_lib/config/cache $media_lib/config/metadata
	
	echo "$data Emby 重启中 ...."
	docker start ${EMBY_NAME}
	sleep 20
else
	echo -e "\033[35m$data 同步数据库不完整，跳过复制...\033[0m"
	echo "$data 同步失败，正在恢复备份数据……"
	mv  $media_lib/config/data/library.org.db $media_lib/config/data/library.db
	mv $media_lib/config/data/library.db-wal.bak $media_lib/config/data/library.db-wal
	mv $media_lib/config/data/library.db-shm.bak $media_lib/config/data/library.db-shm
	docker start ${EMBY_NAME}
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
		echo "程序执行超时 5分钟，终止执行更新用户Policy"
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

