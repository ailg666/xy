#!/bin/bash

# ——————————————————————————————————————————————————————————————————————————————————
#  $$$$$$\          $$$$$$$\   $$$$$$\  $$\   $$\ 
# $$  __$$\         $$  __$$\ $$  __$$\ $$ |  $$ |
# $$ /  \__|        $$ |  $$ |$$ /  $$ |\$$\ $$  |
# $$ |$$$$\ $$$$$$\ $$$$$$$\ |$$ |  $$ | \$$$$  / 
# $$ |\_$$ |\______|$$  __$$\ $$ |  $$ | $$  $$<  
# $$ |  $$ |        $$ |  $$ |$$ |  $$ |$$  /\$$\ 
# \$$$$$$  |        $$$$$$$  | $$$$$$  |$$ /  $$ |
#  \______/         \_______/  \______/ \__|  \__|
#
# ——————————————————————————————————————————————————————————————————————————————————
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
#
# 作者很菜，无法经常更新，不保证适用每个人的环境，请勿用于商业用途；
#
# 如果您喜欢这个脚本，可以请我喝咖啡：https://ailg.ggbond.org/3q.jpg
# ——————————————————————————————————————————————————————————————————————————————————
# 小雅G-Box工具函数库
# ——————————————————————————————————————————————————————————————————————————————————    
# 包含以下功能模块:
# - 颜色输出函数
# - 系统检查和依赖安装
# - 通用工具函数
# - Docker相关操作
# - Emby 6908端口屏蔽功能（从DDS大佬脚本移植而来）
#
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
# ——————————————————————————————————————————————————————————————————————————————————

# ——————————————————————————————————————————————————————————————————————————————————
# 颜色输出函数
# ——————————————————————————————————————————————————————————————————————————————————
setup_colors() {
    Blue="\033[1;34m"
    Green="\033[1;32m"
    Red="\033[1;31m"
    Yellow="\033[1;33m"
    NC="\033[0m"
    INFO="[${Green}INFO${NC}]"
    ERROR="[${Red}ERROR${NC}]"
    WARN="[${Yellow}WARN${NC}]"
}

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}


command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        ERROR "此脚本必须以 root 身份运行！"
        INFO "请在ssh终端输入命令 'sudo -i' 回车，再输入一次当前用户密码，切换到 root 用户后重新运行脚本。"
        exit 1
    fi
}

check_env() {
    local required_commands=(
        "curl" "wget"
        "jq"
        "docker"
        "grep" "sed" "awk"
        "stat"
        "du" "df" "mount" "umount" "losetup"
        "ps" "kill"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            WARN "缺少命令: $cmd，尝试安装..."
            if ! install_command "$cmd"; then
                ERROR "安装 $cmd 失败，请手动安装后再运行脚本"
                return 1
            fi
        fi
    done

    if ! docker info &> /dev/null; then
        ERROR "Docker 未运行或者当前用户无权访问 Docker"
        return 1
    fi

    if ! grep -q 'alias gbox' /etc/profile; then
        echo -e "alias gbox='bash -c \"\$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)\"'" >> /etc/profile
    fi
    source /etc/profile

    emby_list=()
    emby_order=()
    img_order=()
    
    return 0
}

install_command() {
    local pkg="$1"

    case "$pkg" in
        "docker") 
            _install_docker
            return $?
            ;;
        "losetup"|"mount"|"umount") pkg="util-linux" ;;
        "kill"|"ps"|"pkill") pkg="procps" ;;
        "grep"|"cp"|"mv"|"awk"|"sed"|"stat"|"du"|"df") pkg="coreutils" ;;
    esac

    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get install -y "$pkg"
    elif command -v yum &> /dev/null; then
        yum makecache fast
        yum install -y "$pkg"
    elif command -v dnf &> /dev/null; then
        dnf makecache
        dnf install -y "$pkg"
    elif command -v zypper &> /dev/null; then
        zypper refresh
        zypper install -y "$pkg"
    elif command -v pacman &> /dev/null; then
        pacman -Sy
        pacman -S --noconfirm "$pkg"
    elif command -v brew &> /dev/null; then
        brew update
        brew install "$pkg"
    elif command -v apk &> /dev/null; then
        apk update
        apk add --no-cache "$pkg"
    elif command -v opkg &> /dev/null; then
        opkg update
        case "$pkg" in
            "awk") pkg="gawk" ;; 
            "stat") pkg="coreutils-stat" ;;
            "du"|"df") pkg="coreutils" ;;
            "mount"|"umount") pkg="mount-utils" ;;
            *) pkg="$pkg" ;;
        esac
        opkg install "$pkg"
    else
        ERROR "未找到支持的包管理器，请手动安装 $pkg"
        return 1
    fi

    if ! command -v "$pkg" &> /dev/null; then
        ERROR "$pkg 安装失败"
        return 1
    fi

    return 0
}

function _install_docker() {
    if ! command -v docker &> /dev/null; then
        WARN "docker 未安装，脚本尝试自动安装..."
        wget -qO- get.docker.com | bash
        if ! command -v docker &> /dev/null; then
            ERROR "docker 安装失败，请手动安装！"
            exit 1
        fi
    fi

    if ! docker info &> /dev/null; then
        ERROR "Docker 未运行或者当前用户无权访问 Docker"
        return 1
    fi
}

check_qnap() {
    if grep -Eqi "QNAP" /etc/issue > /dev/null 2>&1; then
        INFO "检测到您是QNAP威联通系统，正在尝试更新安装环境，以便速装emby/jellyfin……"
        
        if ! command -v opkg &> /dev/null; then
            wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | sh
            echo 'export PATH=$PATH:/opt/bin:/opt/sbin' >> ~/.profile
            source ~/.profile
        fi

        [ -f /bin/mount ] && mv /bin/mount /bin/mount.bak
        [ -f /bin/umount ] && mv /bin/umount /bin/umount.bak
        [ -f /usr/local/sbin/losetup ] && mv /usr/local/sbin/losetup /usr/local/sbin/losetup.bak

        opkg update

        for pkg in mount-utils losetup; do
            success=false
            for i in {1..3}; do
                if opkg install $pkg; then
                    success=true
                    break
                else
                    INFO "尝试安装 $pkg 失败，重试中 ($i/3)..."
                fi
            done
            if [ "$success" = false ]; then
                INFO "$pkg 安装失败，恢复备份文件并退出脚本。"
                [ -f /bin/mount.bak ] && mv /bin/mount.bak /bin/mount
                [ -f /bin/umount.bak ] && mv /bin/umount.bak /bin/umount
                [ -f /usr/local/sbin/losetup.bak ] && mv /usr/local/sbin/losetup.bak /usr/local/sbin/losetup
                exit 1
            fi
        done

        if [ -f /opt/bin/mount ] && [ -f /opt/bin/umount ] && [ -f /opt/sbin/losetup ]; then
            cp /opt/bin/mount /bin/mount
            cp /opt/bin/umount /bin/umount
            cp /opt/sbin/losetup /usr/local/sbin/losetup
            INFO "已完成安装环境更新！"
        else
            INFO "安装文件缺失，恢复备份文件并退出脚本。"
            [ -f /bin/mount.bak ] && mv /bin/mount.bak /bin/mount
            [ -f /bin/umount.bak ] && mv /bin/umount.bak /bin/umount
            [ -f /usr/local/sbin/losetup.bak ] && mv /usr/local/sbin/losetup.bak /usr/local/sbin/losetup
            exit 1
        fi
    fi
}


check_path() {
    dir_path=$1
    if [[ ! -d "$dir_path" ]]; then
        read -t 60 -erp "您输入的目录不存在，按Y/y创建，或按其他键退出！" yn || {
            echo ""
            INFO "等待输入超时，默认不创建目录并退出"
            exit 0
        }
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

setup_status() {
    if docker container inspect "${1}" > /dev/null 2>&1; then
        echo -e "${Green}已安装${NC}"
    else
        echo -e "${Red}未安装${NC}"
    fi
}

check_port() {
    local check_command result
    local port_conflict=0
    local port_conflict_list=()
    local ports_to_check=()

    case "$1" in
        "emby")
            ports_to_check=(6908)
            ;;
        "jellyfin")
            ports_to_check=(6909 6910)
            ;;
        "g-box")
            ports_to_check=(2345 2346 4567 5678 3002)
            ;;
        *)
            ports_to_check=("$1")
            ;;
    esac

    if [[ "${OSNAME}" = "macos" ]]; then
        check_command=lsof
    else
        if ! command -v netstat > /dev/null 2>&1; then
            if ! command -v lsof > /dev/null 2>&1; then
                WARN "未检测到 netstat 或 lsof 命令，跳过端口检查！"
                return 0
            else
                check_command=lsof
            fi
        else
            check_command=netstat
        fi
    fi

    for port in "${ports_to_check[@]}"; do
        if [ "${check_command}" == "netstat" ]; then
            if result=$(netstat -tuln | awk -v port="${port}" '$4 ~ ":"port"$"'); then
                if [ -z "${result}" ]; then
                    INFO "${port} 端口通过检测！"
                else
                    ERROR "${port} 端口被占用！"
                    echo "$(netstat -tulnp | awk -v port="${port}" '$4 ~ ":"port"$"')"
                    port_conflict=$((port_conflict + 1))
                    port_conflict_list+=($port)
                fi
            else
                WARN "检测命令执行错误，跳过 ${port} 端口检查！"
            fi
        elif [ "${check_command}" == "lsof" ]; then
            if ! lsof -i :"${port}" > /dev/null; then
                INFO "${port} 端口通过检测！"
            else
                ERROR "${port} 端口被占用！"
                echo "$(lsof -i :"${port}")"
                port_conflict=$((port_conflict + 1))
                port_conflict_list+=($port)
            fi
        fi
    done

    if [ $port_conflict -gt 0 ]; then
        ERROR "存在 ${port_conflict} 个端口冲突，冲突端口如下："
        for port in "${port_conflict_list[@]}"; do
            echo -e "${Red}端口 ${port} 被占用，请解决后重试！${NC}"
        done
    fi

    export PORT_CONFLICT_COUNT=$port_conflict
    export PORT_CONFLICT_LIST=("${port_conflict_list[@]}")

    return $port_conflict
}

check_space() {
    free_size=$(df -P "$1" | tail -n1 | awk '{print $4}')
    free_size_G=$((free_size / 1024 / 1024))
    if [ "$free_size_G" -lt "$2" ]; then
        ERROR "空间剩余容量不够：${free_size_G}G 小于最低要求${2}G"
        return 1
    else
        INFO "磁盘可用空间：${free_size_G}G"
        return 0
    fi
}

check_loop_support() {
    if [ ! -e /dev/loop-control ]; then
        if ! lsmod | awk '$1 == "loop"'; then
            if ! command -v modprobe &> /dev/null; then
                echo "modprobe command not found."
                return 1
            else
                if modprobe loop; then
                    if ! mknod -m 660 /dev/loop-control c 10 237; then
                        ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，请手动启用该功能后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！" && exit 1
                    fi
                else
                    ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，请手动启用该功能后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！" && exit 1
                fi
            fi
        fi
    fi

    test_loop_device=""
    
    if test_loop_device=$(losetup -f 2>/dev/null) && [ -n "$test_loop_device" ]; then
        if [ ! -e "$test_loop_device" ]; then
            loop_num=$(echo "$test_loop_device" | grep -o '[0-9]\+$')
            if ! mknod "$test_loop_device" b 7 "$loop_num" 2>/dev/null; then
                test_loop_device=""
            fi
        fi
    fi
    
    if [ -n "$test_loop_device" ]; then
        for i in {1..3}; do
            curl -o /tmp/loop_test.img https://ailg.ggbond.org/loop_test.img
            if [ -f /tmp/loop_test.img ] && [ $(stat -c%s /tmp/loop_test.img) -gt 1024000 ]; then
                break
            else
                rm -f /tmp/loop_test.img
            fi
        done
        if [ ! -f /tmp/loop_test.img ] || [ $(stat -c%s /tmp/loop_test.img) -le 1024000 ]; then
            ERROR "测试文件下载失败，请检查网络后重新运行脚本！" && exit 1
        fi
        if ! losetup -o 35 "$test_loop_device" /tmp/loop_test.img > /dev/null 2>&1; then
            ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，建议排查losetup命令后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！"
            rm -rf /tmp/loop_test.img
            exit 1
        else
            mkdir -p /tmp/loop_test
            if ! mount "$test_loop_device" /tmp/loop_test; then
                ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，建议排查mount命令后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！"
                rm -rf /tmp/loop_test /tmp/loop_test.img
                exit 1
            else
                umount /tmp/loop_test
                losetup -d "$test_loop_device"
                rm -rf /tmp/loop_test /tmp/loop_test.img
                return 0
            fi
        fi
    else
        ERROR "无法找到可用的loop设备进行测试，请检查系统loop设备支持！" && exit 1
    fi
}


