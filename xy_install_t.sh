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
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

function root_need() {
    if [[ $EUID -ne 0 ]]; then
        ERROR '此脚本必须以 root 身份运行！'
        exit 1
    fi
}

function ___install_docker() {

    if ! which docker; then
        WARN "docker 未安装，脚本尝试自动安装..."
        wget -qO- get.docker.com | bash
        if which docker; then
            INFO "docker 安装成功！"
        else
            ERROR "docker 安装失败，请手动安装！"
            exit 1
        fi
    fi

}

install_package() {
    local package=$1
    local install_cmd="$2 $package"
    
    if ! which $package > /dev/null 2>&1; then
        WARN "$package 未安装，脚本尝试自动安装..."
        if eval "$install_cmd"; then
            INFO "$package 安装成功！"
        else
            ERROR "$package 安装失败，请手动安装！"
            exit 1
        fi
    fi
}

packages_need() {
    local update_cmd
    local install_cmd

    if [ -f /etc/debian_version ]; then
        update_cmd="apt update -y"
        install_cmd="apt install -y"
    elif [ -f /etc/redhat-release ]; then
        install_cmd="yum install -y"
    elif [ -f /etc/SuSE-release ]; then
        update_cmd="zypper refresh"
        install_cmd="zypper install"
    elif [ -f /etc/alpine-release ]; then
        install_cmd="apk add"
    elif [ -f /etc/arch-release ]; then
        update_cmd="pacman -Sy --noconfirm"
        install_cmd="pacman -S --noconfirm"
    else
        ERROR "不支持的操作系统."
        exit 1
    fi

    [ -n "$update_cmd" ] && eval "$update_cmd"
    install_package "curl" "$install_cmd"
    if ! which wget; then
		install_package "wget" "$install_cmd"
	fi
    ___install_docker
}


function check_space() {
	target_dir=$1
    free_size=$(df -P "$1" | tail -n1 | awk '{print $4}')
    free_size_G=$((free_size / 1024 / 1024))
	if [ "$free_size_G" -le "$2" ]; then
		ERROR "空间剩余容量不够：${free_size_G}G 小于最低要求${2}G"
		exit 1
	else
		INFO "磁盘可用空间：${free_size_G}G"
	fi
}

function get_emby_image() {
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        emby_image="emby/embyserver:4.8.0.56"
		;;
    "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
        emby_image="emby/embyserver_arm64v8:4.8.0.56"
        ;;
    "armv7l")
		emby_image="emby/embyserver_arm32v7:4.8.0.56"
		;;
	*)
        ERROR "不支持你的CPU架构：$cpu_arch"
        exit 1
        ;;
    esac
	for i in {1..3};do
		if docker pull $emby_image; then
			INFO "${emby_image}镜像拉取成功！"
			break
		fi
	done
	docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || (ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本，小雅媒体库在${media_dir}！" && exit 1)
}

#获取小雅alist配置目录路径
function get_config_path(){
	docker_name=$(docker ps -a | grep ailg/alist | awk '{print $NF}')
	if command -v jq;then
		config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
	else
		#config_dir=$(docker inspect xiaoya | awk '/"Destination": "\/data"/{print a} {a=$0}'|awk -F\" '{print $4}')
		config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$docker_name")
	fi
	echo -e "\033[1;37m找到您的小雅ALIST配置文件路径是: \033[1;35m\n$config_dir\033[0m"
    echo -e "\n"
    read -ep "确认请按任意键，或者按N/n手动输入路径（注：上方显示多个路径也请选择手动输入）：" f12_select_0
    if [[ $f12_select_0 == [Nn] ]]; then
		echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
        read config_dir
        if ! [[ -d "$config_dir" && -f "$config_dir/mytoken.txt" ]]; then
            ERROR "该路径不存在或该路径下没有mytoken.txt配置文件"
			ERROR "如果你是选择全新目录重装小雅alist，请先删除原来的容器，再重新运行本脚本！"
            ERROR -e "\033[1;31m您选择的目录不正确，程序退出。\033[0m"
            exit 1
        fi
    fi
}

