#!/bin/bash
#运行环境初始化
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

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

function11() {
    clear
    echo -e "\e[33m"
	echo -e "—————————————————————————————————使  用  说  明———————————————————————————————————"
	echo -e "1、本脚本为小雅EMBY全家桶的定制化安装脚本，使用于群晖系统环境，不保证其他系统通用；"
	echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
	echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行脚本，按CTRL+C立即退出；"
	echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：http://qr61.cn/oVTrfl/q9n5NeV"
	echo -e "——————————————————————————————————————————————————————————————————————————————————"
	echo -e "\e[0m"
	echo -e "\n"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;35m1、安装/重装累死鸟同步（resilio）\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、立即同步小雅emby的config目录\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m3、设置同步计划\033[0m"
    echo -e "\n"
	echo -e "\033[1;35m4、取消同步计划\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
	read -ep "请选择（1-4）：" f11_choose
	if [[ ! $f11_choose == 4 ]];then
		get_config_path
		read -ep "请输入您要同步的emby容器名（名字是默认的emby请直接回车）" emby_name
		#检查用户输入
		[[ -z $emby_name ]] && emby_name="emby"
		if [[ $(docker ps -a | grep $emby_name) ]];then
			[[ -z $(docker ps | grep $emby_name) ]] && docker restart $emby_name
		else
			ERROR "您输入的容器名不正确，按任意键换个姿势再来一次！"
			read -n 1 s
			function11
		fi
		get_emby_media_path $emby_name
	fi
	if [[ $f11_choose == 1 ]]; then
		#获取其他自定义的同步参数
		read -ep "请设置您的resilio容器内存上限（单位：MB，示例：2048）：" mem_size
        curl -o /tmp/resilio_ailg.sh https://xy.ggbond.org/xy/resilio_ailg.sh
        grep -q "resilio" /tmp/resilio_ailg.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/resilio_ailg.sh; exit 1; }
		bash -c "$(cat /tmp/resilio_ailg.sh)" \
		-s $media_dir $mem_size
	elif [[ $f11_choose == 2 ]]; then
		#read -ep "请输入您要同步的resilio容器名（名字是默认的resilio请直接回车）" resilio_name
        echo -e "\n"
        echo -e "\033[1;31m同步进行中，需要较长时间，请耐心等待，直到出命令行提示符才算结束！\033[0m"
        curl -o /tmp/sync_emby_config_ailg.sh https://xy.ggbond.org/xy/sync_emby_config_ailg.sh
        grep -q "返回错误" /tmp/sync_emby_config_ailg.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/sync_emby_config_ailg.sh; exit 1; }
		bash -c "$(cat /tmp/sync_emby_config_ailg.sh)" -s $media_dir $config_dir $emby_name | tee $media_dir/temp/cron.log
		echo -e "\n"
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        INFO "安装完成"
        WARN "已在原目录（config/data）为您创建library.db的备份文件library.org.db"
        echo -e "\n"
        WARN "只有emby启动报错，或启动后媒体库丢失才需执行以下操作："
        echo -e "\033[1;35m1、先停止容器，检查emby媒体库目录的config/data目录中是否有library.org.db备份文件！"
        echo -e "2、如果没有，说明备份文件已自动恢复，原数据启动不了需要排查其他问题，或重装config目录！"
        echo -e "3、如果有，继续执行3-5步，先删除library.db/library.db-shm/library.db-wal三个文件！"
		echo -e "4、将library.org.db改名为library.db，library.db-wal.bak改名为library.db-wal（没有此文件则略过）！"
		echo -e "5、将library.db-shm.bak改名为library.db-shm（没有此文件则略过），重启emby容器即可恢复原数据！\033[0m"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
	elif [[ $f11_choose == 3 ]]; then	
		echo -e "\033[1;37m请设置您希望resilio每次同步的时间：\033[0m"
		read -ep "注意：24小时制，格式："hh:mm"，小时分钟之间用英文冒号分隔，示例：23:45）：" sync_time
		read -ep "您希望小雅emby的 config 几天同步一次？（单位：天）" sync_day
		#read -ep "请输入您要同步的emby容器名（名字是默认的emby请直接回车）：" emby_name
		#read -ep "请输入您要同步的resilio容器名（名字是默认的resilio请直接回车）：" resilio_name
		#read -ep "宿主机为群晖请输入syno，否则直接回车：" is_syno
        [[ -f /etc/synoinfo.conf ]] && is_syno="syno"
        [[ -z $emby_name ]] && emby_name="emby"
		#[[ -z $resilio_name ]] && resilio_name="resilio"
        curl -o /tmp/sync_cron_ailg.sh https://xy.ggbond.org/xy/sync_cron_ailg.sh
        grep -q "定时任务" /tmp/sync_cron_ailg.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/sync_cron_ailg.sh; exit 1; }
		bash -c "$(cat /tmp/sync_cron_ailg.sh)" -s $media_dir $config_dir $sync_time $sync_day $emby_name $is_syno
	elif [[ $f11_choose == 4 ]]; then
		if [[ -f /etc/synoinfo.conf ]];then
			sed -i '/sync_emby_config/d' /etc/crontab
		elif command -v crontab >/dev/null 2>&1; then
			crontab -l |grep -v sync_emby_config > /tmp/cronjob.tmp && crontab /tmp/cronjob.tmp
		else
			echo -e "未在你的系统找到同步计划任务！"
			exit 1
		fi
	echo -e "已为您取消同步计划！"
	fi
}

