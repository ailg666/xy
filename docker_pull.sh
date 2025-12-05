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

function docker_pull() {
    #[ -z "${config_dir}" ] && get_config_path
    start_time=$SECONDS
    local config_dir=${2:-"/etc/xiaoya"}
    mirrors=(
        "docker.io"
        "hub.rat.dev"
        "docker.1ms.run"
        "dk.nastool.de"
        "docker.aidenxin.xyz"
        "dockerhub.anzu.vip"
        "proxy.1panel.live"
        "freeno.xyz"
        "docker.adysec.com"
        "dockerhub.icu"
        "docker.fxxk.dedyn.io"
    )
    declare -A mirror_total_delays
    if [ ! -f "${config_dir}/docker_mirrors.txt" ]; then
        echo -e "\033[1;32m正在进行代理测速，为您选择最佳代理……\033[0m"
        for i in "${!mirrors[@]}"; do
            mirror="${mirrors[$i]}"
            echo -e "\033[1;34m正在测试 $mirror...\033[0m"
            
            # 测试连接延迟
            output=$(curl -s -o /dev/null -w '%{time_total}' --head --request GET --connect-timeout 10 "$mirror" 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo -e "\033[1;31m  - $mirror 连接测试失败\033[0m"
                continue
            fi
            echo -e "\033[1;32m  - $mirror 连接延迟: ${output}s\033[0m"
            
            # 测试镜像拉取
            echo -e "\033[1;34m  - 测试 $mirror 拉取镜像...\033[0m"
            if docker pull "${mirrors[$i]}/library/hello-world:latest" &> /dev/null; then
                echo -e "\033[1;32m  - $mirror 镜像拉取成功\033[0m"
                mirror_total_delays["$mirror"]=$output
                docker rmi "${mirror}/library/hello-world:latest" &> /dev/null
            else
                echo -e "\033[1;31m  - $mirror 镜像拉取失败\033[0m"
            fi
        done
        
        if [ ${#mirror_total_delays[@]} -eq 0 ]; then
            echo -e "\033[1;31m所有代理测试失败，已恢复为官方docker镜像源，检查网络或配置可用代理后重新运行脚本，请从主菜单手动退出！\033[0m"
        else
            sorted_mirrors=$(for k in "${!mirror_total_delays[@]}"; do echo $k ${mirror_total_delays["$k"]}; done | sort -n -k2)
            echo "$sorted_mirrors" | head -n 2 | awk '{print $1}' > "${config_dir}/docker_mirrors.txt"
            echo -e "\033[1;32m已为您选取两个最佳代理点并添加到了${config_dir}/docker_mirrors.txt文件中：\033[0m"
            cat ${config_dir}/docker_mirrors.txt
        fi
    fi
    end_time=$SECONDS
    execution_time=$((end_time - start_time))
    minutes=$((execution_time / 60))
    seconds=$((execution_time % 60))
    echo "测速执行时间：${minutes} 分 ${seconds} 秒"

    mirrors=()
    INFO "正在从${config_dir}/docker_mirrors.txt文件获取代理点配置……"
    while IFS= read -r line; do
        mirrors+=("$line")
    done < "${config_dir}/docker_mirrors.txt"

    local pull_success=false
    local last_mirror=""
    
    if command -v timeout > /dev/null 2>&1; then
        for mirror in "${mirrors[@]}"; do
            last_mirror="${mirror}"
            INFO "正在从${mirror}代理点为您下载镜像……"
            #local_sha=$(timeout 300 docker pull "${mirror}/${1}" 2>&1 | grep 'Digest: sha256' | awk -F':' '{print $3}')
            command -v mktemp >/dev/null 2>&1 && tempfile=$(mktemp) || tempfile="/tmp/ailg_temp.txt"
            timeout 300 docker pull "${mirror}/${1}" | tee "$tempfile"
            local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
            rm -f "$tempfile"

            if [ -n "${local_sha}" ]; then
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                pull_success=true
                [[ "${mirror}" == "docker.io" ]] && return 0
                break
            else
                WARN "${1} 镜像拉取失败，正在进行重试..."
            fi
        done
    else
        for mirror in "${mirrors[@]}"; do
            last_mirror="${mirror}"
            INFO "正在从${mirror}代理点为您下载镜像……"
            timeout=200
            > "/tmp/tmp_sha"  # 清空文件
            (docker pull "${mirror}/${1}" 2>&1 | grep 'Digest: sha256' | awk -F':' '{print $3}' > "/tmp/tmp_sha") &
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
            [ -f "/tmp/tmp_sha" ] && local_sha=$(cat "/tmp/tmp_sha") || local_sha=""
            [ -f "/tmp/tmp_sha" ] && rm -f "/tmp/tmp_sha"
            
            if [ -n "${local_sha}" ]; then
                INFO "${1} 镜像拉取成功！"
                #sed -i "/"${1}"/d" "${config_dir}/ailg_sha.txt"
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                pull_success=true
                [[ "${mirror}" == "docker.io" ]] && return 0
                break
            else
                WARN "${1} 镜像拉取失败，正在进行重试..."
            fi
        done
    fi

    if $pull_success || [ -n "$(docker images -q "${last_mirror}/${1}")" ]; then
        [ -n "$(docker images -q "${last_mirror}/${1}")" ] && docker tag "${last_mirror}/${1}" "${1}" && docker rmi "${last_mirror}/${1}"
        return 0
    else
        ERROR "已尝试所有镜像代理拉取失败，程序退出，请检查网络后再试！"
        exit 1       
    fi
}

if [ -n "$1" ];then
    docker_pull $1 $2
else
    while :; do
        read -erp "$(INFO "请输入您要拉取镜像的完整名字（示例：ailg/alist:latest）：")" pull_img
        [ -z "${pull_img}" ] && ERROR "镜像名称不能为空，请重新输入！" && continue
        read -erp "$(INFO "测速会创建一个docker_mirrors.txt文件，请输入该文件存放的目录：")" config_dir
        config_dir=${config_dir:-"/etc/xiaoya"}
        [ -d "${config_dir}" ] && break
        ERROR "您输入的文件存放目录不存在，请重新输入！" && continue
    done
    docker_pull "${pull_img}" "${config_dir}"
fi