function docker_pull() {
    [ -z "${config_dir}" ] && get_config_path
    
    if ! [[ "$skip_choose_mirror" == [Yy] ]]; then
        mirrors=()
        INFO "正在从${config_dir}/docker_mirrors.txt文件获取代理点配置……"
        if [ -f "${config_dir}/docker_mirrors.txt" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && mirrors+=("$line")
            done < "${config_dir}/docker_mirrors.txt"
        else
            ERROR "${config_dir}/docker_mirrors.txt 文件不存在！"
            return 1
        fi
        
        if command -v mktemp > /dev/null 2>&1; then
            tempfile=$(mktemp)
        else
            tempfile="/tmp/docker_pull_$$.tmp"
            touch "$tempfile"
        fi
        
        for mirror in "${mirrors[@]}"; do
            INFO "正在从${mirror}代理点为您下载镜像：${1}"
            
            if command -v timeout > /dev/null 2>&1; then
                timeout 300 docker pull "${mirror}/${1}" | tee "$tempfile"
            else
                (docker pull "${mirror}/${1}" 2>&1 | tee "$tempfile") &
                pull_pid=$!
                
                wait_time=0
                while kill -0 $pull_pid 2>/dev/null && [ $wait_time -lt 200 ]; do
                    sleep 5
                    wait_time=$((wait_time + 5))
                done
                
                if [ $wait_time -ge 200 ]; then
                    kill $pull_pid 2>/dev/null
                    wait $pull_pid 2>/dev/null
                    WARN "下载超时，正在尝试下一个镜像源..."
                    continue
                fi
            fi
            
            local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
            
            if [ -n "${local_sha}" ]; then
                INFO "${1} 镜像拉取成功！"
                if [ -f "${config_dir}/ailg_sha.txt" ]; then
                    sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                fi
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                
                [[ "${mirror}" == "docker.io" ]] && rm -f "$tempfile" && return 0
                
                if [ "${mirror}/${1}" != "${1}" ]; then
                    docker tag "${mirror}/${1}" "${1}" && docker rmi "${mirror}/${1}"
                fi
                
                rm -f "$tempfile"
                return 0
            else
                WARN "${1} 从 ${mirror} 拉取失败，正在尝试下一个镜像源..."
            fi
        done
        
        rm -f "$tempfile"        
        ERROR "已尝试所有镜像源，均无法拉取 ${1}，请检查网络后再试！"
        WARN "如需重新测速选择代理，请删除 ${config_dir}/docker_mirrors.txt 文件后重新运行脚本！"
        return 1
    else
        INFO "正在从官方源拉取镜像：${1}"
        tempfile="/tmp/docker_pull_$$.tmp"
        
        docker pull "${1}" | tee "$tempfile"
        local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
        rm -f "$tempfile"
        
        if [ -n "${local_sha}" ]; then
            INFO "${1} 镜像拉取成功！"
            if [ -f "${config_dir}/ailg_sha.txt" ]; then
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
            fi
            echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
            return 0
        else
            ERROR "${1} 镜像拉取失败！"
            return 1
        fi
    fi
}

update_ailg() {
    [ -n "$1" ] && update_img="$1" || { ERROR "未指定更新镜像的名称"; exit 1; }
    [ -z "${config_dir}" ] && get_config_path
    
    local containers_info_file=""
    local containers_count=0
    
    local processed_containers=()
    
    if command -v jq &> /dev/null; then
        containers_info_file="/tmp/containers_${update_img//[:\/]/_}.json"
        INFO "检查是否有容器依赖镜像 ${update_img}..."
        for container_id in $(docker ps -a --filter "ancestor=${update_img}" --format "{{.ID}}"); do
            local already_processed=0
            for processed_id in "${processed_containers[@]}"; do
                if [[ "$processed_id" == "$container_id" ]]; then
                    already_processed=1
                    break
                fi
            done
            
            if [[ $already_processed -eq 1 ]]; then
                continue
            fi
            
            processed_containers+=("$container_id")
            containers_count=$((containers_count + 1))
            
            docker inspect "$container_id" >> "$containers_info_file"
            
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
            INFO "找到依赖容器: $container_name (ID: $container_id)"
            
            INFO "删除容器 $container_name..."
            docker rm -f "$container_id"
        done
    else
        containers_info_file="/tmp/containers_${update_img//[:\/]/_}.txt"
        INFO "检查是否有容器依赖镜像 ${update_img}..."
        for container_id in $(docker ps -a --filter "ancestor=${update_img}" --format "{{.ID}}"); do
            local already_processed=0
            for processed_id in "${processed_containers[@]}"; do
                if [[ "$processed_id" == "$container_id" ]]; then
                    already_processed=1
                    break
                fi
            done
            
            if [[ $already_processed -eq 1 ]]; then
                continue
            fi
            
            processed_containers+=("$container_id")
            containers_count=$((containers_count + 1))
            
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
            INFO "找到依赖容器: $container_name (ID: $container_id)"
            
            container_status=$(docker inspect --format '{{.State.Status}}' "$container_id")
            echo "CONTAINER_STATUS=$container_status" >> "$containers_info_file"
            
            echo "CONTAINER_NAME=$container_name" >> "$containers_info_file"
            
            network_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container_id")
            echo "NETWORK_MODE=$network_mode" >> "$containers_info_file"
            
            restart_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$container_id")
            echo "RESTART_POLICY=$restart_policy" >> "$containers_info_file"
            
            privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$container_id")
            echo "PRIVILEGED=$privileged" >> "$containers_info_file"
            
            echo "MOUNTS_START" >> "$containers_info_file"
            docker inspect "$container_id" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}} {{end}}{{end}}' >> "$containers_info_file"
            echo "MOUNTS_END" >> "$containers_info_file"
            
            echo "ENV_START" >> "$containers_info_file"
            docker inspect --format '{{range .Config.Env}}{{.}} {{end}}' "$container_id" >> "$containers_info_file"
            echo "ENV_END" >> "$containers_info_file"
            
            echo "PORTS_START" >> "$containers_info_file"
            docker inspect --format '{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}:{{$p}} {{end}}' "$container_id" >> "$containers_info_file"
            echo "PORTS_END" >> "$containers_info_file"
            
            echo "CONTAINER_END" >> "$containers_info_file"
            
            INFO "删除容器 $container_name..."
            docker rm -f "$container_id"
        done
    fi
    
    docker rmi "${update_img}_old" > /dev/null 2>&1
    docker tag "${update_img}" "${update_img}_old" > /dev/null 2>&1
    
    if [ -f $config_dir/ailg_sha.txt ]; then
        local_sha=$(grep -E "${update_img}" "$config_dir/ailg_sha.txt" | awk '{print $2}')
    else
        local_sha=$(docker inspect -f'{{index .RepoDigests 0}}' "${update_img}" 2>/dev/null | cut -f2 -d:)
    fi
    
    for i in {1..3}; do
        remote_sha=$(curl -sSLf https://ailg.ggbond.org/ailg_sha_remote.txt | grep -E "${update_img}" | awk '{print $2}')
        [ -n "${remote_sha}" ] && break
    done
    echo "remote_sha: $remote_sha"
    echo "local_sha: $local_sha"

    if [ -z "${remote_sha}" ]; then
        local org_name=$(echo "${update_img}" | cut -d'/' -f1)
        local img_name=$(echo "${update_img}" | cut -d'/' -f2 | cut -d':' -f1)
        local tag=$(echo "${update_img}" | cut -d'/' -f2 | cut -d':' -f2)
        for i in {1..3}; do
            remote_sha=$(curl -s -m 20 "https://hub.docker.com/v2/repositories/${org_name}/${img_name}/tags/${tag}" | grep -oE '[0-9a-f]{64}' | tail -1)
            [ -n "${remote_sha}" ] && break
        done
    fi

    if [ "$local_sha" != "$remote_sha" ] || { [ -z "$local_sha" ] && [ -z "$remote_sha" ]; } || ! docker inspect "${update_img}" &>/dev/null; then
        docker rmi "${update_img}" > /dev/null 2>&1
        
        retries=0
        max_retries=3
        update_success=false
        
        while [ $retries -lt $max_retries ]; do
            if docker_pull "${update_img}"; then
                INFO "${update_img} 镜像拉取成功！"
                update_success=true
                break
            else
                WARN "${update_img} 镜像拉取失败，正在进行第 $((retries + 1)) 次重试..."
                retries=$((retries + 1))
            fi
        done
        
        if [ "$update_success" = true ]; then
            INFO "镜像更新成功，准备恢复容器..."
            docker rmi "${update_img}_old" > /dev/null 2>&1
            
            if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
                if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                    restore_containers "$containers_info_file" "${update_img}"
                else
                    restore_containers_simple "$containers_info_file" "${update_img}"
                fi
            fi
            
            return 0
        else
            ERROR "${update_img} 镜像拉取失败，已达到最大重试次数！将回滚到旧版本..."
            docker tag "${update_img}_old" "${update_img}" > /dev/null 2>&1
            
            if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
                if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                    restore_containers "$containers_info_file" "${update_img}"
                else
                    restore_containers_simple "$containers_info_file" "${update_img}"
                fi
            fi
            
            docker rmi "${update_img}_old" > /dev/null 2>&1
            return 1
        fi
    else
        INFO "${update_img} 镜像已是最新版本，无需更新！"
        docker rmi "${update_img}_old" > /dev/null 2>&1
        if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
            if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                restore_containers "$containers_info_file" "${update_img}"
            else
                restore_containers_simple "$containers_info_file" "${update_img}"
            fi
        fi
        return 0
    fi
}