function get_jf_media_path(){
	jf_name=${1:-jellyfin_xy}
	if command -v jq;then
		media_dir=$(docker inspect $jf_name | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
	else
		media_dir=$(docker inspect $jf_name | awk '/"Destination": "\/media"/{print a} {a=$0}'|awk -F\" '{print $4}')
	fi
	if [[ -n $media_dir ]];then
		media_dir=$(dirname "$media_dir")
		echo -e "\033[1;37m找到您的小雅姐夫媒体库路径是: \033[1;35m\n$media_dir\033[0m"
	    echo -e "\n"
	    read -ep "确认请按任意键，或者按N/n手动输入路径：" f12_select_2
	    if [[ $f12_select_2 == [Nn] ]]; then
			echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
			read media_dir
			check_path $media_dir
	    fi
	    echo -e "\n"
	else
		echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
		read media_dir
		check_path $media_dir
	fi
}

function get_emby_media_path(){
	emby_name=${1:-emby}
	if command -v jq;then
		media_dir=$(docker inspect $emby_name | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
	else
		media_dir=$(docker inspect $emby_name | awk '/"Destination": "\/media"/{print a} {a=$0}'|awk -F\" '{print $4}')
	fi
	if [[ -n $media_dir ]];then
		media_dir=$(dirname "$media_dir")
		echo -e "\033[1;37m找到您的小雅emby媒体库路径是: \033[1;35m\n$media_dir\033[0m"
	    echo -e "\n"
	    read -ep "确认请按任意键，或者按N/n手动输入路径：" f12_select_1
	    if [[ $f12_select_1 == [Nn] ]]; then
			echo -e "\033[1;35m请输入您的小雅emby媒体库路径:\033[0m"
			read media_dir
			check_path $media_dir
	    fi
	    echo -e "\n"
	else
		echo -e "\033[1;35m请输入您的小雅emby媒体库路径:\033[0m"
		read media_dir
		check_path $media_dir
	fi
}

meta_select() {
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、config.mp4 —— 小雅姐夫的配置目录数据\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、all.mp4 —— 除pikpak之外的所有小雅元数据\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m3、pikpak.mp4 —— pikpak元数据（需魔法才能观看）\033[0m"
    echo -e "\n"
	echo -e "\033[1;32m4、全部安装\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    echo -e "请选择您\033[1;31m需要安装\033[0m的元数据(输入序号，多项用逗号分隔）："
    read f8_select
	if ! [[ $f8_select =~ ^[1-4]([\,\，][1-4])*$ ]]; then
        echo "输入的序号无效，请输入1到3之间的数字。"
        exit 1
    fi
	
	if ! [[ $f8_select == "4" ]]; then
		files=("config_jf.mp4" "all_jf.mp4" "pikpak_jf.mp4")   
		for i in {1..3}
		do
			file=${files[$i-1]}
			if ! [[ $f8_select == *$i* ]];then
				sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
				sed -i "/7z.*$file/d" /tmp/update_meta_jf.sh
			else
				if [[ -f $media_dir/temp/$file ]] && ! [[ -f $media_dir/temp/$file.aria2 ]];then
					WARN "${Yellow}${file}文件已在${media_dir}/temp目录存在,是否要重新解压？$NC"
					read -ep "请选择：（是-按任意键，否-按N/n键）" yn
					if [[ $yn == [Nn] ]];then
						sed -i "/7z.*$file/d" /tmp/update_meta_jf.sh
						sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
					else
						remote_size=$(curl -sL -D - -o /dev/null --max-time 5 "$docker_addr/d/ailg_jf/${file}" | grep "Content-Length" | cut -d' ' -f2)
						local_size=$(du -b $media_dir/temp/$file | cut -f1)
						[[ $remote_size == "$local_size" ]] && sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
					fi
				fi
			fi
		done
	fi
}

function user_select1(){
	if [[ $st_alist =~ "已安装" ]];then
		WARN "您的小雅ALIST老G版已安装，是否需要重装？"
		read -ep "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
		if [[ $re_setup == [Yy] ]];then
			check_env
			get_config_path
			INFO "小雅ALIST老G版配置路径为：$config_dir"
			INFO "正在停止和删除旧的小雅alist容器"
			docker stop $docker_name
			docker rm $docker_name
			INFO "$docker_name 容器已删除"
		else
			main
			return
		fi
	else
		check_env
		INFO "正在检查和删除已安装的小雅alist"
		rm_alist
		INFO "原有小雅alist容器已删除"
		if [[ -n "$config_dir" ]]; then
			INFO "你原来小雅alist的配置路径是：${Blue}${config_dir}${NC}，可使用原有配置继续安装！"
			read -ep "确认请按任意键，或者按N/n手动输入路径：" user_select_0
			if [[ $user_select_0 == [Nn] ]]; then
				echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
				read config_dir
				check_path $config_dir
				INFO "小雅ALIST老G版配置路径为：$config_dir"
			fi
		else
			read -ep "请输入小雅alist的安装路径，使用默认的/etc/xiaoya可直接回车：" config_dir
			[[ -z $config_dir ]] && config_dir="/etc/xiaoya"
			check_path $config_dir
			INFO "小雅ALIST老G版配置路径为：$config_dir"
		fi	
	fi
	curl -o /tmp/update_new_jf.sh https://xy.ggbond.org/xy/update_new_jf.sh
	grep -q "长度不对" /tmp/update_new_jf.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/update_new_jf.sh; exit 1; }
	echo "http://127.0.0.1:6908" > $config_dir/emby_server.txt
	echo "http://127.0.0.1:6909" > $config_dir/jellyfin_server.txt
	bash -c "$(cat /tmp/update_new_jf.sh)" -s $config_dir host
	INFO "${Blue}哇塞！你的小雅ALIST老G版安装完成了！$NC"
}

function user_select2(){
	if [[ $st_alist =~ "未安装" ]];then
		ERROR "请先安装小雅ALIST老G版，再执行本安装！"
		main
		return
	fi
	if [[ $st_jf =~ "已安装" ]];then
		WARN "您的小雅姐夫已安装，是否需要重装？"
		read -ep "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
		if [[ $re_setup == [Yy] ]];then
			check_env
			get_config_path
			get_jf_media_path
			docker stop $jf_name
			docker rm $jf_name
		else
			main
			return
		fi
	else
		get_config_path
		echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
		read media_dir
		check_path $media_dir	
	fi
	if [ -s $config_dir/docker_address.txt ]; then
		docker_addr=$(head -n1 $config_dir/docker_address.txt)
	else
		echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
		exit
	fi
	mkdir -p $media_dir/xiaoya
	mkdir -p $media_dir/temp
	curl -o /tmp/update_meta_jf.sh https://xy.ggbond.org/xy/update_meta_jf.sh
	meta_select
	chmod 777 /tmp/update_meta_jf.sh
	docker run -i --security-opt seccomp=unconfined --rm --net=host -v /tmp:/tmp -v $media_dir:/media -v $config_dir:/etc/xiaoya -e LANG=C.UTF-8 ailg/ggbond:latest /tmp/update_meta_jf.sh
	#dir=$(find $media_dir -type d -name "*config*" -print -quit)
	mv "$media_dir/jf_config" "$media_dir/confg"
	chmod -R 777 $media_dir/confg
	chmod -R 777 $media_dir/xiaoya
	host=$(echo $docker_addr|cut -f1,2 -d:)
	host_ip=$(grep -oP '\d+\.\d+\.\d+\.\d+' $config_dir/docker_address.txt)
	if ! [[ -f /etc/nsswitch.conf ]];then
		echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf	
	fi
	docker run -d --name jellyfin_xy -v /etc/nsswitch.conf:/etc/nsswitch.conf \
	-v $media_dir/config:/config \
	-v $media_dir/xiaoya:/media \
	-v /$media_dir/config/cache:/cache \
	--user 0:0 \
	-p 6909:8096 \
	-p 6920:8920 \
	-p 1909:1900/udp \
	-p 7369:7359/udp \
	--privileged --add-host="xiaoya.host:$host_ip" --restart always nyanmisaka/jellyfin:240220-amd64-legacy
	INFO "${Blue}小雅姐夫安装完成，正在为您重启小雅alist！$NC"
	echo "${host}:6909" > $config_dir/emby_server.txt
	docker restart xiaoya_jf
	start_time=$(date +%s)
	TARGET_LOG_LINE_SUCCESS="success load storage: [/©️"
	while true; do
		line=$(docker logs "xiaoya_jf" 2>&1| tail -n 10)
		echo $line
		if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
			break
		fi
		current_time=$(date +%s)
		elapsed_time=$((current_time - start_time))
		if [ "$elapsed_time" -gt 300 ]; then
			echo "小雅alist未正常启动超时 5分钟，请检查小雅alist的安装！"
			break
		fi	
		sleep 3
	done
	INFO "请登陆${Blue} $host:2345 ${NC}访问小雅姐夫，用户名：${Blue} ailg ${NC}，密码：${Blue} 5678 ${NC}"
}
	
function user_select3(){
	user_select1
	start_time=$(date +%s)
	TARGET_LOG_LINE_SUCCESS="success load storage: [/©️"
	while true; do
		line=$(docker logs "xiaoya_jf" 2>&1| tail -n 10)
		echo $line
		if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
			break
		fi
		current_time=$(date +%s)
		elapsed_time=$((current_time - start_time))
		if [ "$elapsed_time" -gt 300 ]; then
			echo "小雅alist未正常启动超时 5分钟，程序将退出，请检查小雅alist的安装，或重启小雅alist后重新运行脚本！"
			exit
		fi	
		sleep 3
	done
	user_select2
}

function user_select4(){
	while :; do
		clear
		echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
		echo -e "\n"
		echo -e "A、安装小雅EMBY老G速装版会$Red删除原小雅emby容器，如需保留请退出脚本停止原容器进行更名！$Font"
		echo -e "\n"
		echo -e "B、完整版与小雅emby原版一样，Lite版无PikPak数据（适合无梯子用户），请按需选择！"
		echo -e "\n"
		echo -e "——————————————————————————————————————————————————————————————————————————————————"
		echo -e "\n"
		echo -e "\033[1;32m1、小雅EMBY老G速装 - 完整版\033[0m"
		echo -e "\n"
		echo -e "\033[1;35m2、小雅EMBY老G速装 - Lite版\033[0m"
		echo -e "\n"
		echo -e "——————————————————————————————————————————————————————————————————————————————————"
		read -ep "请输入您的选择（1-2，按b返回上级菜单或按q退出）；" f4_select
		case "$f4_select" in
		  1)
			emby_ailg="emby-ailg.mp4"
			emby_img="emby-ailg.img"
			space_need=80
			break ;;
		  2)
			emby_ailg="emby-ailg-lite.mp4"
			emby_img="emby-ailg-lite.img"
			space_need=60
			break ;;
		  [Bb])
			clear
			main
			break ;;
		  [Qq])
			exit ;;
		  *)
			ERROR "输入错误，按任意键重新输入！"
			read -n 1
			continue ;;
		esac
	done
	
	if [[ $st_alist =~ "未安装" ]];then
		ERROR "请先安装小雅ALIST老G版，再执行本安装！"
		main
		return
	fi
	check_env
	get_config_path
	docker exec $docker_name ali_clear -1 > /dev/null 2>&1
	echo -e "\033[1;35m请输入您的小雅emby镜像存放路径（请确保大于${space_need}G剩余空间！）:\033[0m"
	read image_dir
	check_path $image_dir
	check_space $image_dir $space_need
	if [[ $st_emby =~ "已安装" ]];then
		WARN "您的小雅emby已安装，是否需要重装？"
		read -ep "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
		if [[ $re_setup == [Yy] ]];then
			get_emby_media_path
			docker stop $emby_name
			docker rm $emby_name
		else
			main
			return
		fi
	else	
		echo -e "\033[1;35m请输入您的小雅emby媒体库挂载路径:\033[0m"
		echo -e "\033[1;35m注：建议尽量不与镜像存放目录在同一块硬盘（非必须）！\033[0m"
		read -erp "在此输入：" media_dir
		check_path $media_dir
		emby_name=emby
	fi
	if [ -s $config_dir/docker_address.txt ]; then
		docker_addr=$(head -n1 $config_dir/docker_address.txt)
	else
		echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
		exit
	fi
	umask 000
	start_time=$(date +%s)
	for i in {1..5};do
		remote_size=$(curl -sL -D - -o /dev/null --max-time 5 "$docker_addr/d/ailg_jf/emby/$emby_ailg" | grep "Content-Length" | cut -d' ' -f2 | tr -d '\r')
		[[ -n $remote_size ]] && break
	done
	[[ $remote_size lt 200 ]] && ERROR "获取文件大小失败，请检查网络后重新运行脚本！" && exit 1
	if [[ ! -f $media_dir/$emby_ailg ]] || [[ -f $media_dir/$emby_ailg.aria2 ]];then
		docker exec $docker_name ali_clear -1 > /dev/null 2>&1
		docker run --rm --net=host -v $image_dir:/image -v $media_dir:/temp ailg/ggbond \
		aria2c -o /temp/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/emby/$emby_ailg"
	fi
	local_size=$(du -b $media_dir/$emby_ailg | cut -f1)
	for i in {1..3}; do
		if [[ -f $media_dir/$emby_ailg.aria2 ]] || [[ $remote_size != "$local_size" ]]; then
			docker exec $docker_name ali_clear -1 > /dev/null 2>&1
			docker run --rm --net=host -v $image_dir:/image -v $media_dir:/temp ailg/ggbond \
			aria2c -o /temp/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/emby/$emby_ailg"
			local_size=$(du -b $media_dir/$emby_ailg | cut -f1)
		else
			break
		fi
	done

	[[ -f $media_dir/$emby_ailg.aria2 ]] || [[ $remote_size != "$local_size" ]] && ERROR "文件下载失败，请检查网络后重新运行脚本！" && WARN "未下完的文件存放在${media_dir}目录，以便您续传下载，如不再需要请手动清除！" && exit 1
	
	if [[ ! -f $image_dir/${emby_img} ]] || [[ $(du -b $image_dir/${emby_img} | cut -f1) != $((remote_size-10000000)) ]];then
		echo -e "\033[1;35m正在提取镜像文件，文件较大，请耐心等待……\033[0m"
		dd if=$media_dir/$emby_ailg of=$image_dir/${emby_img} bs=10MB skip=1
		INFO "镜像文件提取完成，已存放在$image_dir中！"
	else
		INFO "镜像文件已存在，如需重新提取请先在${image_dir}中手动删除后重新运行脚本！"
	fi
	
	INFO "挂载镜像文件中……"
	rm -f $media_dir/$emby_ailg
	
	loop_device=$(losetup -j "$image_dir/${emby_img}" | cut -d: -f1)
	if [[ -z "$loop_device" ]]; then
		loop_dev=$(losetup -f)
		losetup ${loop_dev} $image_dir/${emby_img}
	fi
	mount -o loop $image_dir/${emby_img} $media_dir
	INFO "镜像已成功挂载到$media_dir中！"
	#echo "$image_dir/${emby_img} $media_dir auto defaults,loop 0 0" >> /etc/fstab
	cp -f /etc/rc.local /etc/rc.local.bak
	sed -i '/mount -o loop .*\.img/d' /etc/rc.local
	if grep -q 'exit 0' /etc/rc.local; then
		sed -i "/exit 0/i\mount -o loop $image_dir/${emby_img} $media_dir" /etc/rc.local
	else
		echo "mount -o loop $image_dir/${emby_img} $media_dir" >> /etc/rc.local
	fi
	
	INFO "开始安装小雅emby……"
	host=$(echo $docker_addr|cut -f1,2 -d:)
	host_ip=$(echo $docker_addr | cut -d':' -f2 | tr -d '/')
	if ! [[ -f /etc/nsswitch.conf ]];then
		echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf	
	fi
	get_emby_image
	docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
	-v $media_dir/config:/config \
	-v $media_dir/xiaoya:/media \
	--user 0:0 \
	--net=host \
	--privileged --add-host="xiaoya.host:$host_ip" --restart always $emby_image

	current_time=$(date +%s)
	elapsed_time=$(awk -v start=$start_time -v end=$current_time 'BEGIN {printf "%.2f\n", (end-start)/60}')
	INFO "${Blue}恭喜您！小雅emby安装完成，安装时间为 ${elapsed_time} 分钟！$NC"
	INFO "请登陆${Blue} $host:2345 ${NC}访问小雅emby，用户名：${Blue} xiaoya ${NC}，密码：${Blue} 1234 ${NC}"
	INFO "注：如果$host:6908可访问，$host:2345访问失败（502/500等错误），按如下步骤排障：\n\t1、检查$config_dir/emby_server.txt文件中的地址是否正确指向emby的访问地址，即：$host:6908或http://127.0.0.1:6908\n\t2、地址正确重启你的小雅alist容器即可。"
}

function main(){
    clear
	st_alist=$(setup_status "$(docker ps -a | grep ailg/alist | awk '{print $NF}' | head -n1)")
	st_jf=$(setup_status "$(docker ps -a | grep nyanmisaka/jellyfin:240220 | awk '{print $NF}')")
	st_emby=$(setup_status "$(docker ps -a | grep -E 'emby/embyserver|amilys/embyserver' | awk '{print $NF}')")
	echo -e "\e[33m"
	echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
	echo -e "1、本脚本为小雅Jellyfin全家桶的安装脚本，使用于群晖系统环境，不保证其他系统通用；"
	echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
	echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行，按CTRL+C立即退出；"
	echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://xy.ggbond.org/xy/3q.jpg\033[0m"
	echo -e "————————————————————————————————————\033[1;33m安  装  状  态\033[0m————————————————————————————————"
	echo -e "\e[0m"
	echo -e "小雅ALIST老G版：${st_alist}         小雅姐夫（jellyfin）：${st_jf}		小雅emby：${st_emby}"
	echo -e "\e[0m"
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、安装/重装小雅ALIST老G版\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、安装/重装小雅姐夫（jellyfin）\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m3、无脑一键全装/重装小雅姐夫\033[0m"
    echo -e "\n"
	echo -e "\033[1;35m4、安装/重装小雅emby（老G速装版）\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -ep "请输入您的选择（1-4或q退出）；" user_select
	case $user_select in
    1)
		clear
		user_select1;;
    2)
    	clear
    	user_select2;; 
    3)
		clear
		user_select3;;
	4)
		clear
		user_select4;;
    [Qq])
        exit 0;;		
	*)
        ERROR "输入错误，按任意键重新输入！"
        read -n 1
    	main
	esac
}

