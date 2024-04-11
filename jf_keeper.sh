#!/bin/bash
while true;do
	clear
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、一天清理一次\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m2、一分钟清理一次\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -ep "请选择：" user_select
	if [[ $user_select == 1 ]];then
		mode=0
		break
	elif [[ $user_select == 2 ]];then
		mode=55
		break
	else
		echo -e "\033[1;31m你的输入有误，请输入1或2\33[0m"
	fi
done

curl -s https://xiaoyahelper.ddsrem.com/aliyun_clear.sh | tail -n +2 | sed 's/haroldli\/xiaoya-tvbox/haroldli\/xiaoya-tvbox\\|ailg\/alist/g' | sed 's/newsh="$(cat "$0")"/newsh="$(cat "$0" | sed '\''s\/haroldli\\\/xiaoya-tvbox\/haroldli\\\/xiaoya-tvbox\\|ailg\\\/alist\/g'\'')"/g' > /tmp/test.sh
if ! [[ -f /tmp/test.sh ]];then
	curl -s http://xiaoyahelper.zengge99.eu.org/aliyun_clear.sh | tail -n +2 | sed 's/haroldli\/xiaoya-tvbox/haroldli\/xiaoya-tvbox\\|ailg\/alist/g' | sed 's/newsh="$(cat "$0")"/newsh="$(cat "$0" | sed '\''s\/haroldli\\\/xiaoya-tvbox\/haroldli\\\/xiaoya-tvbox\\|ailg\\\/alist\/g'\'')"/g' > /tmp/test.sh
	if ! [[ -f /tmp/test.sh ]];then
		echo -e "\033[1;31m文件下载失败，请检查您的网络！\033[0m"
	fi
fi
docker run --name xiaoyakeeper --restart=always --network=host --privileged -v /var/run/docker.sock:/var/run/docker.sock -e TZ="Asia/Shanghai" -d alpine:3.18.2 sh -c "if [ -f /etc/xiaoya/aliyun_clear.sh ];then sh /etc/xiaoya/aliyun_clear.sh ${mode};else sleep 60;fi" &>/dev/null
docker run --name xiaoyakeeper --restart=always --network=host --privileged -v /var/run/docker.sock:/var/run/docker.sock -e TZ="Asia/Shanghai" -d dockerproxy.com/library/alpine:3.18.2 sh -c "if [ -f /etc/xiaoya/aliyun_clear.sh ];then sh /etc/xiaoya/aliyun_clear.sh $1;else sleep 60;fi" &>/dev/null
docker exec xiaoyakeeper touch /docker-entrypoint.sh
docker exec xiaoyakeeper mkdir /etc/xiaoya
docker cp /tmp/test.sh xiaoyakeeper:/etc/xiaoya/aliyun_clear.sh
docker restart xiaoyakeeper
echo -e "\033[1;32m小雅请理守护安装完成！\033[0m"