restore_containers() {
    local containers_file="$1"
    local image_name="$2"
    local restored_count=0
    local failed_count=0
    
    INFO "开始恢复依赖镜像 ${image_name} 的容器..."
    
    for container_id in $(jq -r '.[].Id' "$containers_file"); do
        local container_json=$(jq -r ".[] | select(.Id==\"$container_id\")" "$containers_file")
        local name=$(echo "$container_json" | jq -r '.Name' | sed 's/^\///')
        local network_mode=$(echo "$container_json" | jq -r '.HostConfig.NetworkMode')
        local restart_policy=$(echo "$container_json" | jq -r '.HostConfig.RestartPolicy.Name')
        
        local mounts=""
        while read -r mount; do
            local source=$(echo "$mount" | jq -r '.Source')
            local destination=$(echo "$mount" | jq -r '.Destination')
            local type=$(echo "$mount" | jq -r '.Type')
            local vol_name=$(echo "$mount" | jq -r '.Name')
            
            if [ "$type" != "volume" ] || [ -n "$vol_name" ]; then
                if [[ "$source" != *"@docker/volumes"* ]]; then
                    [ -n "$source" ] && [ -n "$destination" ] && mounts="$mounts -v $source:$destination"
                fi
            fi
        done < <(echo "$container_json" | jq -c '.Mounts[]?')
        
        local env_vars=""
        while read -r env; do
            [ -n "$env" ] && env_vars="$env_vars -e \"$env\""
        done < <(echo "$container_json" | jq -r '.Config.Env[]?')
        
        local ports=""
        local port_bindings=$(echo "$container_json" | jq -r '.HostConfig.PortBindings')
        if [ "$port_bindings" != "null" ] && [ "$port_bindings" != "{}" ]; then
            while read -r port_mapping; do
                local container_port=$(echo "$port_mapping" | cut -d: -f1)
                local host_port=$(echo "$port_mapping" | cut -d: -f2)
                [ -n "$container_port" ] && [ -n "$host_port" ] && ports="$ports -p $host_port:$container_port"
            done < <(echo "$port_bindings" | jq -r 'to_entries[] | "\(.key):\(.value[0].HostPort)"')
        fi
        
        local privileged=$(echo "$container_json" | jq -r '.HostConfig.Privileged')
        local privileged_param=""
        [ "$privileged" = "true" ] && privileged_param="--privileged"
        
        local run_cmd="docker run -d --name \"$name\" $privileged_param"
        
        if [ "$network_mode" = "host" ]; then
            run_cmd="$run_cmd --net=host"
        elif [ -n "$network_mode" ] && [ "$network_mode" != "default" ]; then
            run_cmd="$run_cmd --net=$network_mode"
        fi
        
        if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
            run_cmd="$run_cmd --restart=$restart_policy"
        fi
        
        [ -n "$mounts" ] && run_cmd="$run_cmd $mounts"
        [ -n "$env_vars" ] && run_cmd="$run_cmd $env_vars"
        [ -n "$ports" ] && run_cmd="$run_cmd $ports"
        
        run_cmd="$run_cmd $image_name"
        
        
        container_status=$(echo "$container_json" | jq -r '.State.Status')
        INFO "恢复容器 $name..."
        if eval "$run_cmd"; then
            if [ "$container_status" = "running" ]; then
                INFO "容器 $name 恢复并启动成功"
            else
                INFO "容器 $name 恢复成功，正在恢复到原始状态（停止）..."
                docker stop "$name" > /dev/null 2>&1
                INFO "容器 $name 已停止，与原始状态一致"
            fi
            restored_count=$((restored_count + 1))
        else
            ERROR "容器 $name 恢复失败"
            failed_count=$((failed_count + 1))
        fi
    done
    
    rm -f "$containers_file"
    
    INFO "容器恢复完成: 成功 $restored_count, 失败 $failed_count"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

restore_containers_simple() {
    local containers_file="$1"
    local image_name="$2"
    local restored_count=0
    local failed_count=0
    
    INFO "开始恢复依赖镜像 ${image_name} 的容器..."
    
    local container_name=""
    local network_mode=""
    local restart_policy=""
    local privileged=""
    local mounts=""
    local env_vars=""
    local ports=""
    local in_mounts=0
    local in_env=0
    local in_ports=0
    local container_status=""
    
    while IFS= read -r line; do
        if [[ "$line" == CONTAINER_NAME=* ]]; then
            if [ -n "$container_name" ]; then
                restore_single_container
                container_name=""
                network_mode=""
                restart_policy=""
                privileged=""
                mounts=""
                env_vars=""
                ports=""
            fi
            container_name="${line#CONTAINER_NAME=}"
        elif [[ "$line" == NETWORK_MODE=* ]]; then
            network_mode="${line#NETWORK_MODE=}"
        elif [[ "$line" == RESTART_POLICY=* ]]; then
            restart_policy="${line#RESTART_POLICY=}"
        elif [[ "$line" == PRIVILEGED=* ]]; then
            privileged="${line#PRIVILEGED=}"
        elif [[ "$line" == "MOUNTS_START" ]]; then
            in_mounts=1
        elif [[ "$line" == "MOUNTS_END" ]]; then
            in_mounts=0
        elif [[ "$line" == "ENV_START" ]]; then
            in_env=1
        elif [[ "$line" == "ENV_END" ]]; then
            in_env=0
        elif [[ "$line" == "PORTS_START" ]]; then
            in_ports=1
        elif [[ "$line" == "PORTS_END" ]]; then
            in_ports=0
        elif [[ "$line" == CONTAINER_STATUS=* ]]; then
            container_status="${line#CONTAINER_STATUS=}"
        elif [[ "$line" == "CONTAINER_END" ]]; then
            restore_single_container
            container_name=""
            network_mode=""
            restart_policy=""
            privileged=""
            mounts=""
            env_vars=""
            ports=""
            container_status=""
        elif [ $in_mounts -eq 1 ]; then
            mounts="$line"
        elif [ $in_env -eq 1 ]; then
            env_vars="$line"
        elif [ $in_ports -eq 1 ]; then
            ports="$line"
        fi
    done < "$containers_file"
    
    if [ -n "$container_name" ]; then
        restore_single_container
    fi
    
    rm -f "$containers_file"
    
    INFO "容器恢复完成: 成功 $restored_count, 失败 $failed_count"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
    
    function restore_single_container() {
        local run_cmd="docker run -d --name \"$container_name\""
        
        if [ "$network_mode" = "host" ]; then
            run_cmd="$run_cmd --net=host"
        elif [ -n "$network_mode" ] && [ "$network_mode" != "default" ]; then
            run_cmd="$run_cmd --net=$network_mode"
        fi
        
        if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
            run_cmd="$run_cmd --restart=$restart_policy"
        fi
        
        if [ "$privileged" = "true" ]; then
            run_cmd="$run_cmd --privileged"
        fi
        
        for mount in $mounts; do
            if [[ "$mount" == *":"* ]]; then
                run_cmd="$run_cmd -v $mount"
            fi
        done
        
        for env in $env_vars; do
            if [ -n "$env" ]; then
                run_cmd="$run_cmd -e \"$env\""
            fi
        done
        
        for port in $ports; do
            if [[ "$port" == *":"* ]]; then
                run_cmd="$run_cmd -p $port"
            fi
        done
        
        run_cmd="$run_cmd $image_name"
        
        INFO "恢复容器 $container_name..."
        if eval "$run_cmd"; then
            if [ "$container_status" = "running" ]; then
                INFO "容器 $container_name 恢复并启动成功"
            else
                INFO "容器 $container_name 恢复成功，正在恢复到原始状态（停止）..."
                docker stop "$container_name" > /dev/null 2>&1
                INFO "容器 $container_name 已停止，与原始状态一致"
            fi
            restored_count=$((restored_count + 1))
        else
            ERROR "容器 $container_name 恢复失败"
            failed_count=$((failed_count + 1))
        fi
    }
}

xy_media_reunzip() {
    running_container_id=""
    
    trap 'echo -e "\n${INFO} 检测到Ctrl+C，立即终止脚本"; exit 1' SIGINT
    
    FILE_OPTIONS=(
        "all.mp4"
        "115.mp4"
        "pikpak.mp4"
        "json.mp4"
        "短剧.mp4"
        "蓝光原盘.mp4"
        "config.mp4"
        "music.mp4"
    )
    
    FILE_DIRS=(
        "📺画质演示测试（4K，8K，HDR，Dolby） 动漫 每日更新 测试 电影 电视剧 纪录片 纪录片（已刮削） 综艺 音乐"
        "115"
        "PikPak"
        "json"
        "短剧"
        "ISO"
        "config"
        "Music"
    )

    cleanup() {
        INFO "Attempting cleanup..."

        local script_pid=$$
        
        if command -v pkill &>/dev/null; then
            pkill -TERM -P $script_pid 2>/dev/null || true
            sleep 1
            pkill -KILL -P $script_pid 2>/dev/null || true
        else
            if command -v ps &>/dev/null; then
                local child_pids=$(ps -o pid --no-headers --ppid $script_pid 2>/dev/null)
                if [ -n "$child_pids" ]; then
                    INFO "终止子进程: $child_pids"
                    for pid in $child_pids; do
                        kill -TERM $pid 2>/dev/null || true
                    done
                    sleep 1
                    for pid in $child_pids; do
                        kill -KILL $pid 2>/dev/null || true
                    done
                fi
            else
                WARN "无法终止子进程: ps和pkill命令均不可用"
            fi
        fi
        
        if [ -n "$running_container_id" ]; then
            INFO "Stopping running Docker container..."
            docker stop $running_container_id >/dev/null 2>&1 || true
            docker rm $running_container_id >/dev/null 2>&1 || true
        fi
        
        if [ -n "$img_mount" ] && mount | grep -q " ${img_mount} "; then
            INFO "Unmounting ${img_mount}..."
            umount "${img_mount}" || WARN "Failed to unmount ${img_mount}"
        fi
        
        INFO "Cleanup attempt finished."
        
        exit 1
    }
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    prepare_directories() {
        for file_to_download in "${files_to_process[@]}"; do
            local idx=-1
            for i in "${!FILE_OPTIONS[@]}"; do
                if [ "${FILE_OPTIONS[$i]}" = "$file_to_download" ]; then
                    idx=$i
                    break
                fi
            done
            
            if [ $idx -ge 0 ]; then
                local dir_names_str="${FILE_DIRS[$idx]}"
                if [ "$file_to_download" == "config.mp4" ]; then
                    INFO "删除旧的config目录: ${img_mount}/config"
                    rm -rf "${img_mount:?}/config" # Protect against empty vars
                else
                    IFS=' ' read -r -a dir_array <<< "$dir_names_str"
                    for dir_name_part in "${dir_array[@]}"; do
                        if [ -n "$dir_name_part" ]; then # Ensure not empty
                            INFO "删除旧的数据目录: ${img_mount}/xiaoya/${dir_name_part}"
                            rm -rf "${img_mount:?}/xiaoya/${dir_name_part:?}"
                        fi
                    done
                fi
            fi
        done
    }

    download_and_extract() {
        local file_to_download=$1
        INFO "处理文件: $file_to_download"
        
        local skip_download=false
        if [ -f "${source_dir}/${file_to_download}" ] && [ ! -f "${source_dir}/${file_to_download}.aria2" ]; then
            INFO "文件 ${file_to_download} 已存在且下载完成，跳过下载步骤"
            skip_download=true
        fi

        if update_ailg ailg/ggbond:latest; then
            INFO "ailg/ggbond:latest 镜像更新成功！"
        else
            ERROR "ailg/ggbond:latest 镜像更新失败，请检查网络后重新运行脚本！"
            return 1
        fi
        
        handle_interrupt() {
            INFO "检测到中断，正在清理..."
            
            if [ -n "$running_container_id" ]; then
                docker stop $running_container_id >/dev/null 2>&1 || true
                docker rm $running_container_id >/dev/null 2>&1 || true
                running_container_id=""
            fi
            
            local script_pid=$$
            
            if command -v pkill &>/dev/null; then
                pkill -TERM -P $script_pid 2>/dev/null || true
            else
                if command -v ps &>/dev/null; then
                    local child_pids=$(ps -o pid --no-headers --ppid $script_pid 2>/dev/null)
                    if [ -n "$child_pids" ]; then
                        INFO "终止子进程: $child_pids"
                        for pid in $child_pids; do
                            kill -TERM $pid 2>/dev/null || true
                        done
                    fi
                fi
            fi
            
            exit 1
        }
        
        trap handle_interrupt SIGINT SIGTERM
        
        if [ "$skip_download" = true ]; then
            running_container_id=$(docker run -d --rm --net=host \
                -v "${source_dir}:/source_temp_dir" \
                -v "${img_mount}:/dist" \
                ailg/ggbond:latest \
                bash -c "cd /source_temp_dir && \
                        echo '正在解压 ${file_to_download}...' && \
                        if [ \"$file_to_download\" = \"config.mp4\" ]; then \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/\" ; \
                        else \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/xiaoya\" ; \
                        fi")
            
            docker wait $running_container_id >/dev/null 2>&1
            extract_status=$?
            running_container_id=""
        else
            running_container_id=$(docker run -d --rm --net=host \
                -v "${source_dir}:/source_temp_dir" \
                -v "${img_mount}:/dist" \
                ailg/ggbond:latest \
                bash -c "cd /source_temp_dir && \
                        echo '正在下载 ${file_to_download}...' && \
                        aria2c -o \"${file_to_download}\" --auto-file-renaming=false --allow-overwrite=true -c -x6 \"${xiaoya_addr}/d/元数据/${file_to_download}\" && \
                        echo '正在解压 ${file_to_download}...' && \
                        if [ \"$file_to_download\" = \"config.mp4\" ]; then \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/\" ; \
                        else \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/xiaoya\" ; \
                        fi")
            
            docker wait $running_container_id >/dev/null 2>&1
            extract_status=$?
            running_container_id=""
        fi
        
        trap cleanup EXIT SIGHUP SIGINT SIGTERM
        
        if [ $extract_status -eq 0 ]; then
            INFO "√ $file_to_download 处理成功."
            return 0
        else
            ERROR "× $file_to_download 处理失败."
            return 1
        fi
    }

    get_remote_file_sizes() {
        local files_to_check=("$@")
        local total_size_bytes=0
        
        for file_to_check in "${files_to_check[@]}"; do
            INFO "获取远程文件 $file_to_check 的大小..."
            local remote_file_url="${xiaoya_addr}/d/元数据/${file_to_check}"
            local remote_size=0
            local attempts=0
            local max_attempts=3
            
            while [ $attempts -lt $max_attempts ]; do
                let attempts+=1
                INFO "尝试 $attempts/$max_attempts 获取 $file_to_check 的远程大小"
                remote_size=$(curl -sL -D - --max-time 10 "$remote_file_url" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r' | tail -n1)
                
                if [[ "$remote_size" =~ ^[0-9]+$ ]] && [ "$remote_size" -gt 10000000 ]; then
                    INFO "成功获取 $file_to_check 的远程大小: $remote_size 字节"
                    break
                else
                    WARN "获取 $file_to_check 的远程大小失败 (得到 '$remote_size')，尝试 $attempts/$max_attempts"
                    if [ $attempts -lt $max_attempts ]; then
                        sleep 2
                    fi
                    remote_size=0
                fi
            done
            if [ "$remote_size" -eq 0 ]; then
                ERROR "无法获取 $file_to_check 的远程大小"
                exit 1
            fi
            
            total_size_bytes=$((total_size_bytes + remote_size))
            if [ -f "${source_dir}/${file_to_check}" ]; then
                local local_size_bytes=$(stat -c%s "${source_dir}/${file_to_check}")
                if [ "$remote_size" -ne "$local_size_bytes" ]; then
                INFO "本地文件 $file_to_check 大小($local_size_bytes 字节)与远程文件大小($remote_size 字节)不一致，需要重新下载"
                rm -f "${source_dir}/${file_to_check}"
                fi
            fi
        done

        total_size_gb=$((total_size_bytes / 1024 / 1024 / 1024 + 5))
        INFO "所有选定文件所需总大小为: $total_size_gb GB"
    }

    media_reunzip_main() {
        if [[ $st_gbox =~ "未安装" ]]; then
            ERROR "请先安装G-Box，再执行本安装！"
            main_menu
            return
        fi

        WARN "当前此功能只适配4.9版本的emby，如果是4.8版的不要用此功能更新config"
        WARN "可以用此功能更新4.8版emby的其他元数据，不要更新config,否则会emby无法启动!"
        WARN "如果用此功能更新4.8版config之外的元数据，需要自己手动添加媒体库后扫描媒体库完成更新和入库！"
        read -p "是否继续? (y/n): " confirm_continue
        if [[ ! "$confirm_continue" =~ ^[Yy]$ ]]; then
            main_menu
            return
        fi

        mount_img || exit 1
        
        INFO "当前挂载模式: $mount_type"
        if [ -n "${emby_name}" ]; then
            if ! docker stop "${emby_name}" > /dev/null 2>&1; then
                WARN "停止容器 ${emby_name} 失败"
                exit 1
            fi
        fi
        [ -z "${config_dir}" ] && get_config_path

        if [ -s $config_dir/docker_address.txt ]; then
            xiaoya_addr=$(head -n1 $config_dir/docker_address.txt)
        else
            echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
            exit
        fi   
        if ! curl -siL "${xiaoya_addr}/d/README.md" | grep -v 302 | grep -q "x-oss-"; then
            ERROR "无法连接到小雅alist: $xiaoya_addr"
            exit 1
        fi
        
        docker_addr="$xiaoya_addr"
        
        echo -e "\n请选择要重新下载和解压的文件:"
        
        if [[ "$mount_type" == "config" ]]; then
            WARN "当前为config镜像挂载模式，只能选择 config.mp4 文件"
        elif [[ "$mount_type" == "media" ]]; then
            WARN "当前为媒体库镜像挂载模式，不能选择 config.mp4 文件"
        fi
        
        selected_status=()
        for ((i=0; i<${#FILE_OPTIONS[@]}; i++)); do
            selected_status[i]=0
        done
        
        while true; do
            for index in "${!FILE_OPTIONS[@]}"; do
                local file_opt="${FILE_OPTIONS[$index]}"
                local status_char="×"; local color="$Red"
                local disabled=""
                
                if [[ "$mount_type" == "config" && "$file_opt" != "config.mp4" ]]; then
                    status_char="❌"; color="$Red"
                    disabled=" (不可选择)"
                elif [[ "$mount_type" == "media" && "$file_opt" == "config.mp4" ]]; then
                    status_char="❌"; color="$Red"
                    disabled=" (不可选择)"
                elif [ "${selected_status[$index]}" -eq 1 ]; then 
                    status_char="√"; color="$Green"
                fi
                
                printf "[ %-1d ] ${color}[%s] %s${NC}%s\n" $((index + 1)) "$status_char" "$file_opt" "$disabled"
            done
            printf "[ 0 ] 确认并继续\n"
            
            local select_input
            read -t 60 -erp "请输入序号(0-${#FILE_OPTIONS[@]})，可用逗号分隔多选，或按Ctrl+C退出: " select_input || {
                echo ""
                INFO "等待输入超时，请重新输入或按Ctrl+C退出"
                continue
            }
            
            if [[ "$select_input" == "0" ]]; then
                local count_selected=0
                for ((i=0; i<${#selected_status[@]}; i++)); do
                    if [ "${selected_status[$i]}" -eq 1 ]; then 
                        let count_selected+=1
                    fi
                done
                if [ $count_selected -eq 0 ]; then 
                    ERROR "至少选择一个文件"
                else 
                    break
                fi
                continue
            fi
            
            select_input=${select_input//，/,}
            
            IFS=',' read -ra select_nums <<< "$select_input"
            
            for select_num in "${select_nums[@]}"; do
                select_num=$(echo "$select_num" | tr -d ' ')
                
                if [[ "$select_num" =~ ^[0-9]+$ ]]; then
                    if [ "$select_num" -ge 1 ] && [ "$select_num" -le ${#FILE_OPTIONS[@]} ]; then
                        idx=$((select_num-1))
                        local file_to_select="${FILE_OPTIONS[$idx]}"
                        
                        local selection_valid=true
                        if [[ "$mount_type" == "config" && "$file_to_select" != "config.mp4" ]]; then
                            ERROR "配置镜像模式下只能选择 config.mp4 文件"
                            selection_valid=false
                        elif [[ "$mount_type" == "media" && "$file_to_select" == "config.mp4" ]]; then
                            ERROR "媒体库镜像模式下不能选择 config.mp4 文件"
                            selection_valid=false
                        fi
                        
                        if [ "$selection_valid" = true ]; then
                            selected_status[$idx]=$((1 - selected_status[$idx]))
                            if [ "${selected_status[$idx]}" -eq 1 ]; then
                                INFO "已选择: ${FILE_OPTIONS[$idx]}"
                            else
                                INFO "已取消选择: ${FILE_OPTIONS[$idx]}"
                            fi
                        fi
                    else 
                        ERROR "无效序号: $select_num，请输入1-${#FILE_OPTIONS[@]}之间的数字"
                    fi
                else 
                    ERROR "无效输入: $select_num，请输入数字"
                fi
            done
        done
        
        files_to_process=()
        for index in "${!FILE_OPTIONS[@]}"; do
            if [ "${selected_status[$index]}" -eq 1 ]; then
                files_to_process+=("${FILE_OPTIONS[$index]}")
            fi
        done
        
        INFO "将处理以下文件: ${files_to_process[*]}"
        
        while true; do
            read -t 60 -erp "请输入临时存放下载文件的目录（默认：/tmp/xy_reunzip_source）: " source_dir || {
                echo ""
                INFO "等待输入超时，请重新输入或按Ctrl+C退出"
                continue
            }
            source_dir=${source_dir:-/tmp/xy_reunzip_source}
            check_path "$source_dir"
            
            get_remote_file_sizes "${files_to_process[@]}"

            if check_space "$source_dir" "$total_size_gb"; then
                break
            else
                read -t 60 -erp "是否选择其他目录? (y/n): " choose_another || {
                    echo ""
                    INFO "等待输入超时，默认选择其他目录"
                    choose_another="y"
                }
                if [[ ! "$choose_another" =~ ^[Yy]$ ]]; then
                    ERROR "由于空间不足，脚本终止"
                    exit 1
                fi
            fi
        done

        prepare_directories
        
        required_intermediate_gb=$(awk "BEGIN {printf \"%.0f\", $total_size_gb * 1.5}")
        
        if ! check_space "$img_mount" "$required_intermediate_gb"; then
            WARN "${img_path}镜像空间不足，请在一键脚本主菜单选择X再选择6对其扩容后重试！"
            exit 1
        fi

        
        for file_to_process in "${files_to_process[@]}"; do
            if ! download_and_extract "$file_to_process"; then
                ERROR "文件 $file_to_process 处理失败，请手动删除${source_dir}/${file_to_process}文件"
            else
                rm -f "${source_dir}/${file_to_process}"
            fi
        done
        
        INFO "所有文件处理完成"
        umount "$img_mount" && INFO "镜像卸载完成" || WARN "卸载 $img_mount 失败"
        [ -n "${emby_name}" ] && docker start "${emby_name}" || INFO "容器 ${emby_name} 未启动"
        
        INFO "脚本执行完成"
    }
    media_reunzip_main "$@"
}

setup_colors

export Blue Green Red Yellow NC INFO ERROR WARN


get_docker0_ip() {
    if command -v ifconfig > /dev/null 2>&1; then
        docker0=$(ifconfig docker0 | awk '/inet / {print $2}' | sed 's/addr://')
    else
        docker0=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d '/' -f 1)
    fi
    echo "$docker0"
}

wait_emby_start() {
    local container_name="$1"
    local TARGET_LOG_LINE_SUCCESS="All entry points have started"
    local start_time=$(date +%s)
    
    INFO "等待Emby容器 ${container_name} 启动..."
    while true; do
        local line=$(docker logs "$container_name" 2>&1 | tail -n 10)
        echo -e "$line"
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]] && [ "$elapsed_time" -gt 10 ]; then
            INFO "Emby容器 ${container_name} 启动成功！"
            return 0
        fi
        
        if [ "$elapsed_time" -gt 900 ]; then
            WARN "Emby容器 ${container_name} 未正常启动超时 15 分钟！"
            return 1
        fi
        sleep 8
    done
}

wait_gbox_start() {
    local container_name="$1"
    local TARGET_LOG_LINE_SUCCESS="load storages completed"
    local start_time=$(date +%s)
    local timeout=600  # 10分钟超时
    
    INFO "等待G-Box容器 ${container_name} 启动..."
    
    timeout $timeout docker exec "$container_name" tail -f /opt/alist/log/alist.log 2>&1 | while IFS= read -r line; do
        echo -e "$line"
        
        if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
            INFO "G-Box容器 ${container_name} 启动成功！"
            kill -USR1 $$ 2>/dev/null || true
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        if [ "$elapsed_time" -gt $timeout ]; then
            WARN "G-Box容器 ${container_name} 未正常启动超时 10 分钟！"
            kill -USR2 $$ 2>/dev/null || true
            break
        fi
    done
    
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
        WARN "G-Box容器 ${container_name} 未正常启动超时 10 分钟！"
        return 1
    elif [ $exit_code -eq 0 ]; then
        return 0
    else
        WARN "G-Box容器 ${container_name} 启动过程中出现错误！"
        return 1
    fi
}

emby_close_6908_port() {
    echo -e "${Yellow}此功能关闭 6908 访问是通过将 Emby 设置为桥接模式并取消端口映射，非防火墙屏蔽！！！${Font}"
    echo -e "${Yellow}如果您使用此功能关闭 6908 访问，那您无法再使用浏览器访问 6908 端口使用 Emby！！！${Font}"
    echo -e "${Yellow}如果您需要访问 Emby 并且走服务端流量，可以访问 2347 端口，此端口与 6908 逻辑一致！！！${Font}"
    echo -e "${Yellow}正常使用依旧是访问 2345 端口即可愉快观影！！！${Font}"
    echo -e "${Yellow}此功能移植自DDSREM大佬的脚本，特此感谢DDSREM！${Font}"
    
    local OPERATE
    while true; do
        INFO "是否继续操作 [Y/n]（默认 Y）"
        read -erp "OPERATE:" OPERATE
        [[ -z "${OPERATE}" ]] && OPERATE="y"
        if [[ ${OPERATE} == [YyNn] ]]; then
            break
        else
            ERROR "非法输入，请输入 [Y/n]"
        fi
    done
    if [[ "${OPERATE}" == [Nn] ]]; then
        return 0
    fi

    get_config_path
    local gbox_name="$docker_name"
    local config_dir="$config_dir"
    
    local emby_name="$(docker ps -a -q | while read container_id; do
        if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "$container_id" | grep -qE "/xiaoya$ /media|\.img /media\.img"; then
            image_name=$(docker inspect --format '{{.Config.Image}}' "$container_id")
            if [[ "$image_name" == *"emby"* ]]; then
                container_name=$(docker ps -a --format '{{.Names}}' --filter "id=$container_id")
                echo "$container_name"
                break
            fi
        fi
    done | head -n1)"
    
    emby_name=${emby_name:-emby}
    
    INFO "检测到G-Box容器: ${gbox_name}"
    INFO "检测到Emby容器: ${emby_name}"
    INFO "使用配置目录: ${config_dir}"

    local NETWORK_NAME="only_for_emby"
    local SUBNET_CANDIDATES=("10.250.0.0/24" "10.250.1.0/24" "10.250.2.0/24" "10.251.0.0/24")
    local AVAILABLE_SUBNET ENBY_IP GATEWAY
    
    if docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
        local CONTAINERS=$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$NETWORK_NAME")
        if [ -n "$CONTAINERS" ]; then
            INFO "以下容器正在使用该网络，将被强制断开:"
            INFO "$CONTAINERS"
            for container in $CONTAINERS; do
                INFO "正在断开容器 $container ..."
                docker network disconnect -f "$NETWORK_NAME" "$container"
            done
        fi
        docker network rm "$NETWORK_NAME"
        INFO "旧 ${NETWORK_NAME} 网络已删除"
    fi

    for subnet in "${SUBNET_CANDIDATES[@]}"; do
        local conflict=0
        local existing_networks config
        existing_networks=$(docker network ls --quiet)
        for net_id in $existing_networks; do
            config=$(docker network inspect "$net_id" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
            if [ "$config" = "$subnet" ]; then
                conflict=1
                break
            fi
        done
        if [ "$conflict" -eq 0 ]; then
            AVAILABLE_SUBNET="$subnet"
            break
        fi
    done
    
    if [ -z "$AVAILABLE_SUBNET" ]; then
        ERROR "所有候选子网均已被占用，请手动删除冲突的子网"
        return 1
    fi
    
    GATEWAY="${AVAILABLE_SUBNET//0\/24/1}"
    ENBY_IP="${AVAILABLE_SUBNET//0\/24/100}"
    
    INFO "正在创建网络 $NETWORK_NAME，使用子网 $AVAILABLE_SUBNET，网关 $GATEWAY..."
    docker network create \
        --driver bridge \
        --subnet "$AVAILABLE_SUBNET" \
        --gateway "$GATEWAY" \
        "$NETWORK_NAME"
    INFO "网络 $NETWORK_NAME 创建成功！"

    if docker inspect ddsderek/runlike:latest > /dev/null 2>&1; then
        local local_sha remote_sha
        local_sha=$(docker inspect --format='{{index .RepoDigests 0}}' ddsderek/runlike:latest 2> /dev/null | cut -f2 -d:)
        remote_sha=$(curl -s -m 10 "https://hub.docker.com/v2/repositories/ddsderek/runlike/tags/latest" | grep -o '"digest":"[^"]*' | grep -o '[^"]*$' | tail -n1 | cut -f2 -d:)
        if [ "$local_sha" != "$remote_sha" ]; then
            docker rmi ddsderek/runlike:latest
            docker_pull "ddsderek/runlike:latest"
        fi
    else
        docker_pull "ddsderek/runlike:latest"
    fi
    
    INFO "获取 ${emby_name} 容器信息中..."
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /tmp:/tmp ddsderek/runlike -p "${emby_name}" > "/tmp/container_update_${emby_name}"
    
    INFO "更改 Emby 为 only_for_emby 模式并取消端口映射中..."
    if grep -q 'network=host' "/tmp/container_update_${emby_name}"; then
        INFO "更改 host 网络模式为 only_for_emby 模式"
        sed -i "s/network=host/network=only_for_emby --ip=${ENBY_IP}/" "/tmp/container_update_${emby_name}"
    elif grep -q 'network=only_for_emby' "/tmp/container_update_${emby_name}"; then
        INFO "重新配置 only_for_emby 网络模式"
        sed -i "s/network=bridge/network=only_for_emby --ip=${ENBY_IP}/" "/tmp/container_update_${emby_name}"
    else
        INFO "添加 only_for_emby 网络模式"
        sed -i "s/name=${emby_name}/name=${emby_name} --network=only_for_emby --ip=${ENBY_IP}/" "/tmp/container_update_${emby_name}"
    fi
    
    if grep -q '6908:6908' "/tmp/container_update_${emby_name}"; then
        INFO "关闭 6908 端口映射"
        sed -i '/-p 6908:6908/d' "/tmp/container_update_${emby_name}"
    fi
    
    local docker0 xiaoya_host
    docker0=$(get_docker0_ip)
    xiaoya_host=$(ip route get 223.5.5.5 | grep -oE 'src [0-9.]+' | grep -oE '[0-9.]+' | head -1) 
    
    INFO "更改容器 host 配置"
    sed -i "s/--add-host xiaoya.host.*/--add-host xiaoya.host:${xiaoya_host} \\\/" "/tmp/container_update_${emby_name}"
    
    if ! docker stop "${emby_name}" > /dev/null 2>&1; then
        if ! docker kill "${emby_name}" > /dev/null 2>&1; then
            ERROR "停止 ${emby_name} 容器失败！"
            return 1
        fi
    fi
    INFO "停止 ${emby_name} 容器成功！"
    
    if ! docker rm --force "${emby_name}" > /dev/null 2>&1; then
        ERROR "删除 ${emby_name} 容器失败！"
        return 1
    fi
    
    if bash "/tmp/container_update_${emby_name}"; then
        rm -f "/tmp/container_update_${emby_name}"
        wait_emby_start "$emby_name"
    else
        ERROR "创建 ${emby_name} 容器失败！"
        return 1
    fi
    
    local gbox_network_mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "${gbox_name}")
    if [[ "$gbox_network_mode" == "bridge" ]]; then
        INFO "G-Box容器使用bridge网络模式，自动加入 only_for_emby 网络中..."
        docker network connect only_for_emby "${gbox_name}"
    elif [[ "$gbox_network_mode" == "host" ]]; then
        INFO "G-Box容器使用host网络模式，无需额外网络配置"
    else
        INFO "G-Box容器使用 ${gbox_network_mode} 网络模式，尝试连接到 only_for_emby 网络..."
        docker network connect only_for_emby "${gbox_name}" 2>/dev/null || WARN "无法将G-Box容器连接到 only_for_emby 网络"
    fi
    
    local new_config="http://$ENBY_IP:6908"
    local config_file="${config_dir}/emby_server.txt"
    local need_restart=false
    
    if [[ ! -f "$config_file" ]] || [[ "$(cat "$config_file" 2>/dev/null)" != "$new_config" ]]; then
        INFO "配置 emby_server.txt 文件中"
        echo "$new_config" > "$config_file"
        chown -R 0:0 "$config_file" 2>/dev/null || true
        need_restart=true
        INFO "emby_server.txt 配置已更新"
    else
        INFO "emby_server.txt 配置无需更新，内容相同"
    fi
    
    if [[ "$need_restart" == "true" ]]; then
        INFO "重启G-Box容器"
        docker restart "${gbox_name}"
        wait_gbox_start "$gbox_name"
    else
        INFO "G-Box容器无需重启，配置未变更"
    fi
    
    INFO "关闭 Emby 6908 端口完成！"
    INFO "现在只能通过 2345 端口访问 Emby，6908 端口已被屏蔽！"
}


cleanup_invalid_loops() {
    local img_path="$1"
    INFO "开始清理无效的loop设备绑定..." >&2
    
    local protected_loops=""
    
    if [ -n "$img_path" ]; then
        local img_dir=$(dirname "$img_path")
        local loop_file="$img_dir/.loop"
        
        if [ -f "$loop_file" ]; then
            local media_loop=$(grep "^media " "$loop_file" 2>/dev/null | awk '{print $2}')
            local config_loop=$(grep "^config " "$loop_file" 2>/dev/null | awk '{print $2}')
            
            if [ -n "$media_loop" ]; then
                protected_loops="$protected_loops $media_loop"
                INFO "保护media loop设备: $media_loop (来自 $loop_file)" >&2
            fi
            if [ -n "$config_loop" ]; then
                protected_loops="$protected_loops $config_loop"
                INFO "保护config loop设备: $config_loop (来自 $loop_file)" >&2
            fi
        else
            INFO "未找到.loop文件: $loop_file" >&2
        fi
    else
        INFO "未提供img_path参数，跳过保护检查" >&2
    fi
    
    local loop_devices=$(losetup -a)
    local cleaned_count=0
    
    echo "$loop_devices" | while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        local loop_device=$(echo "$line" | cut -d: -f1)
        local back_file=""
        
        local is_protected=false
        for protected_loop in $protected_loops; do
            if [ "$loop_device" = "$protected_loop" ]; then
                is_protected=true
                break
            fi
        done
        
        if [ "$is_protected" = true ]; then
            INFO "跳过受保护的loop设备: $loop_device" >&2
            continue
        fi
        
        if echo "$line" | grep -q "("; then
            back_file=$(echo "$line" | sed 's/.*(\([^)]*\)).*/\1/')
        else
            back_file=$(echo "$line" | awk '{print $NF}')
        fi
        
        local should_cleanup=false
        
        if [ "$back_file" = "/" ]; then
            should_cleanup=true
            INFO "发现绑定到根目录的loop设备: $loop_device" >&2
        elif [[ "$back_file" =~ ^/[^/]*\.img$ ]] && [ "$back_file" != "/config.img" ] && [ "$back_file" != "/media.img" ]; then
            should_cleanup=true
            INFO "发现无效绑定的loop设备: $loop_device -> $back_file" >&2
        fi
        
        if [ "$should_cleanup" = true ]; then
            INFO "正在清理loop设备: $loop_device" >&2
            
            if umount -l "$loop_device" 2>/dev/null; then
                INFO "成功卸载: $loop_device" >&2
            else
                INFO "卸载失败或未挂载: $loop_device" >&2
            fi
            
            if losetup -d "$loop_device" 2>/dev/null; then
                if ! losetup -a | grep -q "^$loop_device:"; then
                    INFO "成功解除绑定: $loop_device" >&2
                    cleaned_count=$((cleaned_count + 1))
                else
                    WARN "解除绑定命令执行成功但设备仍存在: $loop_device" >&2
                fi
            else
                WARN "解除绑定失败: $loop_device" >&2
            fi
        fi
        
    done
    
    if [ $cleaned_count -gt 0 ]; then
        INFO "清理完成，共清理了 $cleaned_count 个无效的loop设备" >&2
    else
        INFO "未发现需要清理的无效loop设备" >&2
    fi
}

get_loop_from_state_file() {
    local img_file="$1"
    local img_dir=$(dirname "$img_file")
    local img_name=$(basename "$img_file")
    local state_file=""
    
    if [[ "$img_name" =~ ^emby-ailg.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-ailg.*\.img$ ]]; then
        state_file="$img_dir/.loop"
    elif [[ "$img_name" =~ ^emby-config.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-config.*\.img$ ]]; then
        state_file="$img_dir/.loop"
    else
        return 1
    fi
    
    if [ -f "$state_file" ]; then
        local img_type=""
        local img_name=$(basename "$img_file")
        
        if [[ "$img_name" =~ ^emby-ailg.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-ailg.*\.img$ ]]; then
            img_type="media"
        elif [[ "$img_name" =~ ^emby-config.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-config.*\.img$ ]]; then
            img_type="config"
        else
            return 1
        fi
        
        local recorded_loop=$(grep "^$img_type " "$state_file" | awk '{print $2}')
        if [ -n "$recorded_loop" ]; then
            echo "$recorded_loop"
            return 0
        fi
    fi
    
    return 1
}

update_loop_state_file() {
    local img_file="$1"
    local loop_device="$2"
    local img_dir=$(dirname "$img_file")
    local img_name=$(basename "$img_file")
    local state_file=""
    
    if [[ "$img_name" =~ ^emby-ailg.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-ailg.*\.img$ ]]; then
        state_file="$img_dir/.loop"
    elif [[ "$img_name" =~ ^emby-config.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-config.*\.img$ ]]; then
        state_file="$img_dir/.loop"
    else
        ERROR "不支持的镜像文件类型: $img_name"
        return 1
    fi
    
    mkdir -p "$img_dir"
    
    local img_type=""
    local img_name=$(basename "$img_file")
    
    if [[ "$img_name" =~ ^emby-ailg.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-ailg.*\.img$ ]]; then
        img_type="media"
    elif [[ "$img_name" =~ ^emby-config.*\.img$ ]] || [[ "$img_name" =~ ^jellyfin-config.*\.img$ ]]; then
        img_type="config"
    else
        ERROR "不支持的镜像文件类型: $img_name"
        return 1
    fi
    
    local temp_file=$(mktemp)
    local updated=false
    
    if [ -f "$state_file" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^$img_type\  ]]; then
                echo "$img_type $loop_device $img_file" >> "$temp_file"
                updated=true
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$state_file"
    fi
    
    if [ "$updated" = false ]; then
        echo "$img_type $loop_device $img_file" >> "$temp_file"
    fi
    
    mv "$temp_file" "$state_file"
    INFO "已更新状态文件: $state_file -> $img_type: $loop_device" >&2
}

check_loop_binding() {
    local img_file="$1"
    local loop_device="$2"
    
    local binding_info=$(losetup -a | grep "^$loop_device:")
    if [ -n "$binding_info" ]; then
        local bound_file=""
        
        if echo "$binding_info" | grep -q "("; then
            bound_file=$(echo "$binding_info" | sed 's/.*(\([^)]*\)).*/\1/')
        else
            bound_file=$(echo "$binding_info" | awk '{print $NF}')
        fi
        
        if [ "$bound_file" = "$img_file" ]; then
            return 0  # 已正确绑定
        fi
    fi
    
    return 1  # 未绑定或绑定错误
}

smart_bind_loop_device() {
    local img_file="$1"
    local offset="${2:-10000000}"
    
    if [ ! -f "$img_file" ]; then
        ERROR "img文件不存在: $img_file"
        return 1
    fi
    
    INFO "开始智能绑定loop设备: $img_file" >&2
    
    # 先清理无效的loop设备
    cleanup_invalid_loops
    
    # 尝试从状态文件获取loop设备号
    
    local loop_device=""
    if loop_device=$(get_loop_from_state_file "$img_file"); then
        INFO "从状态文件获取到loop设备: $loop_device" >&2
        
        if check_loop_binding "$img_file" "$loop_device"; then
            INFO "loop设备 $loop_device 已正确绑定到 $img_file" >&2
            echo "$loop_device"
            return 0
        else
            INFO "loop设备 $loop_device 未正确绑定，尝试重新绑定" >&2
            INFO "清理loop设备 $loop_device 的现有绑定" >&2
            umount -l "$loop_device" 2>/dev/null
            if losetup -d "$loop_device" 2>/dev/null; then
                if ! losetup -a | grep -q "^$loop_device:"; then
                    INFO "成功清理loop设备: $loop_device" >&2
                else
                    WARN "清理命令执行成功但设备仍存在: $loop_device" >&2
                fi
            else
                WARN "清理loop设备失败: $loop_device" >&2
            fi
            
            if losetup -o "$offset" "$loop_device" "$img_file"; then
                INFO "成功重新绑定loop设备: $loop_device -> $img_file" >&2
                update_loop_state_file "$img_file" "$loop_device"
                echo "$loop_device"
                return 0
            else
                INFO "重新绑定失败，将获取新的loop设备" >&2
            fi
        fi
    fi
    
    local existing_loop=""
    if losetup -a | grep -q "("; then
        existing_loop=$(losetup -a | grep "($img_file)" | head -n1 | cut -d: -f1)
    else
        existing_loop=$(losetup -a | grep " $img_file" | head -n1 | cut -d: -f1)
    fi
    if [ -n "$existing_loop" ]; then
        INFO "发现已有loop设备绑定到此img文件: $existing_loop" >&2
        update_loop_state_file "$img_file" "$existing_loop"
        echo "$existing_loop"
        return 0
    fi
    
    loop_device=$(losetup -f)
    if [ -z "$loop_device" ]; then
        ERROR "无法获取可用的loop设备"
        return 1
    fi
    
    if [ ! -e "$loop_device" ]; then
        local loop_num=$(echo "$loop_device" | grep -o '[0-9]\+$')
        if ! mknod "$loop_device" b 7 "$loop_num" 2>/dev/null; then
            ERROR "无法创建loop设备: $loop_device"
            return 1
        fi
    fi
    
    if losetup -o "$offset" "$loop_device" "$img_file"; then
        INFO "成功绑定loop设备: $loop_device -> $img_file" >&2
        update_loop_state_file "$img_file" "$loop_device"
        echo "$loop_device"
        return 0
    else
        ERROR "绑定loop设备失败: $loop_device -> $img_file" >&2
        return 1
    fi
}

check_proxy_health() {
    local proxy_url="$1"
    local test_url="${proxy_url}https://raw.githubusercontent.com/octocat/Hello-World/master/README"
    
    local content=$(curl -s --max-time 5 "$test_url" 2>/dev/null)

    if [ -z "$content" ]; then
        return 1
    fi
    
    if echo "$content" | grep -qi "Hello World"; then
        return 0
    fi
    
    if echo "$content" | grep -qi '<!DOCTYPE html\|<html'; then
        return 1
    fi
    
    return 1
}

setup_gh_proxy() {
    if [ -n "${gh_proxy}" ]; then
        INFO "使用用户手动设置的GitHub代理: ${gh_proxy}"
        return 0
    fi
    
    local free_proxies=(
        "https://ghfast.top/"
        "https://github.tbedu.top/"
        "https://tvv.tw/"
    )
    
    local user_proxy="https://gh.gbox.us.kg/"
    
    local country=""
    local ipv6_address=""
    
    INFO "正在检测网络环境..."
    country=$(curl -s --max-time 5 ipinfo.io/country 2>/dev/null || echo "")
    
    ipv6_address=$(curl -s --max-time 3 -6 ipv6.ip.sb 2>/dev/null || echo "")
    
    local proxy_list=()
    
    if [ "$country" = "CN" ]; then
        INFO "检测到国内IP，自动配置代理"
        for proxy in "${free_proxies[@]}"; do
            proxy_list+=("$proxy")
        done
        if [ -n "$user_proxy" ]; then
            proxy_list+=("$user_proxy")
        fi
        proxy_list+=("https://")
    elif [ -n "$ipv6_address" ]; then
        INFO "检测到IPv6网络，自动配置代理"
        for proxy in "${free_proxies[@]}"; do
            proxy_list+=("$proxy")
        done
        if [ -n "$user_proxy" ]; then
            proxy_list+=("$user_proxy")
        fi
        proxy_list+=("https://")
    else
        INFO "其他地区网络，不使用代理"
        proxy_list+=("https://")
    fi
    
    INFO "正在测试代理可用性..."
    local selected_proxy=""
    local proxy_available=false
    
    for proxy in "${proxy_list[@]}"; do
        if [ "$proxy" = "https://" ]; then
            selected_proxy="$proxy"
            INFO "直接访问GitHub，不使用代理"
            break
        else
            INFO "测试代理: ${proxy}"
            if check_proxy_health "$proxy"; then
                selected_proxy="$proxy"
                proxy_available=true
                INFO "代理可用: ${proxy}"
                break
            else
                WARN "代理不可用: ${proxy}，尝试下一个"
            fi
        fi
    done
    
    if [ -z "$selected_proxy" ]; then
        gh_proxy="https://"
        WARN "所有代理均不可用，使用直接访问GitHub（可能无法访问）"
    else
        gh_proxy="$selected_proxy"
        if [ "$proxy_available" = true ]; then
            INFO "已选择代理: ${gh_proxy}"
        fi
    fi
}

dd_xitong() {
    check_root
    
    setup_gh_proxy
    
    dd_xitong_MollyLau() {
        wget --no-check-certificate -qO InstallNET.sh "${gh_proxy}raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" && chmod a+x InstallNET.sh
    }
    
    dd_xitong_bin456789() {
        curl -O ${gh_proxy}raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && chmod a+x reinstall.sh
    }
    
    dd_xitong_1() {
        echo -e "重装后初始用户名: ${Yellow}root${NC}  初始密码: ${Yellow}LeitboGi0ro${NC}  初始端口: ${Yellow}22${NC}"
        echo -e "按任意键继续..."
        read -n 1 -s -r -p ""
        install_command wget
        dd_xitong_MollyLau
    }
    
    dd_xitong_2() {
        echo -e "重装后初始用户名: ${Yellow}Administrator${NC}  初始密码: ${Yellow}Teddysun.com${NC}  初始端口: ${Yellow}3389${NC}"
        echo -e "按任意键继续..."
        read -n 1 -s -r -p ""
        install_command wget
        dd_xitong_MollyLau
    }
    
    dd_xitong_3() {
        echo -e "重装后初始用户名: ${Yellow}root${NC}  初始密码: ${Yellow}123@@@${NC}  初始端口: ${Yellow}22${NC}"
        echo -e "按任意键继续..."
        read -n 1 -s -r -p ""
        dd_xitong_bin456789
    }
    
    dd_xitong_4() {
        echo -e "重装后初始用户名: ${Yellow}Administrator${NC}  初始密码: ${Yellow}123@@@${NC}  初始端口: ${Yellow}3389${NC}"
        echo -e "按任意键继续..."
        read -n 1 -s -r -p ""
        dd_xitong_bin456789
    }
    
    while true; do
        clear
        echo "重装系统"
        echo "--------------------------------"
        echo -e "${Red}注意: ${NC}重装有风险失联，不放心者慎用。重装预计花费15分钟，请提前备份数据。"
        echo -e "${Yellow}感谢leitbogioro大佬和bin456789大佬的脚本支持！${NC}"
        echo "------------------------"
        echo "1. Debian 13                  2. Debian 12"
        echo "3. Debian 11                  4. Debian 10"
        echo "------------------------"
        echo "11. Ubuntu 24.04              12. Ubuntu 22.04"
        echo "13. Ubuntu 20.04              14. Ubuntu 18.04"
        echo "------------------------"
        echo "21. Rocky Linux 10            22. Rocky Linux 9"
        echo "23. Alma Linux 10             24. Alma Linux 9"
        echo "25. oracle Linux 10           26. oracle Linux 9"
        echo "27. Fedora Linux 42           28. Fedora Linux 41"
        echo "29. CentOS 10                 30. CentOS 9"
        echo "------------------------"
        echo "31. Alpine Linux              32. Arch Linux"
        echo "33. Kali Linux                34. openEuler"
        echo "35. openSUSE Tumbleweed       36. fnos飞牛公测版"
        echo "------------------------"
        echo "41. Windows 11                42. Windows 10"
        echo "43. Windows 7                 44. Windows Server 2025"
        echo "45. Windows Server 2022       46. Windows Server 2019"
        echo "47. Windows 11 ARM"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -e -p "请选择要重装的系统: " sys_choice
        case "$sys_choice" in
            1)
                dd_xitong_3
                bash reinstall.sh debian 13
                reboot
                exit
                ;;
            2)
                dd_xitong_1
                bash InstallNET.sh -debian 12
                reboot
                exit
                ;;
            3)
                dd_xitong_1
                bash InstallNET.sh -debian 11
                reboot
                exit
                ;;
            4)
                dd_xitong_1
                bash InstallNET.sh -debian 10
                reboot
                exit
                ;;
            11)
                dd_xitong_1
                bash InstallNET.sh -ubuntu 24.04
                reboot
                exit
                ;;
            12)
                dd_xitong_1
                bash InstallNET.sh -ubuntu 22.04
                reboot
                exit
                ;;
            13)
                dd_xitong_1
                bash InstallNET.sh -ubuntu 20.04
                reboot
                exit
                ;;
            14)
                dd_xitong_1
                bash InstallNET.sh -ubuntu 18.04
                reboot
                exit
                ;;
            21)
                dd_xitong_3
                bash reinstall.sh rocky
                reboot
                exit
                ;;
            22)
                dd_xitong_3
                bash reinstall.sh rocky 9
                reboot
                exit
                ;;
            23)
                dd_xitong_3
                bash reinstall.sh almalinux
                reboot
                exit
                ;;
            24)
                dd_xitong_3
                bash reinstall.sh almalinux 9
                reboot
                exit
                ;;
            25)
                dd_xitong_3
                bash reinstall.sh oracle
                reboot
                exit
                ;;
            26)
                dd_xitong_3
                bash reinstall.sh oracle 9
                reboot
                exit
                ;;
            27)
                dd_xitong_3
                bash reinstall.sh fedora
                reboot
                exit
                ;;
            28)
                dd_xitong_3
                bash reinstall.sh fedora 41
                reboot
                exit
                ;;
            29)
                dd_xitong_3
                bash reinstall.sh centos 10
                reboot
                exit
                ;;
            30)
                dd_xitong_3
                bash reinstall.sh centos 9
                reboot
                exit
                ;;
            31)
                dd_xitong_1
                bash InstallNET.sh -alpine
                reboot
                exit
                ;;
            32)
                dd_xitong_3
                bash reinstall.sh arch
                reboot
                exit
                ;;
            33)
                dd_xitong_3
                bash reinstall.sh kali
                reboot
                exit
                ;;
            34)
                dd_xitong_3
                bash reinstall.sh openeuler
                reboot
                exit
                ;;
            35)
                dd_xitong_3
                bash reinstall.sh opensuse
                reboot
                exit
                ;;
            36)
                dd_xitong_3
                bash reinstall.sh fnos
                reboot
                exit
                ;;
            41)
                dd_xitong_2
                bash InstallNET.sh -windows 11 -lang "cn"
                reboot
                exit
                ;;
            42)
                dd_xitong_2
                bash InstallNET.sh -windows 10 -lang "cn"
                reboot
                exit
                ;;
            43)
                dd_xitong_4
                bash reinstall.sh windows --iso="https://drive.massgrave.dev/cn_windows_7_professional_with_sp1_x64_dvd_u_677031.iso" --image-name='Windows 7 PROFESSIONAL'
                reboot
                exit
                ;;
            44)
                dd_xitong_2
                bash InstallNET.sh -windows 2025 -lang "cn"
                reboot
                exit
                ;;
            45)
                dd_xitong_2
                bash InstallNET.sh -windows 2022 -lang "cn"
                reboot
                exit
                ;;
            46)
                dd_xitong_2
                bash InstallNET.sh -windows 2019 -lang "cn"
                reboot
                exit
                ;;
            47)
                dd_xitong_4
                bash reinstall.sh dd --img https://r2.hotdog.eu.org/win11-arm-with-pagefile-15g.xz
                reboot
                exit
                ;;
            *)
                break
                ;;
        esac
    done
}

