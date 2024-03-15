#!/bin/bash

media_lib=$1

if [ $2 ]; then
	EMBY_URL=$(cat $2/emby_server.txt)
	xiaoya_config_dir=$2
else
	EMBY_URL=$(cat /etc/xiaoya/emby_server.txt)
	xiaoya_config_dir=/etc/xiaoya
fi

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
			echo -e "请检查xiaoya是否正常运行后再试"
			exit 1
		fi
	else
		echo -e "请先配置 ${CONFIG_DIR}/docker_address.txt 后重试"
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

sleep 5
docker run -i \
	--security-opt seccomp=unconfined \
	--rm \
	--net=host \
	-v ${media_lib}:/media \
	-v ${xiaoya_config_dir}:/etc/xiaoya \
	--workdir=/media/temp \
	-e LANG=C.UTF-8 \
	ailg/ggbond:latest \
	7z x config.mp4 -o/media/ -aoa -mmt=8
echo -e "下载解压元数据完成"