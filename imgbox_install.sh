#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2086

PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

Blue="\033[1;34m"
Green="\033[1;32m"
Red="\033[1;31m"
Yellow="\033[1;33m"
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

# 用grep -Eqi "QNAP" /etc/issue判断威联通系统
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

#获取小雅alist配置目录路径
function get_config_path() {
    docker_name=$(docker ps -a | grep ailg/alist | awk '{print $NF}')
    docker_name=${docker_name:-"xiaoya_jf"}
    if command -v jq > /dev/null 2>&1; then
        config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
    else
        #config_dir=$(docker inspect xiaoya | awk '/"Destination": "\/data"/{print a} {a=$0}'|awk -F\" '{print $4}')
        config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$docker_name")
    fi
    echo -e "\033[1;37m找到您的小雅ALIST配置文件路径是: \033[1;35m\n$config_dir\033[0m"
    echo -e "\n"
    f12_select_0=""
    t=10
    while [[ -z "$f12_select_0" && $t -gt 0 ]]; do
        printf "\r确认请按任意键，或者按N/n手动输入路径（注：上方显示多个路径也请选择手动输入）：（%2d 秒后将默认确认）：" $t
        read -r -t 1 -n 1 f12_select_0
        [ $? -eq 0 ] && break
        t=$((t - 1))
    done
    #read -erp "确认请按任意键，或者按N/n手动输入路径（注：上方显示多个路径也请选择手动输入）：" f12_select_0
    if [[ $f12_select_0 == [Nn] ]]; then
        echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
        read -r config_dir
        if [ -z $1 ];then
            if ! [[ -d "$config_dir" && -f "$config_dir/mytoken.txt" ]]; then
                ERROR "该路径不存在或该路径下没有mytoken.txt配置文件"
                ERROR "如果你是选择全新目录重装小雅alist，请先删除原来的容器，再重新运行本脚本！"
                ERROR -e "\033[1;31m您选择的目录不正确，程序退出。\033[0m"
                exit 1
            fi
        fi
    fi
    config_dir=${config_dir:-"/etc/xiaoya"}
}


#镜像代理的内容抄的DDSRem大佬的，适当修改了一下
function docker_pull() {
    mirrors=()
    INFO "正在从${config_dir}/docker_mirrors.txt文件获取代理点配置……"
    while IFS= read -r line; do
        mirrors+=("$line")
    done < "${config_dir}/docker_mirrors.txt"

    if command -v timeout > /dev/null 2>&1;then
        for mirror in "${mirrors[@]}"; do
            INFO "正在从${mirror}代理点为您下载镜像……"
            #local_sha=$(timeout 300 docker pull "${mirror}/${1}" 2>&1 | grep 'Digest: sha256' | awk -F':' '{print $3}')
            if command -v mktemp > /dev/null; then
                tempfile=$(mktemp)
            else
                tempfile="/tmp/tmp_sha"
            fi
            timeout 300 docker pull "${mirror}/${1}" | tee "$tempfile"
            local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
            echo -e "local_sha:${local_sha}"
            rm "$tempfile"

            if [ -n "${local_sha}" ]; then
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                [[ "${mirror}" == "docker.io" ]] && return 0
                break
            else
                WARN "${1} 镜像拉取失败，正在进行重试..."
            fi
        done
    else
        for mirror in "${mirrors[@]}"; do
            INFO "正在从${mirror}代理点为您下载镜像……"
            timeout=200
            (docker pull "${mirror}/${1}" 2>&1 | tee /dev/stderr | grep 'Digest: sha256' | awk -F':' '{print $3}' > "/tmp/tmp_sha") &
            pid=$!
            count=0
            while kill -0 $pid 2>/dev/null; do
                sleep 5
                count=$((count+5))
                if [ $count -ge $timeout ]; then
                    echo "Command timed out"
                    kill $pid
                    break
                fi
            done
            local_sha=$(cat "/tmp/tmp_sha")
            rm "/tmp/tmp_sha"
            if [ -n "${local_sha}" ]; then
                INFO "${1} 镜像拉取成功！"
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                echo -e "local_sha:${local_sha}"
                [[ "${mirror}" == "docker.io" ]] && return 0
                break
            else
                WARN "${1} 镜像拉取失败，正在进行重试..."
            fi
        done
    fi

    if [ -n "$(docker images -q "${mirror}/${1}")" ]; then
        docker tag "${mirror}/${1}" "${1}"
        docker rmi "${mirror}/${1}"
        return 0
    else
        ERROR "已尝试docker_mirrors.txt中所有镜像代理拉取失败，程序将退出，请检查网络后再试！"
        WARN "如需重测速选择代理，请手动删除${config_dir}/docker_mirrors.txt文件后重新运行脚本！"
        exit 1       
    fi
}