# 交互式容器配置修改功能
modify_container_interactive() {
    clear
    echo -e "——————————————————————————————————————— \033[1;33m容器配置修改\033[0m ———————————————————————————————————————"
    echo -e "\n"
    INFO "此功能用于对已存在的Docker容器添加/修改配置参数"
    WARN "注意：修改配置会重建容器，请确保重要数据已备份！"
    echo -e "\n"
    
    # 选择容器
    INFO "获取容器列表..."
    local containers=($(docker ps -a --format '{{.Names}}'))
    
    if [ ${#containers[@]} -eq 0 ]; then
        ERROR "没有找到任何容器！"
        read -n 1 -rp "按任意键返回"
        return 1
    fi
    
    echo -e "\033[1;33m可用容器列表：\033[0m"
    for i in "${!containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "${containers[$i]}")
        echo -e "[ $((i + 1)) ] ${containers[$i]} [$status]"
    done
    echo -e "[ 0 ] 退出"
    echo -e "\n"
    
    read -erp "请选择要修改的容器序号：" container_select
    
    if [ "$container_select" -eq 0 ]; then
        return 0
    fi
    
    if [ "$container_select" -lt 1 ] || [ "$container_select" -gt ${#containers[@]} ]; then
        ERROR "无效的序号！"
        read -n 1 -rp "按任意键返回"
        return 1
    fi
    
    local selected_container="${containers[$((container_select - 1))]}"
    INFO "已选择容器：${selected_container}"
    
    # 使用 runlike 提取配置
    INFO "正在提取容器配置..."
    local runlike_file="/tmp/container_config_${selected_container}_$$.sh"
    
    # 拉取 runlike 镜像
    local runlike_image="ailg/runlike:latest"
    if ! docker inspect "$runlike_image" > /dev/null 2>&1; then
        runlike_image="ddsderek/runlike:latest"
        if ! docker inspect "$runlike_image" > /dev/null 2>&1; then
            INFO "拉取 runlike 镜像..."
            docker_pull "$runlike_image"
        fi
    fi
    
    if ! docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /tmp:/tmp "$runlike_image" -p "${selected_container}" > "${runlike_file}"; then
        ERROR "提取容器配置失败！"
        rm -f "${runlike_file}"
        read -n 1 -rp "按任意键返回"
        return 1
    fi
    
    INFO "配置已提取到：${runlike_file}"
    
    # 进入配置修改菜单
    modify_config_menu "$selected_container" "$runlike_file"
    
    rm -f "${runlike_file}"
}

# 配置修改菜单
modify_config_menu() {
    local container_name="$1"
    local config_file="$2"
    
    while true; do
        clear
        echo -e "——————————————————————————————————————— \033[1;33m配置修改菜单\033[0m ———————————————————————————————————————"
        echo -e "\n"
        INFO "容器名称：${container_name}"
        echo -e "\n"
        echo -e "\033[1;33m请选择要修改的配置：\033[0m"
        echo -e "[ 1 ] 添加/修改路径挂载"
        echo -e "[ 2 ] 添加/修改环境变量"
        echo -e "[ 3 ] 修改网络模式/端口"
        echo -e "[ 4 ] 添加其他额外参数"
        echo -e "[ 0 ] 保存并重建容器"
        echo -e "[ B ] 取消修改"
        echo -e "\n"
        
        read -erp "请选择：" choice
        
        case "$choice" in
            1)
                modify_mount "$config_file"
                ;;
            2)
                modify_env "$config_file"
                ;;
            3)
                modify_network "$config_file"
                ;;
            4)
                modify_extra_params "$config_file"
                ;;
            0)
                rebuild_container "$container_name" "$config_file"
                return 0
                ;;
            [Bb])
                INFO "已取消修改"
                read -n 1 -rp "按任意键返回"
                return 0
                ;;
            *)
                ERROR "无效的选择！"
                read -n 1 -rp "按任意键继续"
                ;;
        esac
    done
}