function diy_media_path(){
	echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
    read media_dir
    echo -e "\n"
    if [[ -d "$media_dir" && -d "$media_dir/config" && -d "$media_dir/xiaoya" ]]; then
        echo -e "\033[1;37m您选择的小雅EMBY媒体库路径是: \033[1;35m$media_dir\033[0m"
        echo -e "\n"
        read -ep "确认就按Y/y：" f12_select_3
        if ! [[ $f12_select_3 == [Yy] ]]; then
			ERROR "按键错误，按任意键重新输入或CTRL+C退出程序。"
        	read -n 1 s
        	diy_media_path
        fi
    else
        ERROR "该路径不存在或该路径下没有config配置目录"
        echo -e "\n"
        ERROR -e "\033[1;31m您选择的个目录不正确，按任意键重新输入或CTRL+C退出程序。\033[0m"
        read -n 1 s
        diy_media_path
    fi
}

#用$1传递非默认emby容器名
function get_emby_media_path(){
	if [[ -z $1 ]];then
		emby_name=emby
	else
		emby_name=$1
	fi	
	if command -v jq;then
		media_dir=$(docker inspect $emby_name | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
	else
		media_dir=$(docker inspect $emby_name | awk '/"Destination": "\/media"/{print a} {a=$0}'|awk -F\" '{print $4}')
	fi
	if ! [[ -z $media_dir ]];then
		media_dir=$(dirname "$media_dir")
		echo -e "\033[1;37m找到您的小雅EMBY媒体库路径是: \033[1;35m\n$media_dir\033[0m"
	    echo -e "\n"
	    read -ep "确认请按任意键，或者按N/n手动输入路径：" f12_select_2
	    if [[ $f12_select_2 == [Nn] ]]; then
			diy_media_path
	    fi
	    echo -e "\n"
	else
		diy_media_path
	fi
}

function get_config_path(){
	#获取小雅alist配置目录路径
	docker_name=$(docker ps -a | grep xiaoyaliu/alist | awk '{print $NF}')
	if command -v jq;then
		config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
	else
		config_dir=$(docker inspect $docker_name | awk '/"Destination": "\/data"/{print a} {a=$0}'|awk -F\" '{print $4}')
	fi
	echo -e "\033[1;37m找到您的小雅ALIST配置文件路径是: \033[1;35m\n$config_dir\033[0m"
    echo -e "\n"
    read -ep "确认请按任意键，或者按N/n手动输入路径（注：上方显示多个路径也请选择手动输入）：" f12_select_0
    if [[ $f12_select_0 == [Nn] ]]; then
		echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
        read config_dir
        echo -e "\n"
        if [[ -d "$config_dir" && -f "$config_dir/mytoken.txt" ]]; then
            echo -e "\033[1;37m您选择的小雅ALIST配置文件路径是: \033[1;35m$config_dir\033[0m"
            echo -e "\n"
            read -ep "确认就按Y/y：" f12_select_1
            if ! [[ $f12_select_1 == [Yy] ]]; then
				echo "选择错误，程序将退出。"
            	exit 1
            fi
        else
            echo "该路径不存在或该路径下没有mytoken.txt配置文件"
            echo -e "\n"
            echo -e "\033[1;31m您选择的个目录不正确，程序退出。\033[0m"
            exit 1
        fi
    fi
   echo -e "\n"    
}
function11