update_ailg() {
    [ -z "${config_dir}" ] && get_config_path
    if [[ -n "$1" ]];then
        update_img="$1"
    fi
    #local name_img
    #name_img=$(echo "${update_img}" | awk -F'[/:]' '{print $2}')
    #local tag_img
    #tag_img=$(echo "${update_img}" | awk -F'[/:]' '{print $3}')
    if [ -f $config_dir/ailg_sha.txt ]; then
        local_sha=$(grep -E "${update_img}" "$config_dir/ailg_sha.txt" | awk '{print $2}')
    else
        local_sha=$(docker inspect -f'{{index .RepoDigests 0}}' "${update_img}" | cut -f2 -d:)
    fi
    for i in {1..3}; do
        remote_sha=$(curl -sSLf https://xy.ggbond.org/xy/ailg_sha_remote.txt | grep -E "${update_img}" | awk '{print $2}')
        [ -n "${remote_sha}" ] && break
    done
    #remote_sha=$(curl -s -m 20 "https://hub.docker.com/v2/repositories/ailg/${name_img}/tags/${tag_img}" | grep -oE '[0-9a-f]{64}' | tail -1)
    #[ -z "${remote_sha}" ] && remote_sha=$(docker exec $docker_name cat "/${name_img}_${tag_img}_sha.txt")
    if [ ! "$local_sha" == "$remote_sha" ]; then
        docker rmi "${update_img}"
        retries=0
        max_retries=3
        while [ $retries -lt $max_retries ]; do
            if docker_pull "${update_img}"; then
                INFO "${update_img} 镜像拉取成功！"
                break
            else
                WARN "${update_img} 镜像拉取失败，正在进行第 $((retries + 1)) 次重试..."
                retries=$((retries + 1))
            fi
        done
        if [ $retries -eq $max_retries ]; then
            ERROR "镜像拉取失败，已达到最大重试次数！"
            exit 1
        fi
    elif [ -z "$local_sha" ] &&  [ -z "$remote_sha" ]; then
        docker_pull "${update_img}"
    fi
}

function user_select1() {
    WARN "安装g-box会卸载已安装的小雅alist和小雅tv-box以避免端口冲突！"
    read -erp "请选择：（确认按Y/y，否则按任意键返回！）" re_setup
    _update_img="ailg/g-box:hostmode"
    #清理旧容器并更新镜像
    if [[ $re_setup == [Yy] ]]; then
        image_keywords=("ailg/alist" "xiaoyaliu/alist" "ailg/g-box")
        for keyword in "${image_keywords[@]}"; do
            for container_id in $(docker ps -a | grep "$keyword" | awk '{print $1}'); do
                config_dir=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
                if docker rm -f "$container_id"; then
                    echo -e "${container_id}容器已删除！"
                fi
            done
        done

        update_ailg "${_update_img}"
    else
        main
        return
    fi
    
    #获取安装路径
    if [[ -n "$config_dir" ]]; then
        INFO "你原来小雅alist/tvbox的配置路径是：${Blue}${config_dir}${NC}，可使用原有配置继续安装！"
        read -erp "确认请按任意键，或者按N/n手动输入路径：" user_select_0
        if [[ $user_select_0 == [Nn] ]]; then
            echo -e "\033[1;35m请输入您的小雅g-box配置文件路径:\033[0m"
            read -r config_dir
            check_path $config_dir
            INFO "小雅g-box老G版配置路径为：$config_dir"
        fi
    else
        read -erp "请输入小雅g-box的安装路径，使用默认的/etc/xiaoya可直接回车：" config_dir
        [[ -z $config_dir ]] && config_dir="/etc/xiaoya"
        check_path $config_dir
        INFO "小雅g-box老G版配置路径为：$config_dir"
    fi

    docker run -d --name=g-box --net=host \
        -v "$config_dir":/data \
        --restart=always \
        ailg/g-box:hostmode

    if command -v ifconfig &> /dev/null; then
        localip=$(ifconfig -a|grep inet|grep -v 172. | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1)
    else
        localip=$(ip address|grep inet|grep -v 172. | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1|cut -f1 -d"/")
    fi

    echo "http://$localip:5678" > $config_dir/docker_address.txt
    [ ! -s $config_dir/infuse_api_key.txt ] && echo "e825ed6f7f8f44ffa0563cddaddce14d" > "$config_dir/infuse_api_key.txt"
    [ ! -s $config_dir/infuse_api_key_jf.txt ] && echo "aec47bd0434940b480c348f91e4b8c2b" > "$config_dir/infuse_api_key_jf.txt"
    [ ! -s $config_dir/emby_server.txt ] && echo "http://127.0.0.1:6908" > $config_dir/emby_server.txt
    [ ! -s $config_dir/jellyfin_server.txt ] && echo "http://127.0.0.1:6909" > $config_dir/jellyfin_server.txt

    INFO "${Blue}哇塞！你的小雅g-box老G版安装完成了！$NC"
    INFO "${Blue}如果你没有配置mytoken.txt和myopentoken.txt文件，请登陆\033[1;35mhttp://${localip}:4567\033[0m网页在'账号-详情'中配置！$NC"
}


function main() {
    clear
    echo -e "\e[33m"
    echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
    echo -e "1、本脚本为\033[1;35mG-Box\033[0m的安装脚本，使用于群晖系统环境，不保证其他系统通用；"
    echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
    echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行，按CTRL+C立即退出；"
    echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://xy.ggbond.org/xy/3q.jpg\033[0m"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;35m1、安装/重装G-Box老G版\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -erp "请输入您的选择（1-4或q退出）；" user_select
    case $user_select in
    1)
        clear
        user_select1
        ;;
    [Qq])
        exit 0
        ;;
    *)
        ERROR "输入错误，按任意键重新输入！"
        read -r -n 1
        main
        ;;
    esac
}