# 1、添加/修改路径挂载
modify_mount() {
    local config_file="$1"
    
    while true; do
        clear
        echo -e "——————————————————————————————————————— \033[1;33m添加/修改挂载\033[0m ———————————————————————————————————————"
        echo -e "\n"
        echo -e "当前挂载列表："
        grep -oE "(--volume|-v)\s+[^[:space:]]+:[^[:space:]]+" "$config_file" | sed 's/^\s*//'
        echo -e "\n"
        echo -e "输入格式：宿主机绝对路径:容器绝对路径"
        echo -e "示例：/home/data:/mnt/data"
        echo -e "输入 'b' 返回上级菜单"
        echo -e "\n"
        
        read -erp "请输入挂载配置：" mount_input
        
        if [[ $mount_input == [Bb] ]]; then
            break
        fi
        
        # 验证输入格式
        if [[ ! $mount_input =~ ^/[^:]+:/[^:]+$ ]]; then
            ERROR "格式错误！请使用：宿主机绝对路径:容器绝对路径"
            read -n 1 -rp "按任意键继续"
            continue
        fi
        
        local host_path=$(echo "$mount_input" | cut -d':' -f1)
        local container_path=$(echo "$mount_input" | cut -d':' -f2)
        
        # 检查容器路径是否已存在（基于文件内容）
        if grep -qE "(--volume|-v)[[:space:]]+[^[:space:]]+:${container_path}([[:space:]]|\\\|$)" "$config_file"; then
            WARN "容器路径 ${container_path} 已存在挂载，这将修改原有挂载"
            read -erp "是否继续？(y/n)：" confirm
            if [[ ! $confirm == [Yy] ]]; then
                continue
            fi
            # 删除旧的挂载 - 使用 | 作为分隔符以避免路径中/字符的问题
            sed -i -E "s#(--volume|-v)[[:space:]]+[^[:space:]]+:${container_path}([[:space:]]|\\\|$)# #g" "$config_file"
            # 清理多余空格
            sed -i 's/  */ /g' "$config_file"
        fi
        
        # 检查主机路径是否存在
        if [ ! -d "$host_path" ]; then
            WARN "主机目录 ${host_path} 不存在"
            read -erp "是否创建该目录？(y/n)：" create_dir
            if [[ $create_dir == [Yy] ]]; then
                mkdir -p "$host_path"
                INFO "目录已创建：${host_path}"
            else
                WARN "未创建目录，请确保容器运行前目录存在"
            fi
        fi
        
        # 在 --name 之后添加挂载
        sed -i "s|--name=${container_name} |--name=${container_name} --volume ${host_path}:${container_path} |" "$config_file"
        
        INFO "已添加挂载：${host_path} -> ${container_path}"
        read -erp "是否继续添加挂载？(y/n)：" continue_add
        if [[ ! $continue_add == [Yy] ]]; then
            break
        fi
    done
}

