#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2086
# shellcheck disable=SC1091
# shellcheck disable=SC2154
# shellcheck disable=SC2162

if [ -d $1/mytoken.txt ]; then
	rm -rf $1/mytoken.txt
fi
mkdir -p $1
mkdir -p $1/data
touch $1/mytoken.txt
touch $1/myopentoken.txt
touch $1/temp_transfer_folder_id.txt

mytokenfilesize=$(cat $1/mytoken.txt)
mytokenstringsize=${#mytokenfilesize}
if [ $mytokenstringsize -le 31 ]; then
	echo -e "\\033[1;35m获取mytoken链接1：https://alist.nn.ci/zh/guide/drivers/aliyundrive.html\\033[0m"
    echo -e "\\033[1;35m获取mytoken链接2：https://aliyuntoken.vercel.app\\033[0m"
    echo -e "\033[32m"
	read -p "输入你的阿里云盘 Token（32位长）: " token
	token_len=${#token}
	if [ $token_len -ne 32 ]; then
		echo "长度不对,阿里云盘 Token是32位长"
		echo -e "安装停止，请参考指南配置文件\nhttps://xiaoyaliu.notion.site/xiaoya-docker-69404af849504fa5bcf9f2dd5ecaa75f \n"
		echo -e "\033[0m"
		exit
	else	
		echo $token > $1/mytoken.txt
	fi
	echo -e "\033[0m"
fi	

myopentokenfilesize=$(cat $1/myopentoken.txt)
myopentokenstringsize=${#myopentokenfilesize}
if [ $myopentokenstringsize -le 279 ]; then
	echo -e "\\033[1;32m获取myopentoken链接：https://alist.nn.ci/tool/aliyundrive/request.html\\033[0m"
    echo -e "\033[33m"
    read -p "输入你的阿里云盘 Open Token（280位长或者335位长）: " opentoken
	opentoken_len=${#opentoken}
        if [[ $opentoken_len -ne 280 ]] && [[ $opentoken_len -ne 335 ]]; then
                echo "长度不对,阿里云盘 Open Token是280位长或者335位"
		echo -e "安装停止，请参考指南配置文件\nhttps://xiaoyaliu.notion.site/xiaoya-docker-69404af849504fa5bcf9f2dd5ecaa75f \n"
		echo -e "\033[0m"
                exit
        else
        	echo $opentoken > $1/myopentoken.txt
	fi
	echo -e "\033[0m"
fi

folderidfilesize=$(cat $1/temp_transfer_folder_id.txt)
folderidstringsize=${#folderidfilesize}
if [ $folderidstringsize -le 39 ]; then
	echo -e "\\033[1;35m获取阿里云盘转存目录id链接：https://www.aliyundrive.com/s/rP9gP3h9asE\\033[0m"
    echo -e "\033[36m"
    read -p "输入你的阿里云盘转存目录folder id: " folderid
	folder_id_len=${#folderid}
	if [ $folder_id_len -ne 40 ]; then
                echo "长度不对,阿里云盘 folder id是40位长"
		echo -e "安装停止，请参考指南配置文件\nhttps://xiaoyaliu.notion.site/xiaoya-docker-69404af849504fa5bcf9f2dd5ecaa75f \n"
		echo -e "\033[0m"
                exit
        else
        	echo $folderid > $1/temp_transfer_folder_id.txt
	fi	
	echo -e "\033[0m"
fi

#echo "new" > $1/show_my_ali.txt
if command -v ifconfig &> /dev/null; then
        localip=$(ifconfig -a|grep inet|grep -v 172.17 | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1)
else
        localip=$(ip address|grep inet|grep -v 172.17 | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1|cut -f1 -d"/")
fi

if [ $2 ]; then
	if [ $2 == 'host' ]; then
		if [ ! -s $1/docker_address.txt ]; then
			echo "http://$localip:5678" > $1/docker_address.txt
		fi	
		docker stop xiaoya 2>/dev/null
		docker rm xiaoya 2>/dev/null
		docker stop xiaoya-hostmode 2>/dev/null
		docker rm xiaoya-hostmode 2>/dev/null
		
		if [[ -f $1/proxy.txt ]] && [[ -s $1/proxy.txt ]]; then
			proxy_url=$(head -n1 $1/proxy.txt)
			docker run -d --env HTTP_PROXY="$proxy_url" --env HTTPS_PROXY="$proxy_url" --env no_proxy="*.aliyundrive.com" --network=host -v $1:/data -v $1/data:/www/data --restart=always --name=xiaoya_jf ailg/alist:hostmode
		else	
			docker run -d --network=host -v $1:/data -v $1/data:/www/data --restart=always --name=xiaoya_jf ailg/alist:hostmode
		fi
		[ ! -s $1/infuse_api_key.txt ] && echo "e825ed6f7f8f44ffa0563cddaddce14d" > "${1}/infuse_api_key.txt"
		[ ! -s $1/infuse_api_key_jf.txt ] && echo "aec47bd0434940b480c348f91e4b8c2b" > "${1}/infuse_api_key_jf.txt"
		exit
	fi
fi

if [ ! -s $1/docker_address.txt ]; then
        echo "http://$localip:5678" > $1/docker_address.txt
fi
docker stop xiaoya 2>/dev/null
docker rm xiaoya 2>/dev/null

if [[ -f $1/proxy.txt ]] && [[ -s $1/proxy.txt ]]; then
	proxy_url=$(head -n1 $1/proxy.txt)
    docker run -d --env HTTP_PROXY="$proxy_url" --env HTTPS_PROXY="$proxy_url" --env no_proxy="*.aliyundrive.com" --network=host -v $1:/data -v $1/data:/www/data --restart=always --name=xiaoya_jf ailg/alist:latest
else
	docker run -d --network=host -v $1:/data -v $1/data:/www/data --restart=always --name=xiaoya_jf ailg/alist:latest
fi
[ ! -s $1/infuse_api_key.txt ] && echo "e825ed6f7f8f44ffa0563cddaddce14d" > "${1}/infuse_api_key.txt"
[ ! -s $1/infuse_api_key_jf.txt ] && echo "aec47bd0434940b480c348f91e4b8c2b" > "${1}/infuse_api_key_jf.txt"

