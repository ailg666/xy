#!/bin/bash
#运行环境初始化
# shellcheck shell=bash
# shellcheck disable=SC2086
# shellcheck disable=SC1091
# shellcheck disable=SC2154
# shellcheck disable=SC2162
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

Blue="\033[1;34m"
Green="\033[1;32m"
Red="\033[1;31m"
Yellow='\033[1;33m'
NC="\033[0m"
INFO="[${Green}INFO${NC}]"
ERROR="[${Red}ERROR${NC}]"
WARN="[${Yellow}WARN${NC}]"

function INFO() {
    echo -e "${INFO} ${1}" | tee >(sed "s/\x1b\[[0-9;]*m//g" >> $LOG_FILE)
}
function ERROR() {
    echo -e "${ERROR} ${1}" | tee >(sed "s/\x1b\[[0-9;]*m//g" >> $LOG_FILE)
}
function WARN() {
    echo -e "${WARN} ${1}" | tee >(sed "s/\x1b\[[0-9;]*m//g" >> $LOG_FILE)
}

LOG_FILE="/data/ali_clear.log"
reopen_log() {
    exec &> "$LOG_FILE"
}
trap 'reopen_log' USR1

PID_FILE="/var/run/ali_clear_ailg.pid"
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    [ -n "$old_pid" ] && kill -0 "$old_pid" &> /dev/null && kill -9 "$old_pid"
fi
echo $$ > "$PID_FILE"

get_access(){
	response=$(curl --connect-timeout 5 -m 5 -s -H "Content-Type: application/json" \
	-d '{"grant_type":"refresh_token", "refresh_token":"'$refresh_token'"}' \
	https://api.aliyundrive.com/v2/account/token)
	access_token=$(echo "$response" | sed -n 's/.*"access_token":"\([^"]*\).*/\1/p')
}

get_drive_id(){
	response="$(curl --connect-timeout 5 -m 5 -s -H "$HEADER" \
	-H "Content-Type: application/json" -X POST -d '{}' \
	"https://user.aliyundrive.com/v2/user/get")"

	lagacy_drive_id=$(echo "$response" | sed -n 's/.*"default_drive_id":"\([^"]*\).*/\1/p')
	drive_id=$(echo "$response" | sed -n 's/.*"resource_drive_id":"\([^"]*\).*/\1/p')

	if [ -z "$drive_id" ] || [ "$folder_type"x = "b"x ]; then
			drive_id=$lagacy_drive_id
	fi
}

get_file_list(){
	_res=$(curl --connect-timeout 5 -m 5 -s -H "$HEADER" \
	-H "Content-Type: application/json" -X POST \
	-d '{"drive_id": "'$drive_id'","parent_file_id": "'$file_id'"}' \
	"https://api.aliyundrive.com/adrive/v2/file/list")
	
	_list=$(echo "$_res" | tr '{' '\n' | grep -o "\"file_id\":\"[^\"]*\"" | cut -d':' -f2- | tr -d '"')
}

delete_File() {
    _file_id=$1
    _name=$(echo "$_res" | jq -r --arg file_id $_file_id '.items[] | select(.file_id==$file_id) | .name')
    _del=$(curl --connect-timeout 5 -m 5 -s -H "$HEADER" -H "Content-Type: application/json" -X POST -d '{
  "requests": [
    {
      "body": {
        "drive_id": "'$drive_id'",
        "file_id": "'$_file_id'"
      },
      "headers": {
        "Content-Type": "application/json"
      },
      "id": "'$_file_id'",
      "method": "POST",
      "url": "/file/delete"
    }
  ],
  "resource": "file"
}' "https://api.aliyundrive.com/v3/batch" | grep "\"status\":204")
    if [ -z "$_del" ]; then
        ERROR "$(date +%Y/%m/%d' '%H:%M:%S)\t${_name}删除失败！"
	else
		INFO "$(date +%Y/%m/%d' '%H:%M:%S)\t${_name}已彻底删除！"
		((del_num++))
    fi
}

# 本脚本在原小雅阿里守护清理的脚本基础上修改而来，致谢原作者！
timer=$(sed -n '2p' /data/ali_clear_time.txt)
timer=${timer:-1440}
timer=${1:-$timer}
case $timer in
	-1)
		cp -f /etc/crontabs/root /etc/crontabs/root.bak
		sed -i '/ali_clear/d' /etc/crontabs/root
		crontab /etc/crontabs/root
		trigger=1
		;;
	0)
		trigger=-1
		;;
	*)
		;;