# 2、添加/修改环境变量
modify_env() {
    local config_file="$1"
    
    while true; do
        clear
        echo -e "——————————————————————————————————————— \033[1;33m添加/修改环境变量\033[0m ———————————————————————————————————————"
        echo -e "\n"
        echo -e "当前环境变量列表："
        grep -oE "(--env|-e)\s+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+" "$config_file" | sed 's/^\s*//'
        echo -e "\n"
        echo -e "输入格式：环境变量名=环境变量值"
        echo -e "示例：TZ=Asia/Shanghai"
        echo -e "输入 'b' 返回上级菜单"
        echo -e "\n"
        
        read -erp "请输入环境变量：" env_input
        
        if [[ $env_input == [Bb] ]]; then
            break
        fi
        
        # 验证输入格式
        if [[ ! $env_input =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            ERROR "格式错误！请使用：环境变量名=环境变量值"
            read -n 1 -rp "按任意键继续"
            continue
        fi
        
        local env_name=$(echo "$env_input" | cut -d'=' -f1)
        local env_value=$(echo "$env_input" | cut -d'=' -f2-)
        
        # 检查环境变量是否已存在（基于文件内容）
        if grep -qE "(--env|-e)\s+${env_name}=" "$config_file"; then
            local current_value=$(grep -oE "(--env|-e)[= ]+${env_name}=[^[:space:]]+" "$config_file" | sed "s/^.*${env_name}=//" | sed 's/\\$//')
            WARN "环境变量 ${env_name} 已存在"
            INFO "当前值：${current_value}"
            INFO "新值：${env_input}"
            read -erp "是否覆盖？(y/n)：" confirm
            if [[ ! $confirm == [Yy] ]]; then
                continue
            fi
            # 删除旧的环境变量 - 使用 | 作为分隔符以避免值中/字符的问题
            sed -i -E "s#(--env|-e)[= ]+${env_name}=[^[:space:]]*([[:space:]]|$)# #g" "$config_file"
            # 清理多余空格
            sed -i 's/  */ /g' "$config_file"
        fi
        
        # 在 --name 之后添加环境变量
        sed -i "s|--name=${container_name} |--name=${container_name} --env ${env_input} |" "$config_file"
        
        INFO "已添加环境变量：${env_input}"
        read -erp "是否继续添加环境变量？(y/n)：" continue_add
        if [[ ! $continue_add == [Yy] ]]; then
            break
        fi
    done
}

# 3、修改网络模式/端口
modify_network() {
    local config_file="$1"
    
    clear
    echo -e "——————————————————————————————————————— \033[1;33m修改网络模式/端口\033[0m ———————————————————————————————————————"
    echo -e "\n"
    
    # 检查当前网络模式（基于文件内容）
    local current_network="bridge"
    if grep -qE "\s*--network=host\s*" "$config_file" || grep -qE "\s*--net=host\s*" "$config_file"; then
        current_network="host"
    elif grep -qE "\s*--network=|\s*--net=" "$config_file"; then
        current_network=$(grep -oE "\s*--network=[^[:space:]]+|\s*--net=[^[:space:]]+" "$config_file" | head -n1 | cut -d'=' -f2 | sed 's/\\$//')
    fi
    
    INFO "当前网络模式：${current_network}"
    echo -e "\n"
    echo -e "请选择网络模式："
    echo -e "[ 1 ] host 模式"
    echo -e "[ 2 ] bridge 模式"
    echo -e "[ 3 ] 自定义网络"
    echo -e "[ 0 ] 不修改，返回"
    echo -e "\n"
    
    read -erp "请选择：" network_choice
    
    case "$network_choice" in
        1)
            # 删除旧的网络配置和端口映射
            sed -i 's|--network=[^[:space:]]*||g' "$config_file"
            sed -i 's|--net=[^[:space:]]*||g' "$config_file"
            sed -i -E 's#(--publish|-p)[= ]+[^[:space:]]+([[:space:]]|$)# #g' "$config_file"
            # 清理多余空格
            sed -i 's/  */ /g' "$config_file"
            # 添加 host 网络
            sed -i "s|--name=${container_name} |--name=${container_name} --network=host |" "$config_file"
            INFO "已设置为 host 网络模式"
            read -n 1 -rp "按任意键返回"
            ;;
        2)
            # 删除旧的网络配置
            sed -i 's|--network=host||g' "$config_file"
            sed -i 's|--net=host||g' "$config_file"
            # 清理多余空格
            sed -i 's/  */ /g' "$config_file"
            
            # 桥接模式下可以添加端口映射
            while true; do
                echo -e "\n"
                INFO "当前端口映射："
                grep -oE "(--publish|-p)\s+[0-9]+:[0-9]+" "$config_file" | sed 's/^\s*//'
                echo -e "\n"
                echo -e "输入格式：主机端口:容器端口"
                echo -e "示例：8080:80"
                echo -e "输入 'b' 返回网络模式选择"
                echo -e "\n"
                
                read -erp "请输入端口映射：" port_input
                
                if [[ $port_input == [Bb] ]]; then
                    break
                fi
                
                # 验证输入格式
                if [[ ! $port_input =~ ^[0-9]+:[0-9]+ ]]; then
                    ERROR "格式错误！请使用：主机端口:容器端口"
                    read -n 1 -rp "按任意键继续"
                    continue
                fi
                
                local host_port=$(echo "$port_input" | cut -d':' -f1)
                local container_port=$(echo "$port_input" | cut -d':' -f2)
                
                # 检查主机端口是否被占用
                if netstat -tuln 2>/dev/null | grep -q ":${host_port}\s"; then
                    WARN "主机端口 ${host_port} 可能已被占用"
                    read -erp "是否继续？(y/n)：" confirm
                    if [[ ! $confirm == [Yy] ]]; then
                        continue
                    fi
                fi
                
                # 检查容器端口是否已存在映射（基于文件内容）
                local container_port_base=$(echo "$container_port" | cut -d'/' -f1)
                if grep -qE "(--publish|-p)[= ]+[0-9]+:${container_port_base}" "$config_file"; then
                    WARN "容器端口 ${container_port_base} 已存在映射"
                    read -erp "是否覆盖？(y/n)：" confirm
                    if [[ $confirm == [Yy] ]]; then
                        # 删除旧的端口映射 - 使用 | 作为分隔符以避免端口/协议格式的问题
                        sed -i -E "s#(--publish|-p)[= ]+[0-9]+:${container_port_base}[^[:space:]]*([[:space:]]|$)# #g" "$config_file"
                        # 清理多余空格
                        sed -i 's/  */ /g' "$config_file"
                    else
                        continue
                    fi
                fi
                
                # 添加端口映射
                sed -i "s|--name=${container_name} |--name=${container_name} --publish ${port_input} |" "$config_file"
                INFO "已添加端口映射：${port_input}"
                
                read -erp "是否继续添加端口？(y/n)：" continue_port
                if [[ ! $continue_port == [Yy] ]]; then
                    break
                fi
            done
        
            INFO "已设置为 bridge 网络模式"
            read -n 1 -rp "按任意键返回"
            ;;
        3)
            # 自定义网络模式
            echo -e "\n"
            INFO "当前网络配置："
            if grep -qE "\s*(--network=|--net=)" "$config_file"; then
                grep -oE "\s*(--network=|--net=)[^[:space:]]+" "$config_file" | sed 's/^\s*//'
            else
                echo "无网络配置，当前为默认bridge模式"
            fi
            echo -e "\n"
            read -erp "请输入自定义网络名称（如：my-network）：" custom_network
            
            if [ -z "$custom_network" ]; then
                ERROR "网络名称不能为空！"
                read -n 1 -rp "按任意键返回"
                return 0
            fi
            
            # 删除旧的网络配置
            sed -i 's|--network=[^[:space:]]*||g' "$config_file"
            sed -i 's|--net=[^[:space:]]*||g' "$config_file"
            # 清理多余空格
            sed -i 's/  */ /g' "$config_file"
            
            # 添加自定义网络
            sed -i "s|--name=${container_name} |--name=${container_name} --network=${custom_network} |" "$config_file"
            INFO "已设置为自定义网络：${custom_network}"
            read -n 1 -rp "按任意键返回"
            ;;
        0)
            return 0
            ;;
        *)
            ERROR "无效的选择！"
            read -n 1 -rp "按任意键返回"
            ;;
    esac
}

