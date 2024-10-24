#!/bin/bash
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
clear
echo -e "\e[33m"
echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
echo -e "1、本脚本为CloudDrive2的docker版安装脚本，用于Linux环境，不保证所有系统可用；"
echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行，按CTRL+C立即退出；"
echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://gbox.ggbond.org/3q.jpg\033[0m"
echo -e "—————————————————————————————————————\033[1;33mA   I  老   G\033[0m————————————————————————————————"

INFO "卸载命令："
echo -e "${Yellow}bash -c \"\$(curl -sSLf https://ailg.ggbond.org/cd2.sh)\" -s uninstall${NC}" 

for dir in /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin ~/bin /opt/homebrew/bin; do
  if [[ ":$PATH:" != *":$dir:"* ]]; then
    PATH="${PATH}:$dir"
  fi
done
export PATH




function root_need() {
    if [[ $EUID -ne 0 ]]; then
        ERROR '此脚本必须以 root 身份运行！'
        exit 1
    fi
}

function ___install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
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

fuse3_install() {
    if command -v opkg >/dev/null 2>&1 && [ -e "/sbin/procd" ]; then
        echo -e "\r\n${Green}更新软件源...${NC}"
        opkg update > /dev/null
        op_packages=("fuse3-utils" "libfuse3-3")
        INSTALL_SUCCESS="true"
        for op_pkg in "${op_packages[@]}"; do
            if ! opkg list-installed | grep -q "$op_pkg"; then
                opkg install "$op_pkg" > /dev/null
                if ! [ $? -eq 0 ]; then
                    INSTALL_SUCCESS="false"
                fi
            fi
        done
        if [ "$INSTALL_SUCCESS" = "false" ]; then
            echo -e "${Red}安装 FUSE3 软件包失败，可能无法挂载${NC}"
        fi
    elif [[ "$os_type" == "Darwin" ]]; then
        if [ ! -f "/Library/Frameworks/macFUSE.framework/Versions/A/macFUSE" ]; then
        fuse_version=$(curl -s https://api.github.com/repos/osxfuse/osxfuse/releases/latest | grep -Eo '\s\"name\": \"macfuse-.+?\.dmg\"' | awk -F'"' '{print $4}')
        echo -e "\r\n${Green}下载 macFUSE latest...${NC}"
        curl -sL https://github.com/osxfuse/osxfuse/releases/latest/download/"${fuse_version}" -o /tmp/macfuse.dmg || { ERROR "下载失败，请检查网络后重试"; exit 1; }

        sudo spctl --master-disable
        if [ $? -eq 0 ]; then
            echo -e "macFUSE 下载完成"
        else
            echo -e "${Red}网络中断，请检查网络${NC}"
            exit 1
        fi
        hdiutil mount /tmp/macfuse.dmg
        installer -pkg "/Volumes/macFUSE/Install macFUSE.pkg" -target /
        hdiutil unmount /Volumes/macFUSE
        rm -rf /tmp/macfuse.dmg
        fi
    fi

    package_name="fuse3" 
    if [ -f /etc/os-release ]; then
        . /etc/os-release      
        case $ID in
            ubuntu|debian)
                apt-get update
                apt-get install -y $package_name
                ;;
            centos)
                yum install -y $package_name
                ;;
            arch|manjaro)
                pacman -Syu $package_name
                ;;
            *)
                echo -e "${Red}未知: $ID, 可能无法挂载${NC}"
                ;;
        esac
    elif [[ -f /etc/synoinfo.conf ]]; then
        if [ -f /bin/fusermount ];then
            ln -s /bin/fusermount /bin/fusermount3
        else
            if [ -z "$(ls -A "/opt")" ]; then
                mkdir -p /volume1/@Entware/opt
                rm -rf /opt
                mkdir /opt
                mount -o bind "/volume1/@Entware/opt" /opt
                cpu_arch=$(uname -m)
                case $cpu_arch in
                "x86_64" | *"amd64"*)
                    wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh || { echo "下载失败"; exit 1; }
                    ;;
                "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
                    wget -O - http://bin.entware.net/aarch64-k3.10/installer/generic.sh | /bin/sh || { echo "下载失败"; exit 1; }
                    ;;
                *)
                    ERROR "不支持你的CPU架构：$cpu_arch"
                    exit 1
                    ;;
                esac
            else
                echo "您的/opt目录不是空的，请手动备份或清空后重新运行脚本！"
                exit 1
            fi
        fi
    else
        echo -e "${Red}未知: $ID, 可能无法挂载${NC}"
    fi
}

