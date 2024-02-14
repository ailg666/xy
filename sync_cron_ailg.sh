time_value=${3//：/:}
hour=${time_value%%:*}
minu=${time_value#*:}

if ! [[ "$hour" =~ ^([01]?[0-9]|2[0-3])$ ]] || ! [[ "$minu" =~ ^([0-5]?[0-9])$ ]]; then
  echo "输入错误，请重新输入。小时必须为0-23的正整数，分钟必须为0-59的正整数。"
fi

echo -e "hour=$hour"
echo -e "minu=$minu"
#echo -e "$1\n$2\n$3\n$4\n$5\n$6\n$7"
#read -ep "**check"
if command -v crontab >/dev/null 2>&1; then
	crontab -l |grep -v sync_emby_config > /tmp/cronjob.tmp
	echo '$minu $hour */$4 * * bash -c "$(curl https://gitee.com/i-xxg/xy/raw/master/sync_emby_config_ailg.sh)" -s' " $1 $2 $5 $6 >> $1/resilio/cron.log" >> /tmp/cronjob.tmp
	crontab /tmp/cronjob.tmp

	echo -e "\033[33m"
	echo -e "已经添加下面的记录到crontab定时任务，每$4天更新一次config"
	echo '$minu $hour */$4 * * bash -c "$(curl https://gitee.com/i-xxg/xy/raw/master/sync_emby_config_ailg.sh)" -s' " $1 $2 $5 $6 >> $1/resilio/cron.log" ' 2>&1'
	echo -e "\033[0m"
elif [[ $7 == syno ]];then
	cp /etc/crontab /etc/crontab.bak
	echo -e "\033[1;35m已创建/etc/crontab.bak备份文件！\033[0m"
	
	sed -i '/sync_emby_config/d' /etc/crontab
	echo "$minu $hour */$4 * * root bash -c \"\$(curl https://gitee.com/i-xxg/xy/raw/master/sync_emby_config_ailg.sh)\" -s $1 $2 $5 $6 >> $1/resilio/cron.log" >> /etc/crontab
fi
