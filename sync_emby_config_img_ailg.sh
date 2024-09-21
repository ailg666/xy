#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2086
# shellcheck disable=SC1091
# shellcheck disable=SC2154
# shellcheck disable=SC2162
data=$(date +"%Y-%m-%d %H:%M:%S")

function check_start(){
	SINCE_TIME=$(date +"%Y-%m-%dT%H:%M:%S")
	start_time=$(date +%s)
	[ -n "$4" ] && CONTAINER_NAME=${IMG_NAME} || CONTAINER_NAME=${EMBY_NAME}
	TARGET_LOG_LINE_SUCCESS="All entry points have started"
	while true; do
		line=$(docker logs "$CONTAINER_NAME" 2>&1| tail -n 10)
		echo $line >/dev/null
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
}

if [ $3 ]; then
	EMBY_NAME=$3
else	
	EMBY_NAME=emby
fi

if [ $4 ]; then
	IMG_NAME=$4
	if [ ! -d "$1/config_sync" ]; then
		mkdir "$1/config_sync"
	fi
fi

if [ $2 ]; then
	EMBY_URL=$(cat $2/emby_server.txt)
	xiaoya_config_dir=$2
else
	EMBY_URL=$(cat /etc/xiaoya/emby_server.txt)
	xiaoya_config_dir=/etc/xiaoya
fi

media_lib=$1


