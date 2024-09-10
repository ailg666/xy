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

#!/bin/bash

# 检查并设置时区为中国上海
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
