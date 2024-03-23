#!/bin/bash
#运行环境初始化
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

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

WARN "脚本会自动删除现有的名为emby的容器"
read -n 1 -p "按任意键继续，或按CTR+C退出！"

if [[ -z $1 || -z $2 ]];then
	ERROR "请在-s后输入两个正确的挂载路径后重新运行脚本，先后对应你小雅emby的config和xiaoya的路径"
	exit 1
fi

#获取小雅alist配置目录路径
docker_name=$(docker ps -a | grep xiaoyaliu/alist | awk '{print $NF}')
if command -v jq;then
	config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
else
	config_dir=$(docker inspect $docker_name | awk '/"Destination": "\/data"/{print a} {a=$0}'|awk -F\" '{print $4}')
fi

if command -v ifconfig > /dev/null 2>&1; then
	docker0=$(ifconfig docker0 | awk '/inet / {print $2}' | sed 's/addr://')
	localip=$(ifconfig -a | grep inet | grep -v 172.17 | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed 's/addr://' | head -n1)
else
	docker0=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d '/' -f 1)
	localip=$(ip address | grep inet | grep -v 172.17 | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed 's/addr://' | head -n1 | cut -f1 -d"/")
fi

if curl -siL http://127.0.0.1:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
	echo "http://127.0.0.1:5678" > $config_dir/emby_server.txt
elif curl -siL http://${docker0}:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
	echo "http://${docker0}:5678" > $config_dir/emby_server.txt
elif curl -siL http://${localip}:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
	echo "http://${localip}:5678" > $config_dir/emby_server.txt
else
	echo "请检查xiaoya是否正常运行后再试"
	exit 1
fi
host_ip=$(grep -oP '\d+\.\d+\.\d+\.\d+' $config_dir/emby_server.txt)
INFO "小雅alist容器重启中……"
docker restart $docker_name

if docker inspect emby > /dev/null 2>&1;then
	INFO "删除旧的emby容器"
	docker stop emby
	docker rm emby
fi

docker run -d --name emby \
-v /etc/nsswitch.conf:/etc/nsswitch.conf \
-v $1:/config \
-v $2:/media \
--user 0:0 \
--net=host \
--device /dev/dri:/dev/dri \
--privileged \
--add-host="xiaoya.host:$host_ip" \
--restart always emby/embyserver_arm32v7:4.8.0.56

INFO "小雅emby已安装完成，5分钟后用浏览器打开 http://$host_ip:2345 访问，用户名：xiaoya ,密码： 1234"