esac


if ! ping -c 4 api.aliyundrive.com &> /dev/null;then
	sed '/aliyundrive.com/d' /etc/hosts > /tmp/hosts && cat /tmp/hosts > /etc/hosts
	echo -e "49.7.63.220\tapi.aliyundrive.com\n49.7.63.220\tuser.aliyundrive.com" >> /etc/hosts
fi
if ! ping -c 4 api.aliyundrive.com &> /dev/null;then
    ERROR "$(date +%Y/%m/%d' '%H:%M:%S)\t连接阿里云网络失败，请检查网络后重试！"
	sed '/49\.7\.63\.220/d' /etc/hosts > /tmp/hosts && cat /tmp/hosts > /etc/hosts
    exit 1
fi



refresh_token=$(head -n1 /data/mytoken.txt)
file_id=$(head -n1 /data/temp_transfer_folder_id.txt)
folder_type=$(head -n1 /data/folder_type.txt)  

for i in {1..5};do
	[ -n "${access_token}" ] && break || get_access
done
[ -z "${access_token}" ] && { ERROR "$(date +%Y/%m/%d' '%H:%M:%S)\t获取访问令牌失败，请检查mytoken.txt中的token是否失效！";exit 1; }
HEADER="Authorization: Bearer $access_token"



for i in {1..5};do
	[ -n "${drive_id}" ] && break || get_drive_id
done
[ -z "${drive_id}" ] && { ERROR "$(date +%Y/%m/%d' '%H:%M:%S)\t获取drive_id失败，请检查网络及token是否失效！";exit 1; }


for i in {1..5};do
	[ -n "${_list}" ] && break || get_file_list
done
#[ -z "${_list}" ] && { ERROR "$(date +%Y/%m/%d' '%H:%M:%S)\t获取转存文件列表失败，请检查网络及token是否失效！";exit 1; }

del_num=0
while read line; do
    _created_at=$(echo "$_res" | jq -r --arg file_id $line '.items[] | select(.file_id==$file_id) | .created_at')
	if [[ $trigger != 1	]] && [[ $trigger != -1	]];then
		trigger=$(($(date +%s)-$(date -d "${_created_at}" -D '%Y-%m-%dT%H:%M:%S' +%s)-timer*60-8*60*60)) 
	fi
	[ "$trigger" -gt 0 ] && delete_File "$line"
done < <(echo "$_list" | sed '/^$/d')
INFO "$(date +%Y/%m/%d' '%H:%M:%S)\t本次共清理${del_num}个小雅转存文件及文件夹！"
[ -n "$trigger" ] && [ "$trigger" -eq 1 ] && { cp -f /etc/crontabs/root.bak /etc/crontabs/root;crontab /etc/crontabs/root; }

ggbond_latest_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/ggbond/tags/latest" | grep -o '[0-9a-f]{64}' | tail -1)
[ -n "${ggbond_latest_sha}" ] && echo "${ggbond_latest_sha}" > /ggbond_latest_sha.txt

alist_hostmode_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/alist/tags/hostmode" | grep -o '[0-9a-f]{64}' | tail -1)
[ -n "${alist_hostmode_sha}" ] && echo "${alist_hostmode_sha}" > /alist_hostmode_sha.txt

alist_latest_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/alist/tags/latest" | grep -o '[0-9a-f]{64}' | tail -1)
[ -n "${alist_latest_sha}" ] && echo "${alist_latest_sha}" > /alist_latest_sha.txt