setup_status() {
    if docker container inspect "${1}" > /dev/null 2>&1; then
        echo -e "${Green}已安装${NC}"
    else
        echo -e "${Red}未安装${NC}"
    fi
}

#检查用户路径输入
check_path() {
	dir_path=$1
	if [[ ! -d "$dir_path" ]]; then
		read -ep "您输入的目录不存在，按Y/y创建，或按其他键退出！" yn
		case $yn in
			[Yy]* )
				mkdir -p $dir_path
				if [[ ! -d $dir_path ]];then
					echo "您的输入有误，目录创建失败，程序退出！"
					exit 1 
				else
					chmod 777 $dir_path
					INFO "${dir_path}目录创建成功！"
				fi
				;;
			* ) exit 0;;
		esac
	fi
}

#安装环境检查
check_env() {
if ! which curl; then
	packages_need
	if ! which curl; then
		ERROR "curl 未安装，请手动安装！"
		exit 1
	fi
	if ! which wget; then
		ERROR "wget 未安装，请手动安装！"
		exit 1
	fi
	if ! which docker; then
		ERROR "docker 未安装，请手动安装！"
		exit 1
	fi
fi
}

#删除原来的小雅容器
rm_alist() {
for container in $(docker ps -aq)
do
    image=$(docker inspect --format '{{.Config.Image}}' "$container")
    if [[ "$image" == "xiaoyaliu/alist:latest" ]] || [[ "$image" == "xiaoyaliu/alist:hostmode" ]] || [[ "$image" == "ailg/alist:hostmode" ]]; then
		WARN "本安装会删除原有的小雅alist容器，按任意键继续，或按CTRL+C退出！"
		read -n 1
        echo "Deleting container $container using image $image ..."
		config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$container")
        docker stop "$container"
        docker rm "$container"
        echo "Container $container has been deleted."
    fi
done
}

main
