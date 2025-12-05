#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2068
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

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

Green="\033[32m"
Red="\033[31m"
Yellow='\033[33m'
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

# 检查curl命令
if ! command -v curl >/dev/null 2>&1; then
    WARN "未找到curl命令,尝试使用wget..."
    if ! command -v wget >/dev/null 2>&1; then
        WARN "未找到wget命令,尝试安装curl..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y curl
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy curl --noconfirm
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl
        else
            ERROR "无法安装curl或wget,请手动安装后重试!"
            exit 1
        fi
        
        if ! command -v curl >/dev/null 2>&1; then
            ERROR "curl安装失败,请手动安装后重试!"
            exit 1
        fi
    fi
fi

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    ERROR "此脚本必须以root权限运行!"
    INFO "请使用 sudo -i 切换到root用户后重试"
    exit 1
fi

# 清理函数
cleanup() {
    local temp_files=(
        "/tmp/xy_ailg.sh"
        "/tmp/update_meta_jf.sh"
        "/tmp/share_resources.sh"
        "/tmp/sync_emby_config_ailg.sh"
        "/tmp/cronjob.tmp"
        "/tmp/cron.log"
        "/tmp/xy_utils.sh"
    )
    
    for file in "${temp_files[@]}"; do
        [ -f "$file" ] && rm -f "$file" > /dev/null 2>&1
    done
}

# 注册退出清理
trap cleanup EXIT INT TERM

# 定义基础URL和文件
BASE_URLS=(
    "https://ailg.ggbond.org"
    "https://gbox.ggbond.org"
    "https://xy.ggbond.org/xy"
)

SCRIPT_FILES=(
    "xy_ailg.sh"
    "xy_utils.sh"
    "xy_sync.sh"
)

# 下载脚本
utils_success=0
download_success=0
sync_success=0

download_file() {
    local file=$1
    local success=1
    
    for base_url in "${BASE_URLS[@]}"; do
        local url="${base_url}/${file}"
        if command -v curl >/dev/null 2>&1; then
            download_cmd="curl -sL --connect-timeout 20 $url -o /tmp/${file}"
        else
            download_cmd="wget -qO /tmp/${file} --timeout=20 $url"
        fi

        if eval "$download_cmd"; then
            if [ -s "/tmp/${file}" ]; then
                # 移除UTF-8 BOM
                sed -i '1s/^\xEF\xBB\xBF//' "/tmp/${file}"
                case "$file" in
                    "xy_ailg.sh")
                        if grep -q "fuck_docker" "/tmp/${file}"; then
                            success=0
                            break
                        fi
                        ;;
                    "xy_utils.sh")
                        if grep -q "setup_colors" "/tmp/${file}"; then
                            success=0
                            break
                        fi
                        ;;
                    "xy_sync.sh")
                        if grep -q "xy_emby_sync" "/tmp/${file}"; then
                            success=0
                            break
                        fi
                        ;;
                esac
            fi
            [ $success -eq 1 ] && rm -f "/tmp/${file}"
        else
            WARN "从 ${url} 下载失败,尝试其他源..."
        fi
    done
    
    return $success
}

# 下载所有脚本
INFO "正在初始化，请稍后..."
for file in "${SCRIPT_FILES[@]}"; do
    if download_file "$file"; then
        case "$file" in
            "xy_ailg.sh") download_success=1 ;;
            "xy_utils.sh") utils_success=1 ;;
            "xy_sync.sh") sync_success=1 ;;
        esac
    fi
done

if [ $download_success -eq 1 ] && [ $utils_success -eq 1 ] && [ $sync_success -eq 1 ]; then
    # 添加执行权限
    
    chmod +x /tmp/xy_ailg.sh
    chmod +x /tmp/xy_utils.sh
    chmod +x /tmp/xy_sync.sh
    
    # 执行主脚本
    INFO "初始化完成..."
    bash /tmp/xy_ailg.sh "$@"
    
else
    ERROR "脚本下载失败,请检查网络连接后重试!"
    [ $download_success -eq 0 ] && ERROR "主脚本下载失败"
    [ $utils_success -eq 0 ] && ERROR "工具脚本下载失败"
    [ $sync_success -eq 0 ] && ERROR "同步脚本下载失败"
    exit 1
fi 