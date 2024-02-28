#!/bin/bash
Sky_Blue="\e[36m"
Blue="\033[34m"
Green="\033[32m"
Red="\033[31m"
Yellow='\033[33m'
Font="\033[0m"
INFO="[${Green}INFO${Font}]"
ERROR="[${Red}ERROR${Font}]"
WARN="[${Yellow}WARN${Font}]"

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

docker stop resilio
docker rm resilio

if [ $1 ]; then
	mkdir -p $1/resilio/downloads
	if [ ! -d $1/config_sync ]; then
		mkdir -p $1/config_sync
		chmod 777 $1/config_sync
		cp -r $1/config/* $1/config_sync/
	fi

docker run -d \
  -m 2048M \
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

if command -v crontab >/dev/null 2>&1; then
	crontab -l |grep -v sync_emby_config > /tmp/cronjob.tmp
	echo '0 6 */3 * * bash -c "$(curl http://docker.xiaoya.pro/sync_emby_config.sh)" -s' " $1 $2 >> $1/resilio/cron.log" >> /tmp/cronjob.tmp
	crontab /tmp/cronjob.tmp

elif [ -f /etc/synoinfo.conf ]; then
    # 群晖单独支持
    cp /etc/crontab /etc/crontab.bak
    INFO "已创建/etc/crontab.bak备份文件"
    sed -i '/sync_emby_config/d' /etc/crontab
    echo -e "0 6 */3 * * root bash -c \"\$(curl http://docker.xiaoya.pro/sync_emby_config.sh)\" -s $1 $2" >> /etc/crontab
    INFO '已经添加下面的记录到crontab定时任务'
	echo -e "\033[33m"
	echo '0 6 */3 * * bash -c "$(curl http://docker.xiaoya.pro/sync_emby_config.sh)" -s' " $1 $2 >> $1/resilio/cron.log" ' 2>&1'
	echo -e "\033[0m"
fi

else
	echo "请在命令后输入 -s /媒体库目录 再重试"
	exit 1
fi

