#!/bin/bash
Blue="\033[1;34m"
Green="\033[1;32m"
Red="\033[1;31m"
Yellow='\033[1;33m'
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

time_value=${3//：/:}
hour=${time_value%%:*}
minu=${time_value#*:}


if ! [[ "$hour" =~ ^([01]?[0-9]|2[0-3])$ ]] || ! [[ "$minu" =~ ^([0-5]?[0-9])$ ]]; then
  echo "输入错误，请重新输入。小时必须为0-23的正整数，分钟必须为0-59的正整数。"
fi

#echo -e "hour=$hour"
#echo -e "minu=$minu"
#echo -e "$1\n$2\n$3\n$4\n$5\n$6\n$7"
#read -ep "**check"
if command -v crontab >/dev/null 2>&1; then
	crontab -l |grep -v sync_emby_config > /tmp/cronjob.tmp
	#echo '$minu $hour */$4 * * bash -c "$(curl https://xy.ggbond.org/xy/sync_emby_config_ailg.sh)" -s' " $1 $2 $5 > $1/resilio/cron.log" >> /tmp/cronjob.tmp
	echo "$minu $hour */$4 * * /bin/bash -c \"\$(curl https://xy.ggbond.org/xy/sync_emby_config_ailg.sh) -s $1 $2 $5 | tee $1/temp/cron.log" >> /tmp/cronjob.tmp
	crontab /tmp/cronjob.tmp
    echo -e "\n"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"	
    INFO "已经添加下面的记录到crontab定时任务，每$4天更新一次config"
    echo -e "\033[1;34m"
	echo "$(cat /tmp/cronjob.tmp| grep sync_emby_config )"
    echo -e "\033[0m"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
elif [[ $6 == syno ]];then
	cp /etc/crontab /etc/crontab.bak
	echo -e "\033[1;35m已创建/etc/crontab.bak备份文件！\033[0m"
	
	sed -i '/sync_emby_config/d' /etc/crontab
	echo "$minu $hour */$4 * * root /bin/bash -c \"\$(curl https://xy.ggbond.org/xy/sync_emby_config_ailg.sh) -s $1 $2 $5 | tee $1/temp/cron.log" >> /etc/crontab
    echo -e "\n"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"	
    INFO "已经添加下面的记录到crontab定时任务，每$4天更新一次config"
    echo -e "\033[1;34m"
	echo "$(cat /tmp/cronjob.tmp| grep sync_emby_config )"
    echo -e "\033[0m"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
fi
