#!/bin/bash
function11() {
    clear
    echo -e "\e[33m"
	echo -e "—————————————————————————————————使  用  说  明———————————————————————————————————"
	echo -e "1、本脚本为小雅EMBY全家桶的定制化安装脚本，使用于群晖系统环境，不保证其他系统通用；"
	echo -e "\n"
	echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
	echo -e "\n"
	echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行脚本，按CTRL+C立即退出；"
	echo -e "\n"
	echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：http://qr61.cn/oVTrfl/q9n5NeV"
	echo -e "——————————————————————————————————————————————————————————————————————————————————"
	echo -e "\e[0m"
	echo -e "\n"
    echo -e "————————————————————————————————————————————————————— \033[1;33mA  I  老  G\033[0m ——————————————————————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;35m1、安装/重装累死鸟同步（resilio）\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、立即同步小雅emby的config目录\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m3、设置同步计划\033[0m"
    echo -e "\n"
    echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"
	read -ep "请选择（1或2或3）：" f11_choose
	if [[ $f11_choose == 1 ]]; then
		function12
		#获取其他自定义的同步参数
		read -ep "请设置您的resilio容器内存上限（单位：MB，示例：2048）：" mem_size
		bash -c "$(curl https://xy.ggbond.org/xy/resilio_ailg.sh)" \
		-s $media_dir $config_dir $mem_size
	elif [[ $f11_choose == 2 ]]; then
		function12
		read -ep "请输入您要同步的emby容器名（名字是默认的emby请直接回车）" emby_name
		read -ep "请输入您要同步的resilio容器名（名字是默认的resilio请直接回车）" resilio_name
		bash -c "$(curl https://xy.ggbond.org/xy/sync_emby_config_ailg.sh)" -s $media_dir $config_dir $emby_name $resilio_name >> $media_dir/resilio/cron.log
		echo -e "已在同级目录（config/data）为您创建library.db的备份文件library.org.db"
        echo -e "\033[1;35m如果emby报错，先停止容器，删除library.db/library.db-shm/library.db-wal三个文件\n将library.org.db改名为library.db，重启emby容器即可恢复原数据！\033[0m"

	elif [[ $f11_choose == 3 ]]; then	
		function12
		echo -e "\033[1;37m请设置您希望resilio每次同步的时间：\033[0m"
		read -ep "注意：24小时制，格式："hh:mm"，小时分钟之间用英文冒号分隔，示例：23:45）：" sync_time
		read -ep "您希望resilio几天同步一次？（单位：天）" sync_day
		read -ep "请输入您要同步的emby容器名（名字是默认的emby请直接回车）：" emby_name
		read -ep "请输入您要同步的resilio容器名（名字是默认的resilio请直接回车）：" resilio_name
		read -ep "宿主机为群晖请输入syno，否则直接回车：" is_syno
        [[ -z $emby_name ]] && emby_name="emby"
		[[ -z $resilio_name ]] && resilio_name="resilio"
		bash -c "$(curl https://xy.ggbond.org/xy/sync_cron_ailg.sh)" -s $media_dir $config_dir $sync_time $sync_day $emby_name $resilio_name $is_syno
	fi
}

function12(){
	#获取小雅alist配置目录路径
	docker_name=$(docker ps -a | grep xiaoyaliu/alist | awk '{print $NF}')
	config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
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
    
    #获取小雅媒体库路径
	media_dir=$(docker inspect emby | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
	if ! [[ -z $media_dir ]];then
		media_dir=$(dirname "$media_dir")
		echo -e "\033[1;37m找到您的小雅EMBY媒体库路径是: \033[1;35m\n$media_dir\033[0m"
	    echo -e "\n"
	    read -ep "确认请按任意键，或者按N/n手动输入路径：" f12_select_2
	    if [[ $f12_select_2 == [Nn] ]]; then
			echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
	        read media_dir
	        echo -e "\n"
	        if [[ -d "$media_dir" && -d "$media_dir/config" && -d "$media_dir/xiaoya" ]]; then
	            echo -e "\033[1;37m您选择的小雅EMBY媒体库路径是: \033[1;35m$media_dir\033[0m"
	            echo -e "\n"
	            read -ep "确认就按Y/y：" f12_select_3
	            if ! [[ $f12_select_3 == [Yy] ]]; then
					echo "选择错误，程序将退出。"
	            	exit 1
	            fi
	        else
	            echo "该路径不存在或该路径下没有config配置目录"
	            echo -e "\n"
	            echo -e "\033[1;31m您选择的个目录不正确，程序退出。\033[0m"
	            exit 1
	        fi
	    fi
	    echo -e "\n"
	else
		echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
        read media_dir
        echo -e "\n"
        if [[ -d "$media_dir" && -d "$media_dir/config" && -d "$media_dir/xiaoya" ]]; then
            echo -e "\033[1;37m您选择的小雅EMBY媒体库路径是: \033[1;35m$media_dir\033[0m"
            echo -e "\n"
            read -ep "确认就按Y/y：" f12_select_4
            if ! [[ $f12_select_4 == [Yy] ]]; then
				echo "选择错误，程序将退出。"
            	exit 1
            fi
        else
            echo "该路径不存在或该路径下没有config配置目录"
            echo -e "\n"
            echo -e "\033[1;31m您选择的个目录不正确，程序退出。\033[0m"
            exit 1
        fi
	fi
}
function11