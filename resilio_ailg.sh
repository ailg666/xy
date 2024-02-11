docker stop resilio
docker rm resilio

if [ $1 ]; then
	mkdir -p $1/resilio/downloads
	echo "正在执行安装，同步目录较大，需较长时间创建，请耐心等待……"
	if [ ! -d $1/config_sync ]; then
		mkdir -p $1/config_sync
		chmod 777 $1/config_sync
		cp -r $1/config/* $1/config_sync/
	fi
	#wget -O /tmp/resilio.tgz http://docker.xiaoya.pro/resilio.tgz
	#cd $1
	#tar zxf /tmp/resilio.tgz
	#wget -O /tmp/dot_sync.tgz http://docker.xiaoya.pro/dot_sync.tgz
	#cd $1
	#tar zxf /tmp/dot_sync.tgz
	docker run -d \
	  -m ${3}M \
	  --log-driver none \
	  --name=resilio \
	  -e PUID=0 \
	  -e PGID=0 \
	  -e TZ=Asia/Shanghai \
	  --network=host \
	  -v $1/resilio:/config \
	  -v $1/resilio/downloads:/downloads \
	  -v $1:/sync \
	  --restart=always \
	  linuxserver/resilio-sync:latest
	
	echo -e "\033[32m"
	echo "安装 resilio 成功，登入的端口：8888"
	echo -e "\033[0m"
else
	echo "请在命令后输入 -s /媒体库目录 再重试"
	exit 1
fi