umask 000
#版本号用于控制非4.8.0.56的emby的用户数据写入，流程不一样。
emby_version=$(docker inspect $EMBY_NAME | grep -E Image | grep -v sha256 | awk -F\" '{ print $4 }' | cut -d: -f2)

local_sha=$(docker inspect -f'{{index .RepoDigests 0}}' ailg/ggbond:latest  |cut -f2 -d:)
remote_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/ggbond/tags/latest" | grep -oE '[0-9a-f]{64}' | tail -1)
if [ ! "$local_sha" == "$remote_sha" ]; then
	docker rmi ailg/ggbond:latest
    for i in {1..3};do
		docker pull ailg/ggbond:latest && break
	done
	[ $? -ne 0 ] && ERROR "ailg/ggbond镜像更新失败，请检查网络后重试，程序退出！" && exit 1
fi

SQLITE_COMMAND="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config:/emby/config -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_2="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/config/data:/emby/config/data -v /tmp/emby_user.sql:/tmp/emby_user.sql  -v /tmp/emby_library_mediaconfig.sql:/tmp/emby_library_mediaconfig.sql -e LANG=C.UTF-8 ailg/ggbond:latest"
SQLITE_COMMAND_3="docker run -i --security-opt seccomp=unconfined --rm --net=host -v $media_lib/temp/config/data:/emby/config/data -e LANG=C.UTF-8 ailg/ggbond:latest"

if [ "$4" ];then
	if [[ $(docker ps -a | grep -E "(^|\s)$IMG_NAME(\s|$)") ]];then
		#mount_paths=$(docker inspect $EMBY_NAME \
		#| jq -r '.[0].Mounts[] | select(.Destination != "/media" and .Destination != "/config" and .Destination != "/etc/nsswitch.conf") | .Destination')
		#echo $mount_paths
		#printf "%s\n" "${mount_paths[@]}" > $media_lib/config/mount_paths.txt
		docker inspect $IMG_NAME | grep Destination | grep -vE "/config|/media|/etc/" | awk -F\" '{print $4}' > $media_lib/config/mount_paths.txt
	fi
else
	if [[ $(docker ps -a | grep -E "(^|\s)$EMBY_NAME(\s|$)") ]];then
		#mount_paths=$(docker inspect $EMBY_NAME \
		#| jq -r '.[0].Mounts[] | select(.Destination != "/media" and .Destination != "/config" and .Destination != "/etc/nsswitch.conf") | .Destination')
		#echo $mount_paths
		#printf "%s\n" "${mount_paths[@]}" > $media_lib/config/mount_paths.txt
		docker inspect $EMBY_NAME | grep Destination | grep -vE "/config|/media|/etc/" | awk -F\" '{print $4}' > $media_lib/config/mount_paths.txt
	fi
fi
curl -s "${EMBY_URL}/Users?api_key=e825ed6f7f8f44ffa0563cddaddce14d"  > /tmp/emby.response
echo "$data Emby 关闭中 ...."
docker stop ${EMBY_NAME}

sleep 4

#旧数据备份并清除旧数据库
rm -f /tmp/*.sql
${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump UserDatas" > /tmp/emby_user.sql
${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db ".dump ItemExtradata" > /tmp/emby_library_mediaconfig.sql
${SQLITE_COMMAND} /emby_userdata.sh

echo -e "$EMBY_NAME\n$media_lib\n$EMBY_URL\n$xiaoya_config_dir" 
#read -ep "**检查sql"
mv  $media_lib/config/data/library.db $media_lib/config/data/library.org.db
[[ -f $media_lib/config/data/library.db-wal ]] && mv $media_lib/config/data/library.db-wal $media_lib/config/data/library.db-wal.bak
[[ -f $media_lib/config/data/library.db-shm ]] && mv $media_lib/config/data/library.db-shm $media_lib/config/data/library.db-shm.bak
#rm $media_lib/config/data/library.db $media_lib/config/data/library.db-wal $media_lib/config/data/library.db-shm
	
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
		ERROR "请先配置 ${xiaoya_config_dir}/docker_address.txt 后重试"
		exit 1
	fi
fi
echo -e "连接小雅地址为 ${xiaoya_addr}"
for i in {1..5};do
	remote_cfg_size=$(curl -sL -D - -o /dev/null --max-time 5 "$xiaoya_addr/d/元数据/config.mp4" | grep "Content-Length" | cut -d' ' -f2)
	[[ -n $remote_cfg_size ]] && break
done
local_cfg_size=$(du -b "$media_lib/temp/config.mp4" | cut -f1)
echo -e "\033[1;33mremote_cfg_size=${remote_cfg_size}\nlocal_cfg_size=${local_cfg_size}\033[0m"
for i in {1..5};do
	if [[ -z "${local_cfg_size}" ]] || [[ ! $remote_size == "$local_size" ]] || [[ -f $media_lib/temp/config.mp4.aria2 ]];then
		echo -e "\033[1;33m正在下载config.mp4……\033[0m"
		rm -f $media_lib/temp/config.mp4
		docker run -i \
		--security-opt seccomp=unconfined \
		--rm \
		--net=host \
		-v $media_lib:/media \
		-v ${xiaoya_config_dir}:/etc/xiaoya \
		--workdir=/media/temp \
		-e LANG=C.UTF-8 \
		ailg/ggbond:latest \
		aria2c -o config.mp4 --continue=true -x6 --conditional-get=true --allow-overwrite=true "${xiaoya_addr}/d/元数据/config.mp4"
		local_cfg_size=$(du -b "$media_lib/temp/config.mp4" | cut -f1)
		run_7z=true
	else
		echo -e "\033[1;33m本地config.mp4与远程文件一样，无需重新下载！\033[0m"
		run_7z=false
		break
	fi
done
if [[ -z "${local_cfg_size}" ]] || [[ ! $remote_size == "$local_size" ]] || [[ -f $media_lib/temp/config.mp4.aria2 ]];then
	ERROR "config.mp4下载失败，请检查网络，如果token失效或触发阿里风控将小雅alist停止1小时后再打开重试！"
	exit 1
fi

if ! "${run_7z}";then
	echo -e "\033[1;33m远程小雅config未更新，与本地数据一样，是否重新解压本地config.mp4？\033[0m"
	answer=""
	t=30
	while [[ -z "$answer" && $t -gt 0 ]]; do
		printf "\r按Y/y键解压，按N/n退出（%2d 秒后将默认不解压退出）：" $t
		read -t 1 -n 1 answer
		t=$((t-1))
	done
	[[ "${answer}" == [Yy] ]] && run_7z=true
fi
if "${run_7z}";then
	rm -rf $media_lib/config/cache/* $media_lib/config/metadata/* $media_lib/config/data/library.db $media_lib/config/data/library.db-wal $media_lib/config/data/library.db-shm
	docker run -i \
	--security-opt seccomp=unconfined \
	--rm \
	--net=host \
	-v $media_lib:/media \
	-v ${xiaoya_config_dir}:/etc/xiaoya \
	--workdir=/media/temp \
	-e LANG=C.UTF-8 \
	ailg/ggbond:latest \
	7z x -aoa -bb1 -mmt=16 config.mp4
	echo -e "\033[1;33m下载解压元数据完成\033[0m"
else
	echo -e "\033[1;33m远程config与本地一样，未执行解压/更新！\033[0m"
	exit 0
fi

echo "$data 检查同步数据库完整性..."
sleep 4

if ${SQLITE_COMMAND_3} sqlite3 /emby/config/data/library.db ".tables" | grep Chapters3 > /dev/null ; then
	
	echo -e "\033[32m$data 同步数据库数据完整\033[0m"
	echo -e "\033[32m$data 正在复制新的library.db至emby数据库……\033[0m"
	cp -f $media_lib/temp/config/data/library.db* $media_lib/config/data/
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS UserDatas;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_user.sql"
	${SQLITE_COMMAND} sqlite3 /emby/config/data/library.db "DROP TABLE IF EXISTS ItemExtradata;"
	${SQLITE_COMMAND_2} sqlite3 /emby/config/data/library.db ".read /tmp/emby_library_mediaconfig.sql"	
	[[ $emby_version == "4.8.0.56" ]] && ${SQLITE_COMMAND} bash -c "sqlite3 /emby/config/data/library.db < /emby/config/media_items_all.sql"
	echo "$data 保存用户信息完成"
	mkdir -p $media_lib/config/cache
	mkdir -p $media_lib/config/metadata
	echo -e "\033[1;33m正在复制新的config数据，请耐心等候……\033[0m"
	cp -rf $media_lib/temp/config/cache/* $media_lib/config/cache/
	cp -rf $media_lib/temp/config/metadata/* $media_lib/config/metadata/
	echo "$data 复制新的缓存及元数据至 emby数据库 完成！"
	
	echo -e "\033[32m$data正在更新数据库权限\033[0m"
	chmod -R 777 $media_lib/config/data $media_lib/config/cache $media_lib/config/metadata
	echo -e "\033[32m$data数据库权限更新完成！\033[0m"
	
	echo "$data Emby 重启中 ...."
	[ -n "$4" ] && docker start "${IMG_NAME}" || docker start "${EMBY_NAME}"
	sleep 3
else
	echo -e "\033[35m$data 同步数据库不完整，跳过复制...\033[0m"
	echo "$data 同步失败，正在恢复备份数据……"
	mv  $media_lib/config/data/library.org.db $media_lib/config/data/library.db
	mv $media_lib/config/data/library.db-wal.bak $media_lib/config/data/library.db-wal
	mv $media_lib/config/data/library.db-shm.bak $media_lib/config/data/library.db-shm
	[ -n "$4" ] && docker start "${IMG_NAME}" || docker start "${EMBY_NAME}"
	exit
fi

check_start

if [[ ! $emby_version == 4.8.0.56 ]];then   
    docker stop ${EMBY_NAME}
    sleep 10
    ${SQLITE_COMMAND} bash -c "sqlite3 /emby/config/data/library.db < /emby/config/media_items_all.sql"
    [ -n "$4" ] && docker start "${IMG_NAME}" || docker start "${EMBY_NAME}"
    sleep 3
    check_start
fi
rm -f $media_lib/config/*.sql
rm -f $media_lib/config/mount_paths.txt
rm -rf $media_lib/temp/config/*
[ -n "$4" ] && docker rm "${EMBY_NAME}"

EMBY_COMMAND="docker run -it --security-opt seccomp=unconfined --rm --net=host -v /tmp/emby.response:/tmp/emby.response -e LANG=C.UTF-8 ailg/ggbond:latest"
USER_COUNT=$(${EMBY_COMMAND} jq '.[].Name' /tmp/emby.response |wc -l)
#echo -e "user_count = $USER_COUNT"
#read -ep "check user_count"

for(( i=0 ; i <$USER_COUNT ; i++ ))
do
	if [[ "$USER_COUNT" -gt 30 ]]; then
		exit
	fi
	#<<<在绿联中不支持，改用下面的写法通用性可能更好。
    #read -r id <<< "$(${EMBY_COMMAND} jq -r ".[$i].Id" /tmp/emby.response |tr -d [:space:])"
    read -r id <<EOF
$(${EMBY_COMMAND} jq -r ".[$i].Id" /tmp/emby.response | tr -d "[:space:]")
EOF
    #下面这个命令将id替换成jellyfin惯用的形式，不知道是否某些版本的emby要求这种格式的id来请求更新策略，留着备用。
    #id=$(echo $id | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
	#read -r name <<< "$(${EMBY_COMMAND} jq -r ".[$i].Name" /tmp/emby.response |tr -d [:space:])"
	read -r name <<EOF
$(${EMBY_COMMAND} jq -r ".[$i].Name" /tmp/emby.response | tr -d "[:space:]")
EOF
	#read -r policy <<< "$(${EMBY_COMMAND} jq -r ".[$i].Policy | to_entries | from_entries | tojson" /tmp/emby.response |tr -d [:space:])"
	read -r policy <<EOF
$(${EMBY_COMMAND} jq -r ".[$i].Policy | to_entries | from_entries | tojson" /tmp/emby.response |tr -d "[:space:]")
EOF
	USER_URL_2="${EMBY_URL}/Users/$id/Policy?api_key=e825ed6f7f8f44ffa0563cddaddce14d"
    	status_code=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "$policy" "$USER_URL_2")
        echo $status_code

    	if [ "$status_code" == "204" ]; then
        	echo "成功更新 $name 用户Policy"
    	else
        	echo "返回错误代码 $status_code"
    	fi
done

