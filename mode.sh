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