#!/bin/bash
keys="awk jq grep cp mv kill 7z dirname"
values="gawk jq grep coreutils coreutils procps p7zip coreutils"

get_value() {
    key=$1
    keys_array=$(echo $keys)
    values_array=$(echo $values)
    i=1
    for k in $keys_array; do
        if [ "$k" = "$key" ]; then
            set -- $values_array
            eval echo \$$i
            return
        fi
        i=$((i + 1))
    done
    echo "Key not found"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_command() {
    cmd=$1
    # local pkg=${PACKAGE_MAP[$cmd]:-$cmd}
    pkg=$(get_value $cmd)

    if command_exists apt-get; then
        apt-get update && apt-get install -y "$pkg"
    elif command_exists yum; then
        yum install -y "$pkg"
    elif command_exists dnf; then
        dnf install -y "$pkg"
    elif command_exists zypper; then
        zypper install -y "$pkg"
    elif command_exists pacman; then
        pacman -Sy --noconfirm "$pkg"
    elif command_exists brew; then
        brew install "$pkg"
    elif command_exists apk; then
        apk add --no-cache "$pkg"
    else
        echo "无法自动安装 $pkg，请手动安装。"
        return 1
    fi
}

docker_pid() {
    if [ -f /var/run/docker.pid ]; then
        kill -SIGHUP $(cat /var/run/docker.pid)
    elif [ -f /var/run/dockerd.pid ]; then
        kill -SIGHUP $(cat /var/run/dockerd.pid)
    else
        echo "Docker进程不存在，脚本中止执行。"
        if [ "$FILE_CREATED" == false ]; then
            cp $BACKUP_FILE $DOCKER_CONFIG_FILE
            echo -e "\033[1;33m原配置文件：${DOCKER_CONFIG_FILE} 已恢复，请检查是否正确！\033[0m"
        else
            rm -f $DOCKER_CONFIG_FILE
            echo -e "\033[1;31m已删除新建的配置文件：${DOCKER_CONFIG_FILE}\033[0m"
        fi
        return 1
    fi 
}

jq_exec() {
    jq --argjson urls "$REGISTRY_URLS_JSON" '
        if has("registry-mirrors") then
            .["registry-mirrors"] = $urls
        else
            . + {"registry-mirrors": $urls}
        end
    ' "$DOCKER_CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$DOCKER_CONFIG_FILE"
}

clear
if ! command_exists "docker"; then
    echo -e $'\033[1;33m你还没有安装docker，请先安装docker，安装后无法拖取镜像再运行脚本！\033[0m'
    echo -e "docker一键安装脚本参考："
    echo -e $'\033[1;32m\tcurl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh\033[0m'
    echo -e "或者："
    echo -e $'\033[1;32m\twget -qO- https://get.docker.com | sh\033[0m'
    exit 1
fi

REGISTRY_URLS=('https://hub.rat.dev' 'https://nas.dockerimages.us.kg' 'https://dockerhub.ggbox.us.kg')

DOCKER_CONFIG_FILE=''
BACKUP_FILE=''

REQUIRED_COMMANDS=('awk' 'jq' 'grep' 'cp' 'mv' 'kill')
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command_exists "$cmd"; then
        echo "缺少命令: $cmd，尝试安装..."
        if ! install_command "$cmd"; then
            echo "安装 $cmd 失败，请手动安装后再运行脚本。"
            exit 1
        fi
    fi
done

read -p $'\033[1;33m是否使用自定义镜像代理？（y/n）: \033[0m' use_custom_registry
if [[ "$use_custom_registry" == [Yy] ]]; then
    read -p "请输入自定义镜像代理（示例：https://docker.ggbox.us.kg，多个请用空格分开。直接回车将重置为空）: " -a custom_registry_urls
    if [ ${#custom_registry_urls[@]} -eq 0 ]; then
        echo "未输入任何自定义镜像代理，镜像代理将重置为空。"
        REGISTRY_URLS=()
    else
        REGISTRY_URLS=("${custom_registry_urls[@]}")
    fi
fi

echo -e "\033[1;33m正在执行修复，请稍候……\033[0m"

if [ ${#REGISTRY_URLS[@]} -eq 0 ]; then
    REGISTRY_URLS_JSON='[]'
else
    REGISTRY_URLS_JSON=$(printf '%s\n' "${REGISTRY_URLS[@]}" | jq -R . | jq -s .)
fi

if [ -f /etc/synoinfo.conf ]; then
    DOCKER_ROOT_DIR=$(docker info 2>/dev/null | grep 'Docker Root Dir' | awk -F': ' '{print $2}')
    DOCKER_CONFIG_FILE="${DOCKER_ROOT_DIR%/@docker}/@appconf/ContainerManager/dockerd.json"
elif command_exists busybox; then
    DOCKER_CONFIG_FILE=$(ps | grep dockerd | awk '{for(i=1;i<=NF;i++) if ($i ~ /^--config-file(=|$)/) {if ($i ~ /^--config-file=/) print substr($i, index($i, "=") + 1); else print $(i+1)}}')
else
    DOCKER_CONFIG_FILE=$(ps -ef | grep dockerd | awk '{for(i=1;i<=NF;i++) if ($i ~ /^--config-file(=|$)/) {if ($i ~ /^--config-file=/) print substr($i, index($i, "=") + 1); else print $(i+1)}}')
fi

DOCKER_CONFIG_FILE=${DOCKER_CONFIG_FILE:-/etc/docker/daemon.json}
echo "Docker 配置文件路径: $DOCKER_CONFIG_FILE"

if [ ! -f "$DOCKER_CONFIG_FILE" ]; then
    echo "配置文件 $DOCKER_CONFIG_FILE 不存在，创建新文件。"
    mkdir -p $(dirname $DOCKER_CONFIG_FILE) && echo "{}" > $DOCKER_CONFIG_FILE
    FILE_CREATED=true
else
    FILE_CREATED=false
fi

if [ "$FILE_CREATED" == false ]; then
    BACKUP_FILE="${DOCKER_CONFIG_FILE}.bak"
    cp -f $DOCKER_CONFIG_FILE $BACKUP_FILE
fi

jq_exec

if ! docker_pid; then
    exit 1
fi

if [ "$REGISTRY_URLS_JSON" == '[]' ]; then
    echo -e "\033[1;33m已清空镜像代理，不再检测docker连接性，直接退出！\033[0m"
    exit 0
fi

docker rmi hello-world:latest >/dev/null 2>&1
if docker pull hello-world; then
    echo -e "\033[1;32mNice！Docker下载测试成功，配置更新完成！\033[0m"
else
    echo -e "\033[1;31m哎哟！Docker测试下载失败，恢复原配置文件...\033[0m"
    if [ "$FILE_CREATED" == false ]; then
        cp -f $BACKUP_FILE $DOCKER_CONFIG_FILE
        echo -e "\033[1;33m原配置文件：${DOCKER_CONFIG_FILE} 已恢复，请检查是否正确！\033[0m"
        docker_pid
    else
        REGISTRY_URLS_JSON='[]'
        jq_exec
        docker_pid
        rm -f $DOCKER_CONFIG_FILE
        echo -e "\033[1;31m已删除新建的配置文件：${DOCKER_CONFIG_FILE}\033[0m"
    fi  
fi