#检查用户路径输入
check_path() {
    dir_path=$1
    if [[ ! -d "$dir_path" ]]; then
        read -erp "您输入的目录不存在，按Y/y创建，或按其他键退出！" yn
        case $yn in
        [Yy]*)
            mkdir -p $dir_path
            if [[ ! -d $dir_path ]]; then
                echo "您的输入有误，目录创建失败，程序退出！"
                exit 1
            else
                chmod 777 $dir_path
                INFO "${dir_path}目录创建成功！"
            fi
            ;;
        *) exit 0 ;;
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

choose_mirrors() {
    [ -z "${config_dir}" ] && get_config_path check_docker
    mirrors=("docker.io" "docker.fxxk.dedyn.io" "docker.adysec.com" "registry-docker-hub-latest-9vqc.onrender.com" "docker.chenby.cn" "dockerproxy.com" "hub.uuuadc.top" "docker.jsdelivr.fyi" "docker.registry.cyou" "dockerhub.anzu.vip")
    declare -A mirror_total_delays
    if [ ! -f "${config_dir}/docker_mirrors.txt" ]; then
        echo -e "\033[1;32m正在进行代理测速，为您选择最佳代理……\033[0m"
        start_time=$SECONDS
        for i in "${!mirrors[@]}"; do
            total_delay=0
            success=true
            INFO "${mirrors[i]}代理点测速中……"
            for n in {1..3}; do
                output=$(
                    #curl -s -o /dev/null -w '%{time_total}' --head --request GET --connect-timeout 10 "${mirrors[$i]}"
                    curl -s -o /dev/null -w '%{time_total}' --head --request GET -m 10 "${mirrors[$i]}"
                    [ $? -ne 0 ] && success=false && break
                )
                total_delay=$(echo "$total_delay + $output" | awk '{print $1 + $3}')
            done
            if $success && docker pull "${mirrors[$i]}/library/hello-world:latest" > /dev/null; then
                INFO "${mirrors[i]}代理可用，测试完成！"
                mirror_total_delays["${mirrors[$i]}"]=$total_delay 
                docker rmi "${mirrors[$i]}/library/hello-world:latest" &> /dev/null
            else
                INFO "${mirrors[i]}代理测试失败，将继续测试下一代理点！"
                #break
            fi
        done
        if [ ${#mirror_total_delays[@]} -eq 0 ]; then
            #echo "docker.io" > "${config_dir}/docker_mirrors.txt"
            echo -e "\033[1;31m所有代理测试失败，检查网络或配置可用代理后重新运行脚本，请从主菜单手动退出！\033[0m"
        else
            sorted_mirrors=$(for k in "${!mirror_total_delays[@]}"; do echo $k ${mirror_total_delays["$k"]}; done | sort -n -k2)
            echo "$sorted_mirrors" | head -n 2 | awk '{print $1}' > "${config_dir}/docker_mirrors.txt"
            echo -e "\033[1;32m已为您选取两个最佳代理点并添加到了${config_dir}/docker_mirrors.txt文件中：\033[0m"
            cat ${config_dir}/docker_mirrors.txt
        fi
    end_time=$SECONDS
    execution_time=$((end_time - start_time))
    minutes=$((execution_time / 60))
    seconds=$((execution_time % 60))
    echo "代理测速用时：${minutes} 分 ${seconds} 秒"
    read -n 1 -s -p "$(echo -e "\033[1;32m按任意键继续！\n\033[0m")"
    fi 
}

fuck_docker() {
    clear
    echo -e "\n"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\033[1;37m1、本脚本首次运行会自动检测docker站点的连接性，并自动为您筛选连接性最好的docker镜像代理！\033[0m"
    echo -e "\033[1;37m2、代理配置文件docker_mirrors.txt默认存放在小雅alist的配置目录，如未自动找到请根据提示完成填写！\033[0m"
    echo -e "\033[1;37m3、如果您找到更好的镜像代理，可手动添加到docker_mirrors.txt中，一行一个，越靠前优化级越高！\033[0m"
    echo -e "\033[1;37m4、如果所有镜像代理测试失败，请勿继续安装并检查您的网络环境，不听劝的将大概率拖取镜像失败！\033[0m"
    echo -e "\033[1;37m5、代理测速正常2-3分钟左右，如某个代理测速卡很久，可按CTRL+C键终止执行，检查网络后重试（如DNS等）！\033[0m"
    echo -e "\033[1;33m6、仅首次运行或docker_mirrors.txt文件不存在或文件中代理失效时需要测速！为了后续顺利安装请耐心等待！\033[0m"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -n 1 -s -p "$(echo -e "\033[1;32m按任意键继续！\n\033[0m")"
}
fuck_docker
choose_mirrors
main
