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
	if docker pull $emby_image; then
		INFO "${emby_image}镜像拉取成功！"
	else
		ERROR "${emby_image}镜像拉取失败！"
		exit 1
	fi
}

function get_config_path(){
	docker_name=$(docker ps -a | grep xiaoya/alist | awk '{print $NF}')
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
	if [[ -n $media_dir ]];then
		media_dir=$(dirname "$media_dir")
		echo -e "\033[1;37m找到您的小雅EMBY媒体库路径是: \033[1;35m\n$media_dir\033[0m"
	    echo -e "\n"
	    read -ep "确认请按任意键，或者按N/n手动输入路径：" f12_select_2
	    if [[ $f12_select_2 == [Nn] ]]; then
			echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
			read media_dir
			check_path $media_dir
	    fi
	    echo -e "\n"
	else
		echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
		read media_dir
		check_path $media_dir
	fi
}

function user_select0(){
	timezone=$(cat /etc/timezone)
	if [ "$timezone" != "Asia/Shanghai" ]; then
		INFO "Asia/Shanghai" > /etc/timezone
		dpkg-reconfigure -f noninteractive tzdata
		INFO "时区已设置为中国上海"
	fi

	# 备份原有的/etc/apt/sources.list文件
	cp /etc/apt/sources.list /etc/apt/sources.list.bak

	# 写入新的软件源
	cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye main contrib non-free
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-updates main contrib non-free
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-backports main contrib non-free
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-backports main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bullseye-security main contrib non-free
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security bullseye-security main contrib non-free
EOF

	apt-get update

	if ! which docker >/dev/null 2>&1; then
		INFO "Docker未安装，即将安装Docker..."
		curl -fsSL https://get.docker.com | sh
	fi

	INFO "现在开始安装CasaOS..."
	wget -qO- https://get.casaos.io | bash

	INFO "CasaOS安装完成。"
}

function user_select1(){
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、安装/重装小雅ALIST\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、卸载小雅alist\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
	read -erp "请输入（1或2）：" u1_select
	if [[ $u1_select == 1 ]];then
		if [[ $st_alist =~ "已安装" ]];then
			WARN "您的小雅alist已安装，是否需要重装？"
			read -ep "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
			if [[ $re_setup == [Yy] ]];then
				check_env
				get_config_path
				INFO "小雅alist配置路径为：$config_dir"
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
			read -ep "请输入小雅alist的安装路径，使用默认的/etc/xiaoya可直接回车：" config_dir
			[[ -z $config_dir ]] && config_dir="/etc/xiaoya"
			check_path $config_dir
			INFO "小雅alist配置路径为：$config_dir"
		fi
		curl -o /tmp/update_new.sh https://xy.ggbond.org/xy/update_new.sh
		grep -q "长度不对" /tmp/update_new.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/update_new.sh; exit 1; }
		bash -c "$(cat /tmp/update_new.sh)" -s $config_dir host
		INFO "${Green}哇塞！你的小雅alist安装完成了！$NC"
	elif [[ $u1_select == 2 ]];then
		docker_name=$(docker ps -a | grep xiaoya/alist | awk '{print $NF}')
		ddocker stop $docker_name
		docker rm $docker_name
		INFO "$docker_name 容器已卸载"
	else
		INFO "您的输入有误，程序退出!"
		exit 1
	fi
}