daemon() {
    if [[ "$os_type" == "Linux" ]]; then
        if [[ -f /etc/synoinfo.conf ]]; then
            if ! [ -z "$(ls -A /volume1/@Entware/opt > /dev/null 2>&1)" ]; then
                cat <<EOF > /volume1/@Entware/opt/autostart_fuse3.sh
#!/bin/sh
mkdir -p /opt
mount -o bind "/volume1/@Entware/opt" /opt
/opt/etc/init.d/rc.unslung start
if grep  -qF  '/opt/etc/profile' /etc/profile; then
    echo "Confirmed: Entware Profile in Global Profile"
else
    echo "Adding: Entware Profile in Global Profile"
cat >> /etc/profile <<"EOP"
. /opt/etc/profile
EOP
fi
/opt/bin/opkg update
mount --bind "$INSTALL_PATH/media" "$INSTALL_PATH/media" >> /volume1/@Entware/opt/cron.log
mount --make-shared "$INSTALL_PATH/media" >> /volume1/@Entware/opt/cron.log
EOF
                cp /opt/autostart_fuse3.sh /usr/local/etc/rc.d/autostart_fuse3.sh
                chmod +x /opt/autostart_fuse3.sh /usr/local/etc/rc.d/autostart_fuse3.sh
                echo -e "\033[1;35m已创建开机自启动脚本/usr/local/etc/rc.d/autostart_fuse3.sh\033[0m"
                touch /volume1/@Entware/opt/cron.log && chmod 777 /volume1/@Entware/opt/cron.log
            else
                cat <<EOF > /usr/local/etc/rc.d/autostart_fuse3.sh
#!/bin/sh
mount --bind "$INSTALL_PATH/media" "$INSTALL_PATH/media" >> /tmp/cron.log
mount --make-shared "$INSTALL_PATH/media" >> /tmp/cron.log
EOF
                chmod +x /usr/local/etc/rc.d/autostart_fuse3.sh
            fi
            echo -e "\033[1;35m已创建开机自启动脚本/usr/local/etc/rc.d/autostart_fuse3.sh\033[0m"
            INFO "好腻害！群晖你都能搞定！"         
        elif [ -e "/sbin/procd" ]; then
            touch /etc/init.d/clouddrive
            cat > /etc/init.d/clouddrive << EOF
#!/bin/sh /etc/rc.common

USE_PROCD=1

START=99
STOP=99

start_service() {
    procd_open_instance
    procd_set_param command $INSTALL_PATH/clouddrive
    procd_set_param respawn
    procd_set_param pidfile /var/run/clouddrive.pid
    procd_close_instance
}
EOF
            chmod +x /etc/init.d/clouddrive
            /etc/init.d/clouddrive start
            /etc/init.d/clouddrive enable
            INFO "已成功创建docker共享挂载点开机自启动！"
            INFO "安装成功！妈妈再也不用担心你重启断片了！"
        elif pidof systemd > /dev/null; then
            mkdir -p /etc/systemd/system/docker.service.d/
            cat > /etc/systemd/system/docker.service.d/clear_mount_propagation_flags.conf << EOF
[Service]
MountFlags=shared
EOF
            systemctl daemon-reload
            systemctl restart docker.service
            INFO "已成功创建docker共享挂载点开机自启动！"
            INFO "恭喜你安装成功了！"
        else
            echo -e "\033[1;31m不确定系统类型，请自行配置"${INSTALL_PATH}/media"目录共享挂载的开机自启动。\033[0m"
        fi
    elif [[ "$os_type" == "Darwin" ]]; then
        cat > /Library/LaunchDaemons/clouddrive.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>clouddirve</string>
        <key>KeepAlive</key>
        <true/>
        <key>ProcessType</key>
        <string>Background</string>
        <key>RunAtLoad</key>
        <true/>
        <key>WorkingDirectory</key>
        <string>$INSTALL_PATH</string>
        <key>ProgramArguments</key>
        <array>
            <string>$INSTALL_PATH/clouddrive</string>
        </array>
    </dict>
</plist>
EOF
        launchctl load -w /Library/LaunchDaemons/clouddrive.plist
        launchctl start /Library/LaunchDaemons/clouddrive.plist
        INFO "厉害啊！这么快你就安装成功了！"
    fi
}