# 4、添加其他额外参数
modify_extra_params() {
    local config_file="$1"
    
    while true; do
        clear
        echo -e "——————————————————————————————————————— \033[1;33m添加额外参数\033[0m ———————————————————————————————————————"
        echo -e "\n"
        echo -e "请输入完整的Docker参数"
        echo -e "常用设备参数："
        echo -e "  示例：--device=/dev/dri (GPU设备)"
        echo -e "  示例：--gpus=all (所有GPU)"
        echo -e "  示例：--device=/dev/snd (音频设备)"
        echo -e "\n"
        echo -e "输入 'b' 返回上级菜单"
        echo -e "\n"
        
        read -erp "请输入参数：" extra_param
        
        if [[ $extra_param == [Bb] ]]; then
            break
        fi
        
        if [ -z "$extra_param" ]; then
            ERROR "参数不能为空！"
            read -n 1 -rp "按任意键继续"
            continue
        fi
        
        # 检查参数是否已存在（基于文件内容）
        local param_name=$(echo "$extra_param" | cut -d'=' -f1)
        if grep -qF "$param_name" "$config_file"; then
            WARN "参数 ${param_name} 可能已存在"
            read -erp "是否继续添加？(y/n)：" confirm
            if [[ ! $confirm == [Yy] ]]; then
                continue
            fi
        fi
        
        # 检查网络相关参数冲突
        if [[ "$extra_param" == --network=host || "$extra_param" == --net=host ]]; then
            if grep -qE "(--publish|-p)[= ]+" "$config_file"; then
                WARN "当前配置包含端口映射(-p)，但添加--network=host后端口映射将无效"
                read -erp "是否继续？(y/n)：" confirm
                if [[ ! $confirm == [Yy] ]]; then
                    continue
                fi
            fi
        elif [[ "$extra_param" == -p* || "$extra_param" == --publish* ]]; then
            if grep -qE "\s*(--network=host|--net=host)\s*" "$config_file"; then
                WARN "当前配置为host网络模式，端口映射可能无法正常工作"
                read -erp "是否继续？(y/n)：" confirm
                if [[ ! $confirm == [Yy] ]]; then
                    continue
                fi
            fi
        fi
        
        # 添加参数
        sed -i "s|--name=${container_name} |--name=${container_name} ${extra_param} |" "$config_file"
        
        INFO "已添加参数：${extra_param}"
        read -erp "是否继续添加参数？(y/n)：" continue_add
        if [[ ! $continue_add == [Yy] ]]; then
            break
        fi
    done
}