function user_select2(){
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、安装/重装小雅EMBY\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、卸载小雅EMBY\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
	read -erp "请输入（1或2）：" u2_select
	if [[ $u2_select == 1 ]];then
		if [[ $st_alist =~ "未安装" ]];then
			ERROR "请先安装小雅alist，再执行本安装！"
			main
			return
		fi
		if [[ $st_emby =~ "已安装" ]];then
			WARN "您的小雅EMBY已安装，是否需要重装？"
			read -ep "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
			if [[ $re_setup == [Yy] ]];then
				check_env
				emby_name="emby"
				get_config_path
				get_emby_media_path $emby_name
				docker stop $emby_name
				docker rm $emby_name
			else
				main
				return
			fi
		else
			get_config_path
			echo -e "\033[1;35m请输入您的小雅EMBY媒体库路径:\033[0m"
			read media_dir
			check_path $media_dir	
		fi
		if [ -s $config_dir/docker_address.txt ]; then
			docker_addr=$(head -n1 $config_dir/docker_address.txt)
		else
			echo "请先配置 /etc/xiaoya/docker_address.txt，以便获取docker 地址"
			exit
		fi
		if ! [[ -d $media_dir/xiaoya ]] || ! [[ -d $media_dir/config ]];then
			WARN "您输入的媒体库目录不正确，请先获取媒体库元数据后再安装!"
		fi
		#INFO "正在设置媒体库权限，请耐心等候……"
		#chmod -R 777 $media_dir/xiaoya $media_dir/config
		get_emby_image
		INFO "开始安装EMBY……"
		host=$(echo $docker_addr|cut -f1,2 -d:)
		host_ip=$(grep -oP '\d+\.\d+\.\d+\.\d+' $config_dir/docker_address.txt)
		if ! [[ -f /etc/nsswitch.conf ]];then
			echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf	
		fi
		docker run -d --name emby \
		-v /etc/nsswitch.conf:/etc/nsswitch.conf \
		-v $media_dir/config:/config \
		-v $media_dir/xiaoya:/media \
		--user 0:0 \
		--net=host \
		--add-host="xiaoya.host:$host_ip" \
		--restart always $emby_image
		
		echo "${host}:6909" > $config_dir/emby_server.txt
		docker restart xiaoya
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
		INFO "请登陆${Green} $host:2345 ${NC}访问小雅EMBY，用户名：${Blue} xiaoya ${NC}，密码：${Green} 1234 ${NC}"
	elif [[ $u2_select == 2 ]];then
		INFO "正在卸载小雅EMBY……"
		docker stop emby
		docker rm emby
		docker rmi $emby_image
		INFO "小雅EMBY卸载完成！"
	else
		INFO "您的输入有误，程序退出!"
		exit 1
	fi
}
	
function user_select3(){
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、一键安装/重装小雅ALIST+EMBY\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、卸载小雅ALIST+EMBY\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
	read -erp "请输入（1或2）：" u3_select
	if [[ $u3_select == 1 ]];then
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
		INFO "全部安装完成，请登陆${Green} $host:2345 ${NC}访问小雅EMBY，用户名：${Blue} xiaoya ${NC}，密码：${Green} 1234 ${NC}"	
	elif [[ $u3_select == 2 ]];then
		INFO "正在卸载小雅EMBY……"
		docker stop emby
		docker rm emby
		docker rmi $emby_image
		INFO "小雅EMBY卸载完成！"
		
		INFO "正在卸载小雅ALIST……"
		docker_name=$(docker ps -a | grep xiaoya/alist | awk '{print $NF}')
		ddocker stop $docker_name
		docker rm $docker_name
		INFO "小雅ALIST卸载完成！"
	else
		INFO "您的输入有误，程序退出!"
		exit 1
	fi
}

function main(){
    clear
	st_alist=$(setup_status $(docker ps -a | grep xiaoya/alist | awk '{print $NF}'))
	st_emby=$(setup_status "emby")
	echo -e "\e[33m"
	echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
	echo -e "1、本脚本为小雅emby全家桶的安装脚本，使用于玩客云系统环境，不保证其他系统通用；"
	echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
	echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行，按CTRL+C立即退出；"
	echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://xy.ggbond.org/xy/3q.jpg\033[0m"
	echo -e "————————————————————————————————————\033[1;33m安  装  状  态\033[0m————————————————————————————————"
	echo -e "\e[0m"
	echo -e "小雅alist：${st_alist};          小雅emby：${st_emby}"
	echo -e "\e[0m"
	echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m0、一键安装casaos\033[0m"
    echo -e "\n"
	echo -e "\033[1;32m1、安装/重装/卸载小雅ALIST\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、安装/重装/卸载小雅emby\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m3、无脑一键全装/重装/卸载\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -ep "请输入您的选择（1-3或q退出）；" user_select
	case $user_select in
    0)
		clear
		user_select0;;
	1)
		clear
		user_select1;;
    2)
    	clear
    	user_select2;; 
    3)
		clear
		user_select3;;
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
    if [[ "$image" == "xiaoyaliu/alist:latest" ]] || [[ "$image" == "xiaoyaliu/alist:hostmode" ]] || [[ "$image" == "xiaoya/alist:hostmode" ]]; then
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