uninstall() {
    read -p "是否保留CD2的配置文件? (y/n): " keep_config
    mount=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/CloudNAS"}}{{.Source}}{{end}}{{end}}' clouddrive2)
    docker rm -f clouddrive2
    if ! fusermount3 -u "$mount" > /dev/null 2>&1; then
        umount -l "$mount"
    fi
    if [[ "$keep_config" == [Nn] ]]; then
        rm -rf "$(dirname "$mount")/config"
    fi
    rm -rf "$mount"

    if [ ! -d "$mount" ]; then
        echo "删除${mount}目录成功"
    else
        echo "删除${mount}目录失败，请重启后手动删除！"
    fi

    if [[ -f /etc/synoinfo.conf ]]; then
        rm -f /usr/local/etc/rc.d/autostart_fuse3.sh
        sed -i '/\/opt\/etc\/profile/d' /etc/profile
        # if [ -d "/volume1/@Entware/opt" ]; then
        #     rm -rf /volume1/@Entware/opt
        # fi
    elif [ -e "/sbin/procd" ]; then
        /etc/init.d/clouddrive stop
        /etc/init.d/clouddrive disable
        rm -f /etc/init.d/clouddrive
    elif pidof systemd > /dev/null; then
        rm -rf /etc/systemd/system/docker.service.d
        systemctl daemon-reload
    elif [[ "$os_type" == "Darwin" ]]; then
        rm -f /Library/LaunchDaemons/clouddrive.plist
    else
        echo "未识别系统类型，请手动清理共享挂载点的开机自启设置！"
    fi
    INFO "卸载完成！江湖再见！"
}

main() {
    root_need
    ___install_docker
    os_type=$(uname)
    if ! mount --help | grep -q -- "--bind" || ! mount --help | grep -q -- "--make-shared"; then
        echo "当前环境的mount不支持 --bind 和 --make-shared 选项，可能不支持CD2，请自行更新mount命令后重新运行脚本！"
        exit 1
    fi

    if ! command -v fusermount3 >/dev/null 2>&1; then
        echo "fusermount3 未安装，正在安装..."
        fuse3_install
    fi

    if ! command -v fusermount3 >/dev/null 2>&1; then
        echo "fusermount3 安装失败，请检查。"
        exit 1
    fi

    while true; do
        read -erp "请输入安装目录: " INSTALL_PATH
        mkdir -p "$INSTALL_PATH"
        if [ $? -eq 0 ]; then
            break
        else
            echo "您输入的目录不正确，请重新输入。"
        fi
    done

    mkdir -p "$INSTALL_PATH/config" "$INSTALL_PATH/media"

    if ! mount --bind "$INSTALL_PATH/media" "$INSTALL_PATH/media" || ! mount --make-shared "$INSTALL_PATH/media"; then
        echo "设置目录为共享挂载点操作失败，程序退出。"
        exit 1
    fi

    while true; do
        read -erp "是否修改CD2管理端口？(默认 19798) (y/n): " change_port
        if [[ "$change_port" == [Yy] ]]; then
            read -erp "请输入端口: " PORT
        else
            PORT=19798
        fi

        if ! netstat -tuln | grep -q ":$PORT "; then
            break
        else
            echo "端口 $PORT 已被占用，请重新输入。"
        fi
    done

    INFO "正在安装……"
    docker pull cloudnas/clouddrive2:latest
    if [ "$PORT" == "19798" ]; then
        docker run -d \
            --name clouddrive2 \
            --restart always \
            --env CLOUDDRIVE_HOME=/Config \
            -v "$INSTALL_PATH/media:/CloudNAS:shared" \
            -v "$INSTALL_PATH/config:/Config" \
            --network host \
            --pid host \
            --privileged \
            --device /dev/fuse:/dev/fuse \
            cloudnas/clouddrive2:latest
    else
        docker run -d \
            --name clouddrive2 \
            --restart always \
            --env CLOUDDRIVE_HOME=/Config \
            -v "$INSTALL_PATH/media:/CloudNAS:shared" \
            -v "$INSTALL_PATH/config:/Config" \
            --privileged \
            --device /dev/fuse:/dev/fuse \
            -p "$PORT:19798" \
            cloudnas/clouddrive2:latest
    fi

    if [ $? -eq 0 ]; then
        INFO "clouddrive2 容器已成功运行"
        local_ip=$(ip address | grep inet | grep -v 172.17 | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed 's/addr://' | head -n1 | cut -f1 -d"/")
        INFO "请打开http://${local_ip}:${PORT}添加挂载"
    else
        ERROR "clouddrive2 容器未能成功运行，请检查是否存在旧容器冲突"
        exit 1
    fi

    daemon
}

if [ "${1}" == "uninstall" ]; then
    uninstall
else
    main
fi