# 0、确认并重建容器
rebuild_container() {
    local container_name="$1"
    local config_file="$2"
    
    clear
    echo -e "——————————————————————————————————————— \033[1;33m确认重建容器\033[0m ———————————————————————————————————————"
    echo -e "\n"
    INFO "容器名称：${container_name}"
    echo -e "\n"
    echo -e "\033[1;33m修改后的配置预览：\033[0m"
    echo -e "\033[0;36m"
    cat "$config_file"
    echo -e "\033[0m"
    echo -e "\n"
    
    # 显示变更摘要
    echo -e "\033[1;33m配置变更摘要：\033[0m"
    local volume_count=$(grep -oE "(--volume|-v)[= ]+" "$config_file" | wc -l)
    local env_count=$(grep -oE "(--env|-e)[= ]+" "$config_file" | wc -l)
    local port_count=$(grep -oE "(--publish|-p)[= ]+" "$config_file" | wc -l)
    local network=$(grep -oE "(--network|--net)=[^[:space:]]+" "$config_file" | head -n1 | cut -d'=' -f2)
    
    echo -e "  挂载卷数量: $volume_count"
    echo -e "  环境变量数量: $env_count"
    echo -e "  端口映射数量: $port_count"
    echo -e "  网络模式: ${network:-default}"
    echo -e "\n"
    
    WARN "即将重建容器，此操作将："
    echo -e "  1. 停止并删除现有容器"
    echo -e "  2. 使用新配置创建容器"
    echo -e "  3. 旧容器将备份为 ${container_name}_old"
    echo -e "\n"
    
    read -erp "确认重建容器？(yes/no)：" final_confirm
    
    if [[ ! $final_confirm == "yes" ]]; then
        INFO "已取消重建"
        read -n 1 -rp "按任意键返回"
        return 1
    fi
    
    # 修改配置文件中的容器名
    sed -i "s|--name=${container_name} |--name=${container_name}_new |" "$config_file"
    
    # 获取容器状态
    local was_running=false
    if [ "$(docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null)" == "true" ]; then
        was_running=true
    fi
    
    INFO "停止容器 ${container_name}..."
    docker stop "${container_name}" > /dev/null 2>&1
    
    INFO "重命名旧容器为 ${container_name}_old..."
    docker rename "${container_name}" "${container_name}_old" > /dev/null 2>&1
    
    INFO "创建新容器..."
    if bash "${config_file}"; then
        docker rename "${container_name}_new" "${container_name}" > /dev/null 2>&1
        
        if [ "$was_running" == "true" ]; then
            INFO "启动容器 ${container_name}..."
            docker start "${container_name}" > /dev/null 2>&1
        fi
        
        INFO "容器重建成功！"
        INFO "旧容器已保留为：${container_name}_old"
        echo -e "\n"
        read -erp "是否删除旧容器？(y/n)：" delete_old
        if [[ $delete_old == [Yy] ]]; then
            docker rm -f "${container_name}_old" > /dev/null 2>&1
            INFO "旧容器已删除"
        fi
    else
        ERROR "创建新容器失败！正在回滚..."
        docker rm -f "${container_name}_new" > /dev/null 2>&1
        docker rename "${container_name}_old" "${container_name}" > /dev/null 2>&1
        
        if [ "$was_running" == "true" ]; then
            docker start "${container_name}" > /dev/null 2>&1
        fi
        
        ERROR "回滚完成，容器已恢复原状态"
    fi
    
    read -n 1 -rp "按任意键返回主菜单"
}

export -f INFO ERROR WARN \
    check_path check_port check_space check_root check_env check_loop_support check_qnap \
    setup_status command_exists \
    docker_pull update_ailg restore_containers restore_containers_simple \
    xy_media_reunzip \
    emby_close_6908_port get_docker0_ip wait_emby_start wait_gbox_start \
    cleanup_invalid_loops get_loop_from_state_file update_loop_state_file check_loop_binding smart_bind_loop_device \
    check_proxy_health setup_gh_proxy dd_xitong \
    modify_container_interactive modify_config_menu modify_mount modify_env modify_network modify_extra_params rebuild_container
