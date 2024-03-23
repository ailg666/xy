#!/bin/bash
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

Blue="\033[1;34m"
Green="\033[1;32m"
Red="\033[1;31m"
Yellow='\033[1;33m'
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

clear
echo -e "\e[33m"
echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
echo -e "1、本脚本为小雅Alist的安装脚本，使用于玩客云系统安装，不保证其他系统通用；"
#echo -e "\n"
echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
#echo -e "\n"
echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行脚本，按CTRL+C立即退出；"
#echo -e "\n"
echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://xy.ggbond.org/xy/3q.jpg"
echo -e "——————————————————————————————————————————————————————————————————————————————————"
echo -e "\e[0m"

echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
echo -e "\n"
echo -e "\033[1;32m1、小雅ALIST重新安装（$Yellow用原有token等配置文件$Font进行重装安装）\033[0m"
echo -e "\n"
echo -e "\033[1;35m2、小雅ALIST全新安装（$Yellow清除原有token等配置文件$Font新装或重装）\033[0m"
echo -e "\n"
echo -e "——————————————————————————————————————————————————————————————————————————————————"
read -ep "请输入您的选择（1-2，或按q退出）；" f1_select

function xy_alist_setup(){
	read -ep "是否选择host模式安装？(按Y/y选择host模式安装，非host模式安装直接按回车！)" host_select
    if [[ $host_select == [Yy] ]]; then
        bash -c "$(cat /tmp/update_new.sh)" -s /etc/xiaoya host
    else
        bash -c "$(cat /tmp/update_new.sh)" -s /etc/xiaoya
    fi
    status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "\033[1;35m哇塞！安装完成了，快去看看吧！\033[0m"
    else
        echo -e "\033[1;31m哎呀！安装出错了，错误代码：$status。检查是否没删除其他安装的小雅ALIST！\033[0m"
    fi
    rm -f /tmp/update_new.sh
}

curl -o /tmp/update_new.sh https://xy.ggbond.org/xy/update_new.sh
grep -q "长度不对" /tmp/update_new.sh || { echo -e "文件获取失败，检查网络或重新运行脚本！"; rm -f /tmp/update_new.sh; exit 1; }
if [[ $f1_select == 1 ]]; then
	xy_alist_setup
elif [[ $f1_select == 2 ]]; then
	rm -rf /etc/xiaoya/*
	xy_alist_setup
elif [[ $f1_select == [Qq] ]]; then
	exit
else
	ERROR "输入错误，程序退出！"
	exit 1
fi




