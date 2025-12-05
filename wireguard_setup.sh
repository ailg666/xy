#!/bin/bash

# WireGuard自动安装配置脚本
# 兼容xy_ailg.sh的日志风格

# 脚本版本
SCRIPT_VERSION="v0.2.4"

Green="\033[32m"
Red="\033[31m"
Yellow='\033[33m'
Blue='\033[34m'
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

# 全局变量
WG_DIR="/etc/wireguard"
WG_CONFIG_DIR="${WG_DIR}/configs"
WG_KEYS_DIR="${WG_DIR}/keys"
WG_TUNNELS_DIR="${WG_DIR}/tunnels"  # 存储多隧道信息
WG_INTERFACE="wg0"  # 当前操作的接口，动态设置
WG_PORT="51820"     # 当前操作的端口，动态设置
WG_NETWORK="10.3.3.0/24"  # 当前操作的网段，动态设置
WG_SERVER_IP="10.3.3.1"   # 当前操作的服务端IP，动态设置
PUBLIC_IP=""
CURRENT_TUNNEL=""   # 当前选择的隧道名称
SERVICE_MANAGER=""  # 服务管理系统
FIREWALL_TYPE=""    # 防火墙类型
STARTUP_METHOD=""   # 开机自启动方式

# 检测操作系统和包管理器
detect_os() {
    # 检测特殊系统
    if [ -f /etc/synoinfo.conf ]; then
        OS="synology"
        WARN "检测到群晖系统，WireGuard安装可能需要特殊处理"
        return 1
    elif [ -f /etc/unraid-version ]; then
        OS="unraid"
        WARN "检测到Unraid系统，WireGuard安装可能需要特殊处理"
        return 1
    fi

    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt-get"
        OS="debian-based"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
        OS="rhel-based"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        OS="fedora-based"
    elif command -v zypper &> /dev/null; then
        PACKAGE_MANAGER="zypper"
        OS="suse-based"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
        OS="arch-based"
    elif command -v apk &> /dev/null; then
        PACKAGE_MANAGER="apk"
        OS="alpine"
    elif command -v opkg &> /dev/null; then
        PACKAGE_MANAGER="opkg"
        OS="openwrt-based"
    else
        ERROR "未找到支持的包管理器"
        return 1
    fi

    INFO "检测到系统类型: $OS，包管理器: $PACKAGE_MANAGER"
    return 0
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        ERROR "此脚本需要root权限运行"
        exit 1
    fi
}

# 配置安装路径
configure_install_path() {
    echo -e "\n${Blue}=== WireGuard安装路径配置 ===${Font}"

    # 检测特殊系统并推荐路径
    if [ -f /etc/synoinfo.conf ]; then
        echo -e "${Yellow}检测到群晖系统${Font}"
        echo "推荐路径: /volume1/docker/wireguard 或 /volume1/@appstore/wireguard"
        echo "默认路径: /etc/wireguard"
    elif [ -f /etc/unraid-version ]; then
        echo -e "${Yellow}检测到Unraid系统${Font}"
        echo "推荐路径: /mnt/user/appdata/wireguard"
        echo "默认路径: /etc/wireguard"
    elif ps x | grep -q "/usr/trim/bin/trim$" 2>/dev/null; then
        echo -e "${Yellow}检测到飞牛OS系统${Font}"
        echo "推荐路径: /vol1/1000/wireguard"
        echo "默认路径: /etc/wireguard"
    else
        echo "当前系统: $(uname -s)"
        echo "默认路径: /etc/wireguard"
    fi

    echo
    echo "路径选择："
    echo "1. 使用默认路径 (/etc/wireguard)"
    echo "2. 自定义安装路径"
    read -p "请选择 [1-2, 默认: 1]: " path_choice

    if [[ "$path_choice" == "1" ]] || [[ -z "$path_choice" ]]; then
        # 选择默认路径 /etc/wireguard
        local default_dir="/etc/wireguard"

        # 检查当前 /etc/wireguard 的状态
        if [[ -L "$default_dir" ]]; then
            # 是软链接，需要转换为真实目录
            local real_dir=$(readlink "$default_dir")
            echo -e "\n${Yellow}检测到 /etc/wireguard 是软链接${Font}"
            echo "当前指向: $real_dir"
            echo "选择默认路径将把 /etc/wireguard 转换为真实目录"

            # 检查是否有配置需要迁移
            if [[ -d "$real_dir" ]] && [[ -n "$(ls "$real_dir"/*.conf 2>/dev/null)" ]]; then
                echo -e "\n${Yellow}检测到现有配置文件${Font}"
                echo "原真实目录: $real_dir"
                echo "新真实目录: $default_dir"
                read -p "是否迁移现有配置到默认目录? (Y/n): " migrate_config

                if [[ ! "$migrate_config" =~ ^[Nn]$ ]]; then
                    INFO "迁移配置文件到默认目录..."

                    # 记录当前运行的隧道
                    local running_interfaces=()
                    for conf_file in "$real_dir"/*.conf; do
                        [[ -f "$conf_file" ]] || continue
                        local interface=$(basename "$conf_file" .conf)
                        if wg show "$interface" &>/dev/null; then
                            running_interfaces+=("$interface")
                            INFO "停止隧道: $interface"
                            wg-quick down "$conf_file" 2>/dev/null || true
                        fi
                    done

                    # 删除软链接
                    rm "$default_dir"
                    INFO "已删除软链接: $default_dir"

                    # 创建真实目录并复制配置
                    mkdir -p "$default_dir"
                    mkdir -p "${default_dir}/configs"
                    mkdir -p "${default_dir}/keys"
                    mkdir -p "${default_dir}/tunnels"

                    if cp -r "$real_dir"/* "$default_dir"/ 2>/dev/null; then
                        INFO "配置文件迁移成功"

                        # 询问是否删除原配置目录
                        read -p "是否删除原配置目录 $real_dir? (y/N): " remove_old
                        if [[ "$remove_old" =~ ^[Yy]$ ]]; then
                            rm -rf "$real_dir"
                            INFO "原配置目录已删除: $real_dir"
                        else
                            INFO "保留原配置目录: $real_dir"
                        fi

                        # 重启之前运行的隧道
                        if [[ ${#running_interfaces[@]} -gt 0 ]]; then
                            echo -e "\n${Yellow}重启之前运行的隧道${Font}"
                            for interface in "${running_interfaces[@]}"; do
                                local new_conf_file="${default_dir}/${interface}.conf"
                                if [[ -f "$new_conf_file" ]]; then
                                    INFO "重启隧道: $interface"
                                    if wg-quick up "$new_conf_file" 2>/dev/null; then
                                        INFO "隧道 $interface 启动成功"
                                    else
                                        WARN "隧道 $interface 启动失败，请手动检查配置"
                                    fi
                                else
                                    WARN "未找到隧道配置文件: $new_conf_file"
                                fi
                            done
                        fi
                    else
                        ERROR "配置文件迁移失败"
                        return 1
                    fi
                else
                    # 不迁移，只删除软链接创建空的真实目录
                    rm "$default_dir"
                    mkdir -p "$default_dir"
                    mkdir -p "${default_dir}/configs"
                    mkdir -p "${default_dir}/keys"
                    mkdir -p "${default_dir}/tunnels"
                    INFO "已创建空的默认目录: $default_dir"
                fi
            else
                # 没有配置文件，直接转换
                rm "$default_dir"
                mkdir -p "$default_dir"
                mkdir -p "${default_dir}/configs"
                mkdir -p "${default_dir}/keys"
                mkdir -p "${default_dir}/tunnels"
                INFO "已转换为真实目录: $default_dir"
            fi
        elif [[ ! -d "$default_dir" ]]; then
            # 目录不存在，创建它
            mkdir -p "$default_dir"
            mkdir -p "${default_dir}/configs"
            mkdir -p "${default_dir}/keys"
            mkdir -p "${default_dir}/tunnels"
            INFO "已创建默认目录: $default_dir"
        fi

        WG_DIR="$default_dir"

    elif [[ "$path_choice" == "2" ]]; then
        while true; do
            read -p "请输入自定义安装路径 (如: /opt/wireguard): " custom_path

            if [[ -z "$custom_path" ]]; then
                ERROR "路径不能为空"
                continue
            fi

            # 检查路径格式
            if [[ ! "$custom_path" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
                ERROR "路径格式无效，请使用绝对路径"
                continue
            fi

            if [[ "$custom_path" == "/etc/wireguard" ]]; then
                ERROR "自定义路径不能使用默认的/etc/wireguard"
                continue
            fi

            # 检查是否有现有配置需要迁移
            local old_wg_dir="$WG_DIR"
            local real_old_dir="$old_wg_dir"
            local has_existing_config=false

            # 如果当前WG_DIR是软链接，获取真实路径
            if [[ -L "$old_wg_dir" ]]; then
                real_old_dir=$(readlink "$old_wg_dir")
                INFO "检测到软链接: $old_wg_dir -> $real_old_dir"
            fi

            if [[ -d "$real_old_dir" ]] && [[ -n "$(ls "$real_old_dir"/*.conf 2>/dev/null)" ]]; then
                has_existing_config=true
            fi

            # 检查路径是否可创建/访问
            if ! mkdir -p "$custom_path" 2>/dev/null; then
                ERROR "无法创建目录: $custom_path"
                continue
            fi

            # 检查路径权限
            if [[ ! -w "$custom_path" ]]; then
                ERROR "目录无写入权限: $custom_path"
                continue
            fi

            # 如果有现有配置，询问是否迁移
            if [[ "$has_existing_config" == true ]] && [[ "$custom_path" != "$real_old_dir" ]]; then
                echo -e "\n${Yellow}检测到现有配置文件${Font}"
                if [[ "$real_old_dir" != "$old_wg_dir" ]]; then
                    echo "当前配置: $old_wg_dir -> $real_old_dir (软链接)"
                    echo "真实路径: $real_old_dir"
                else
                    echo "原路径: $real_old_dir"
                fi
                echo "新路径: $custom_path"
                read -p "是否迁移现有配置到新路径? (Y/n): " migrate_config

                if [[ ! "$migrate_config" =~ ^[Nn]$ ]]; then
                    INFO "迁移配置文件到新路径..."

                    # 记录当前运行的隧道
                    local running_interfaces=()
                    for conf_file in "$real_old_dir"/*.conf; do
                        [[ -f "$conf_file" ]] || continue
                        local interface=$(basename "$conf_file" .conf)
                        if wg show "$interface" &>/dev/null; then
                            running_interfaces+=("$interface")
                            INFO "停止隧道: $interface"
                            wg-quick down "$conf_file" 2>/dev/null || true
                        fi
                    done

                    # 复制配置文件
                    if cp -r "$real_old_dir"/* "$custom_path"/ 2>/dev/null; then
                        INFO "配置文件迁移成功"

                        # 询问是否删除原配置目录（配置已迁移到新目录）
                        read -p "是否删除原配置目录 $real_old_dir? (y/N): " remove_old
                        if [[ "$remove_old" =~ ^[Yy]$ ]]; then
                            # 删除真实目录（软链接会自动失效）
                            rm -rf "$real_old_dir"
                            INFO "原配置目录已删除: $real_old_dir"

                            # 如果存在指向已删除目录的软链接，也删除它
                            if [[ -L "$old_wg_dir" ]] && [[ ! -e "$old_wg_dir" ]]; then
                                rm "$old_wg_dir"
                                INFO "已清理失效的软链接: $old_wg_dir"
                            fi
                        else
                            INFO "保留原配置目录: $real_old_dir"
                        fi

                        # 先设置软链接，确保后续重启隧道时能找到配置
                        WG_DIR="$custom_path"
                        if setup_wireguard_symlink; then
                            # 重启之前运行的隧道
                            if [[ ${#running_interfaces[@]} -gt 0 ]]; then
                                echo -e "\n${Yellow}重启之前运行的隧道${Font}"
                                for interface in "${running_interfaces[@]}"; do
                                    local new_conf_file="/etc/wireguard/${interface}.conf"
                                    if [[ -f "$new_conf_file" ]]; then
                                        INFO "重启隧道: $interface"
                                        if wg-quick up "$new_conf_file" 2>/dev/null; then
                                            INFO "隧道 $interface 启动成功"
                                        else
                                            WARN "隧道 $interface 启动失败，请手动检查配置"
                                        fi
                                    else
                                        WARN "未找到隧道配置文件: $new_conf_file"
                                    fi
                                done
                            fi
                        else
                            WARN "软链接设置失败，请手动重启隧道"
                        fi
                    else
                        ERROR "配置文件迁移失败"
                        continue
                    fi
                else
                    # 用户选择不迁移配置，但仍需要设置自定义路径
                    WG_DIR="$custom_path"

                    # 创建必要的子目录
                    mkdir -p "${custom_path}/configs"
                    mkdir -p "${custom_path}/keys"
                    mkdir -p "${custom_path}/tunnels"

                    # 设置软链接
                    if ! setup_wireguard_symlink; then
                        ERROR "软链接设置失败"
                        return 1
                    fi
                fi
            else
                # 没有现有配置，或路径相同，直接设置自定义路径
                WG_DIR="$custom_path"

                # 创建必要的子目录
                mkdir -p "${custom_path}/configs"
                mkdir -p "${custom_path}/keys"
                mkdir -p "${custom_path}/tunnels"

                # 设置软链接
                if ! setup_wireguard_symlink; then
                    ERROR "软链接设置失败"
                    return 1
                fi
            fi

            break
        done
    fi

    # 更新相关路径变量
    WG_CONFIG_DIR="${WG_DIR}/configs"
    WG_KEYS_DIR="${WG_DIR}/keys"
    WG_TUNNELS_DIR="${WG_DIR}/tunnels"

    INFO "WireGuard安装路径: $WG_DIR"
    INFO "配置文件目录: $WG_CONFIG_DIR"
    INFO "密钥文件目录: $WG_KEYS_DIR"
    INFO "隧道信息目录: $WG_TUNNELS_DIR"
}

# 检测并配置公网IP
configure_public_ip() {
    local external_ipv4
    local external_ipv6
    local selected_ip
    local ip_version

    # 确保依赖
    ensure_curl
    ensure_dns_tools

    # 获取外部检测到的IPv4地址
    INFO "正在检测IPv4地址..."
    external_ipv4=$(curl -s --max-time 10 ipv4.icanhazip.com 2>/dev/null || curl -s --max-time 10 -4 ifconfig.me 2>/dev/null || curl -s --max-time 10 -4 ip.sb 2>/dev/null)

    # 获取外部检测到的IPv6地址
    INFO "正在检测IPv6地址..."
    external_ipv6=$(curl -s --max-time 10 ipv6.icanhazip.com 2>/dev/null || curl -s --max-time 10 -6 ifconfig.me 2>/dev/null || curl -s --max-time 10 -6 ip.sb 2>/dev/null)

    # 显示检测结果
    echo -e "\n${Blue}=== IP地址检测结果 ===${Font}"
    if [[ -n "$external_ipv4" ]]; then
        INFO "检测到IPv4地址: $external_ipv4"
    else
        WARN "未检测到IPv4地址"
    fi

    if [[ -n "$external_ipv6" ]]; then
        INFO "检测到IPv6地址: $external_ipv6"
    else
        WARN "未检测到IPv6地址"
    fi

    # 选择IP版本
    local manual_input=false
    if [[ -n "$external_ipv4" && -n "$external_ipv6" ]]; then
        echo -e "\n${Yellow}检测到双栈网络环境，请选择使用的IP版本：${Font}"
        echo "1. IPv4: $external_ipv4"
        echo "2. IPv6: $external_ipv6"
        echo "3. 手动输入IP地址"
        read -p "请选择 [1-3, 默认: 1]: " ip_choice

        case "$ip_choice" in
            2)
                selected_ip="$external_ipv6"
                ip_version="ipv6"
                ;;
            3)
                read -p "请输入服务器公网IP地址: " selected_ip
                manual_input=true
                # 判断输入的是IPv4还是IPv6
                if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    ip_version="ipv4"
                elif [[ "$selected_ip" =~ : ]]; then
                    ip_version="ipv6"
                else
                    ERROR "无效的IP地址格式"
                    exit 1
                fi
                ;;
            *)
                selected_ip="$external_ipv4"
                ip_version="ipv4"
                ;;
        esac
    elif [[ -n "$external_ipv4" ]]; then
        echo -e "\n${Yellow}选择IP版本：${Font}"
        echo "1. 使用检测到的IPv4: $external_ipv4"
        echo "2. 手动输入IP地址"
        read -p "请选择 [1-2, 默认: 1]: " ip_choice

        if [[ "$ip_choice" == "2" ]]; then
            read -p "请输入服务器公网IP地址: " selected_ip
            manual_input=true
            if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ip_version="ipv4"
            elif [[ "$selected_ip" =~ : ]]; then
                ip_version="ipv6"
            else
                ERROR "无效的IP地址格式"
                exit 1
            fi
        else
            selected_ip="$external_ipv4"
            ip_version="ipv4"
        fi
    elif [[ -n "$external_ipv6" ]]; then
        echo -e "\n${Yellow}选择IP版本：${Font}"
        echo "1. 使用检测到的IPv6: $external_ipv6"
        echo "2. 手动输入IP地址"
        read -p "请选择 [1-2, 默认: 1]: " ip_choice

        if [[ "$ip_choice" == "2" ]]; then
            read -p "请输入服务器公网IP地址: " selected_ip
            manual_input=true
            if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ip_version="ipv4"
            elif [[ "$selected_ip" =~ : ]]; then
                ip_version="ipv6"
            else
                ERROR "无效的IP地址格式"
                exit 1
            fi
        else
            selected_ip="$external_ipv6"
            ip_version="ipv6"
        fi
    else
        WARN "无法自动获取外部IP，请手动输入"
        read -p "请输入服务器公网IP地址: " selected_ip
        manual_input=true
        if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ip_version="ipv4"
        elif [[ "$selected_ip" =~ : ]]; then
            ip_version="ipv6"
        else
            ERROR "无效的IP地址格式"
            exit 1
        fi
    fi

    INFO "选择使用 $ip_version 地址: $selected_ip"

    # IPv6或手动输入时跳过WAN口IP比较
    if [[ "$ip_version" == "ipv6" ]]; then
        INFO "IPv6地址无需进行WAN口IP比较"
    elif [[ "$manual_input" == true ]]; then
        INFO "使用手动输入的IP地址"
    else
        # 仅对IPv4进行WAN口IP比较
        echo -e "\n${Yellow}请确认您的路由器WAN口IP地址：${Font}"
        echo "您可以登录路由器管理界面查看WAN口IP（注意：不是LAN口内网IP）"

        echo
        read -p "请输入您的路由器WAN口IP地址（与检测IP一致可按Y/y回车）: " user_wan_ip

        # 处理Y/y快捷确认
        if [[ "$user_wan_ip" =~ ^[Yy]$ ]]; then
            user_wan_ip="$selected_ip"
            INFO "已确认WAN口IP与检测IP一致: $selected_ip"
        fi

        # 比较外部IP和WAN口IP
        if [[ "$selected_ip" != "$user_wan_ip" ]]; then
            ERROR "检测到大内网环境！"
            echo -e "${Red}外部检测IP: $selected_ip${Font}"
            echo -e "${Red}路由器WAN口IP: $user_wan_ip${Font}"
            echo
            echo "当前服务器处于大内网环境（如运营商NAT），无法直接提供WireGuard服务"
            echo "解决方案："
            echo "1. 联系运营商申请公网IP"
            echo "2. 使用内网穿透服务（如frp、ngrok等）"
            echo "3. 使用云服务器搭建WireGuard"
            echo
            read -p "是否继续安装？(不推荐，客户端可能无法连接) (y/N): " force_install

            if [[ ! "$force_install" =~ ^[Yy]$ ]]; then
                echo "安装已取消"
                exit 1
            else
                WARN "强制继续安装，但客户端可能无法正常连接"
                PUBLIC_IP="$selected_ip"
                return
            fi
        fi

        INFO "检测到真实公网IP环境"
    fi

    # 询问是否为动态IP（无论是自动检测还是手动输入都需要确认）
    echo -e "\n${Blue}=== 公网IP类型确认 ===${Font}"
    echo "1. 静态公网IP (IP地址固定不变)"
    echo "2. 动态公网IP (IP地址会定期变化)"
    read -p "请选择您的公网IP类型 [1-2]: " ip_type

    if [[ "$ip_type" == "2" ]]; then
        echo -e "${Yellow}动态公网IP建议使用域名配置WireGuard，而不是直接使用IP地址${Font}"

        while true; do
            read -p "是否要使用域名配置？(y/N): " use_domain

            if [[ "$use_domain" =~ ^[Yy]$ ]]; then
                while true; do
                    read -p "请输入您的域名: " domain_name
                    if [[ -z "$domain_name" ]]; then
                        WARN "域名不能为空，请重新输入"
                        continue
                    fi

                    # 检查域名解析
                    INFO "正在检查域名解析..."
                    local domain_ip

                    if [[ "$ip_version" == "ipv4" ]]; then
                        # IPv4解析
                        domain_ip=$(nslookup "$domain_name" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
                        if [[ -z "$domain_ip" ]]; then
                            # 尝试使用dig命令
                            domain_ip=$(dig +short "$domain_name" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
                        fi
                    else
                        # IPv6解析
                        domain_ip=$(nslookup "$domain_name" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | grep ":" | head -1)
                        if [[ -z "$domain_ip" ]]; then
                            # 尝试使用dig命令
                            domain_ip=$(dig +short "$domain_name" AAAA 2>/dev/null | grep ":" | head -1)
                        fi
                    fi

                    if [[ -z "$domain_ip" ]]; then
                        ERROR "无法解析域名 $domain_name 的 $ip_version 记录"
                        read -p "是否重新输入域名？(y/N): " retry_domain
                        if [[ ! "$retry_domain" =~ ^[Yy]$ ]]; then
                            break
                        fi
                        continue
                    fi

                    INFO "域名 $domain_name 解析到 $ip_version 地址: $domain_ip"

                    if [[ "$domain_ip" == "$selected_ip" ]]; then
                        INFO "域名解析IP与检测IP一致，可以使用"
                        PUBLIC_IP="$domain_name"
                        return
                    else
                        WARN "域名解析IP ($domain_ip) 与检测IP ($selected_ip) 不一致"
                        echo "这可能是因为："
                        echo "1. DDNS尚未更新到最新IP"
                        echo "2. 域名配置错误"
                        echo "3. DNS缓存问题"
                        echo
                        echo "建议："
                        echo "1. 确保DDNS服务正常工作并已更新"
                        echo "2. 等待DNS传播完成（可能需要几分钟到几小时）"
                        echo "3. 检查域名配置是否正确"
                        echo
                        read -p "选择操作: [1]重新输入域名 [2]配置好DDNS后再安装 [3]继续使用此域名: " domain_choice

                        case "$domain_choice" in
                            1)
                                continue
                                ;;
                            2)
                                echo "请配置好DDNS后重新运行安装脚本"
                                exit 1
                                ;;
                            3)
                                WARN "继续使用域名 $domain_name，但可能导致连接问题"
                                echo "请确保在安装完成后配置好DDNS，否则客户端可能无法连接"
                                PUBLIC_IP="$domain_name"
                                return
                                ;;
                            *)
                                WARN "无效选择，重新输入域名"
                                continue
                                ;;
                        esac
                    fi
                done
                break
            else
                WARN "使用动态IP地址配置可能导致客户端连接失败"
                echo "当IP地址变化时，需要重新生成客户端配置"
                break
            fi
        done
    fi

    PUBLIC_IP="$selected_ip"
}

# 获取公网IP（兼容旧版本调用）
get_public_ip() {
    echo "$PUBLIC_IP"
}

# 检测网络接口
get_network_interface() {
    local interface
    interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$interface" ]]; then
        interface=$(ls /sys/class/net | grep -v lo | head -n1)
    fi
    if [[ -z "$interface" ]]; then
        ERROR "无法检测到网络接口"
        return 1
    fi
    echo "$interface"
}

# 获取服务端主机的局域网段
get_server_lan_network() {
    local interface=$(get_network_interface)
    if [[ $? -ne 0 ]] || [[ -z "$interface" ]]; then
        return 1
    fi

    # 从路由表直接获取网段信息
    local network=$(ip route show | grep "$interface" | grep -v default | cut -d' ' -f1 | head -n1)
    if [[ -z "$network" ]]; then
        return 1
    fi

    echo "$network"
}

# 设置WireGuard目录软链接
setup_wireguard_symlink() {
    local custom_dir="$WG_DIR"  # 用户的自定义目录
    local default_dir="/etc/wireguard"

    # 如果自定义目录就是默认目录，无需处理
    if [[ "$custom_dir" == "$default_dir" ]]; then
        return 0
    fi

    INFO "设置WireGuard目录软链接: $default_dir -> $custom_dir"

    # 检查 /etc/wireguard 的状态
    if [[ -L "$default_dir" ]]; then
        # 已经是软链接，检查是否指向正确位置
        local current_target=$(readlink "$default_dir")
        if [[ "$current_target" == "$custom_dir" ]]; then
            INFO "/etc/wireguard 已正确链接到 $custom_dir"
            return 0
        else
            WARN "/etc/wireguard 链接到 $current_target，将重新链接到 $custom_dir"
            rm "$default_dir"
        fi
    elif [[ -d "$default_dir" ]]; then
        # 是真实目录，需要处理现有内容
        if [[ -n "$(ls -A "$default_dir" 2>/dev/null)" ]]; then
            echo -e "\n${Yellow}检测到 /etc/wireguard 目录中有现有配置${Font}"
            echo "将会："
            echo "1. 将现有配置迁移到自定义目录 $custom_dir"
            echo "2. 删除 /etc/wireguard 目录"
            echo "3. 创建软链接 /etc/wireguard -> $custom_dir"
            read -p "是否继续? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                ERROR "操作已取消，可以手动备份/etc/wireguard中的配置，然后清空后重新安装"
                return 1
            fi

            # 迁移现有配置
            mkdir -p "$custom_dir"
            mkdir -p "${custom_dir}/configs"
            mkdir -p "${custom_dir}/keys"
            mkdir -p "${custom_dir}/tunnels"

            # 迁移配置文件
            if [[ -d "${default_dir}/configs" ]]; then
                cp -r "${default_dir}/configs"/* "${custom_dir}/configs/" 2>/dev/null || true
            fi
            if [[ -d "${default_dir}/keys" ]]; then
                cp -r "${default_dir}/keys"/* "${custom_dir}/keys/" 2>/dev/null || true
            fi
            if [[ -d "${default_dir}/tunnels" ]]; then
                cp -r "${default_dir}/tunnels"/* "${custom_dir}/tunnels/" 2>/dev/null || true
            fi

            # 迁移根目录下的配置文件
            for file in "${default_dir}"/*.conf; do
                [[ -f "$file" ]] && cp "$file" "$custom_dir/"
            done

            INFO "配置已迁移到 $custom_dir"
        fi

        # 删除原目录
        rm -rf "$default_dir"
    elif [[ -f "$default_dir" ]]; then
        # 如果是文件，先备份再删除
        WARN "/etc/wireguard 是一个文件，将备份为 /etc/wireguard.bak"
        mv "$default_dir" "${default_dir}.bak"
    fi

    # 创建自定义目录（如果不存在）
    mkdir -p "$custom_dir"
    mkdir -p "${custom_dir}/configs"
    mkdir -p "${custom_dir}/keys"
    mkdir -p "${custom_dir}/tunnels"

    # 创建软链接
    ln -s "$custom_dir" "$default_dir"
    INFO "已创建软链接: /etc/wireguard -> $custom_dir"

    # 更新全局变量指向默认路径（因为现在软链接已经统一了）
    WG_DIR="/etc/wireguard"
    WG_CONFIG_DIR="${WG_DIR}/configs"
    WG_KEYS_DIR="${WG_DIR}/keys"
    WG_TUNNELS_DIR="${WG_DIR}/tunnels"

    return 0
}

# 安装WireGuard
install_wireguard() {
    # 检查WireGuard是否已安装
    if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
        INFO "WireGuard已安装，跳过安装步骤"
        # 仍然尝试安装qrencode
        INFO "检查qrencode工具..."
        install_qrencode
        return 0
    fi

    INFO "开始安装WireGuard..."

    case $PACKAGE_MANAGER in
        "apt-get")
            apt-get update -y
            apt-get install -y wireguard wireguard-tools
            ;;
        "yum")
            # CentOS 7 需要 EPEL
            if grep -q "CentOS Linux 7" /etc/os-release 2>/dev/null; then
                yum install -y epel-release
            fi
            yum makecache fast
            yum install -y wireguard-tools
            ;;
        "dnf")
            dnf makecache
            dnf install -y wireguard-tools
            ;;
        "zypper")
            zypper refresh
            zypper install -y wireguard-tools
            ;;
        "pacman")
            pacman -Sy
            pacman -S --noconfirm wireguard-tools
            ;;
        "apk")
            apk update
            apk add --no-cache wireguard-tools
            ;;
        "opkg")
            opkg update
            opkg install wireguard-tools
            ;;
        *)
            ERROR "不支持的包管理器: $PACKAGE_MANAGER"
            return 1
            ;;
    esac

    if ! command -v wg &> /dev/null; then
        ERROR "WireGuard安装失败"
        return 1
    fi

    INFO "WireGuard安装成功"

    # 自动尝试安装qrencode
    INFO "尝试安装qrencode以支持二维码功能..."
    install_qrencode

    return 0
}

# 安装qrencode（可选）
install_qrencode() {
    # 检查是否已安装
    if command -v qrencode &> /dev/null; then
        INFO "qrencode已安装，支持二维码功能"
        return 0
    fi

    INFO "正在安装qrencode用于生成二维码..."

    case $PACKAGE_MANAGER in
        "apt-get")
            if apt-get install -y qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "yum")
            if yum install -y qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "dnf")
            if dnf install -y qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "zypper")
            if zypper install -y qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "pacman")
            if pacman -S --noconfirm qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "apk")
            if apk add --no-cache libqrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        "opkg")
            # OpenWrt系统的qrencode包名可能不同
            if opkg install qrencode 2>/dev/null; then
                INFO "qrencode安装成功"
                return 0
            else
                WARN "qrencode安装失败，将使用在线二维码工具"
                return 1
            fi
            ;;
        *)
            WARN "未知包管理器，无法自动安装qrencode"
            return 1
            ;;
    esac
}


# 通用依赖检查与安装
ensure_pkg() {
    local pkg_cmd="$1"   # 要检测的命令名
    local pkg_name="$2"  # 包名称（用于安装）
    if command -v "$pkg_cmd" >/dev/null 2>&1; then
        return 0
    fi
    if [[ -z "$PACKAGE_MANAGER" ]]; then
        detect_os || return 1
    fi
    INFO "未检测到命令 $pkg_cmd，尝试通过 $PACKAGE_MANAGER 安装 $pkg_name..."
    case $PACKAGE_MANAGER in
        "apt-get") apt-get update -y && apt-get install -y "$pkg_name" || return 1 ;;
        "yum") yum install -y "$pkg_name" || return 1 ;;
        "dnf") dnf install -y "$pkg_name" || return 1 ;;
        "zypper") zypper install -y "$pkg_name" || return 1 ;;
        "pacman") pacman -Sy --noconfirm "$pkg_name" || return 1 ;;
        "apk") apk add --no-cache "$pkg_name" || return 1 ;;
        "opkg") opkg update && opkg install "$pkg_name" || return 1 ;;
        *) WARN "未知包管理器，无法自动安装 $pkg_name"; return 1 ;;
    esac
}

ensure_net_tools() {
    # ss 或 netstat 至少一个；ip、iptables也要
    if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
        # 尝试安装常见网络工具包
        case $PACKAGE_MANAGER in
            "apt-get") ensure_pkg netstat net-tools || true ;;
            "yum"|"dnf") ensure_pkg ss iproute || true ; ensure_pkg netstat net-tools || true ;;
            "zypper") ensure_pkg ss iproute2 || true ; ensure_pkg netstat net-tools || true ;;
            "pacman") ensure_pkg ss iproute2 || true ; ensure_pkg netstat net-tools || true ;;
            "apk") ensure_pkg ss iproute2 || true ; ensure_pkg netstat net-tools || true ;;
            "opkg") ensure_pkg ip ip-full || true ;;
        esac
    fi
    # ip 命令
    command -v ip >/dev/null 2>&1 || ensure_pkg ip iproute2 || true
}

ensure_dns_tools() {
    # nslookup 或 dig 用于解析域名
    if ! command -v nslookup >/dev/null 2>&1 && ! command -v dig >/dev/null 2>&1; then
        case $PACKAGE_MANAGER in
            "apt-get") ensure_pkg nslookup dnsutils || true ;;
            "yum"|"dnf") ensure_pkg nslookup bind-utils || true ;;
            "zypper") ensure_pkg nslookup bind-utils || true ;;
            "pacman") ensure_pkg nslookup bind-tools || true ;;
            "apk") ensure_pkg nslookup bind-tools || true ;;
            "opkg") ensure_pkg nslookup bind-dig || true ;;
        esac
    fi
}

ensure_curl() {
    command -v curl >/dev/null 2>&1 || ensure_pkg curl curl || true
}

# 尝试确保 resolvconf（或等效）用于处理 DNS（wg-quick 在有 DNS= 时会调用）
ensure_resolvconf() {
    # 如果已具备 resolvconf 或 systemd-resolved 的 resolvectl，则不处理
    if command -v resolvconf >/dev/null 2>&1 || command -v resolvectl >/dev/null 2>&1; then
        return 0
    fi
    if [[ -z "$PACKAGE_MANAGER" ]]; then
        detect_os || return 1
    fi
    INFO "尝试安装用于 DNS 设置的 resolvconf/openresolv（可选）..."
    case $PACKAGE_MANAGER in
        "apt-get")
            # Debian/Ubuntu 有 resolvconf；如失败可尝试 openresolv（第三方源情况较少）
            apt-get update -y 2>/dev/null || true
            apt-get install -y resolvconf 2>/dev/null || apt-get install -y openresolv 2>/dev/null || true
            ;;
        "yum"|"dnf")
            $PACKAGE_MANAGER install -y openresolv 2>/dev/null || true
            ;;
        "zypper")
            zypper install -y openresolv 2>/dev/null || true
            ;;
        "pacman")
            pacman -Sy --noconfirm openresolv 2>/dev/null || true
            ;;
        "apk")
            apk add --no-cache openresolv 2>/dev/null || true
            ;;
        "opkg")
            opkg update 2>/dev/null || true
            opkg install resolvconf 2>/dev/null || true
            ;;
    esac
}


ensure_qrencode() {
    command -v qrencode >/dev/null 2>&1 || install_qrencode || true
}

# 显示配置二维码
show_qrcode() {
    local config_file="$1"
    local config_name="$2"

    if [[ ! -f "$config_file" ]]; then
        ERROR "配置文件不存在: $config_file"
        return 1
    fi

    echo -e "\n${Blue}=== 配置二维码: $config_name ===${Font}"

    if command -v qrencode &> /dev/null; then
        INFO "使用qrencode生成二维码"
        echo
        # 使用中号大小：模块大小2，边距2 - 平衡显示效果和扫描便利性
        qrencode -t ansiutf8 -s 2 -m 2 < "$config_file"
        echo
        echo -e "${Yellow}提示：可以使用WireGuard客户端扫描上方二维码快速导入配置${Font}"
        echo -e "${Yellow}支持的客户端：WireGuard官方客户端、TunSafe等${Font}"
    else
        WARN "需要安装qrencode后才能使用二维码配置导入功能，可选替代方案："
        echo
        echo -e "${Yellow}方案1：在线二维码生成工具${Font}"
        echo "请将配置内容复制到以下在线工具生成二维码："
        echo "• https://www.qr-code-generator.com/"
        echo "• https://qr.io/"
        echo "• https://qrcode.show/"
        echo
        echo -e "${Yellow}方案2：安装qrencode工具${Font}"
        echo "安装命令："
        case $PACKAGE_MANAGER in
            "apt-get") echo "  sudo apt-get install qrencode" ;;
            "yum") echo "  sudo yum install qrencode" ;;
            "dnf") echo "  sudo dnf install qrencode" ;;
            "zypper") echo "  sudo zypper install qrencode" ;;
            "pacman") echo "  sudo pacman -S qrencode" ;;
            "apk") echo "  sudo apk add libqrencode" ;;
            "opkg") echo "  sudo opkg install qrencode" ;;
            *) echo "  请根据您的系统包管理器安装qrencode" ;;
        esac
        echo
        echo -e "${Yellow}安装后重新运行脚本即可使用二维码功能${Font}"
    fi
}


# 创建目录结构
create_directories() {
    mkdir -p "$WG_DIR" "$WG_CONFIG_DIR" "$WG_KEYS_DIR" "$WG_TUNNELS_DIR"
    chmod 700 "$WG_DIR" "$WG_KEYS_DIR"
    chmod 755 "$WG_CONFIG_DIR" "$WG_TUNNELS_DIR"
}

# 获取下一个可用的接口名称
get_next_interface() {
    local base_name="wg"
    for i in {0..99}; do
        local interface="${base_name}${i}"
        if [[ ! -f "${WG_DIR}/${interface}.conf" ]] && ! ip link show "$interface" &>/dev/null; then
            echo "$interface"
            return
        fi
    done
    ERROR "无可用接口名称"
    exit 1
}

# 获取下一个可用的端口
get_next_port() {
    local start_port=51820
    for ((port=start_port; port<=65535; port++)); do
        # 检查端口是否被占用（优先使用ss，fallback到netstat）
        local port_in_use=false
        if command -v ss >/dev/null 2>&1; then
            if ss -ulpn 2>/dev/null | grep -q ":${port} "; then
                port_in_use=true
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -ulpn 2>/dev/null | grep -q ":${port} "; then
                port_in_use=true
            fi
        fi

        if [[ "$port_in_use" == false ]]; then
            # 检查是否已被其他隧道使用
            local used=false
            for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
                [[ -f "$tunnel_info" ]] || continue
                if grep -q "^WG_PORT=${port}$" "$tunnel_info"; then
                    used=true
                    break
                fi
            done
            if [[ "$used" == false ]]; then
                echo "$port"
                return
            fi
        fi
    done
    ERROR "无可用端口"
    exit 1
}

# 获取下一个可用的网段
get_next_network() {
    local base_networks=("10.3.3.0/24" "10.3.4.0/24" "10.3.5.0/24" "10.3.6.0/24" "10.3.7.0/24" "10.3.8.0/24" "10.3.9.0/24" "10.3.10.0/24")

    for network in "${base_networks[@]}"; do
        local used=false
        for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
            [[ -f "$tunnel_info" ]] || continue
            if grep -q "^WG_NETWORK=\"${network}\"$" "$tunnel_info"; then
                used=true
                break
            fi
        done
        if [[ "$used" == false ]]; then
            echo "$network"
            return
        fi
    done

    # 如果预定义网段都被使用，生成随机网段
    for i in {11..254}; do
        local network="10.3.${i}.0/24"
        local used=false
        for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
            [[ -f "$tunnel_info" ]] || continue
            if grep -q "^WG_NETWORK=\"${network}\"$" "$tunnel_info"; then
                used=true
                break
            fi
        done
        if [[ "$used" == false ]]; then
            echo "$network"
            return
        fi
    done

    ERROR "无可用网段"
    exit 1
}

# 生成密钥对
generate_keys() {
    local name=$1
    local tunnel_name=${2:-"default"}  # 支持隧道特定的密钥
    local private_key="${WG_KEYS_DIR}/${tunnel_name}_${name}_private.key"
    local public_key="${WG_KEYS_DIR}/${tunnel_name}_${name}_public.key"

    if [[ ! -f "$private_key" ]]; then
        if ! wg genkey > "$private_key"; then
            ERROR "生成私钥失败"
            return 1
        fi
        chmod 600 "$private_key"
        if ! wg pubkey < "$private_key" > "$public_key"; then
            ERROR "生成公钥失败"
            rm -f "$private_key"
            return 1
        fi
        chmod 644 "$public_key"
        INFO "生成密钥对: ${tunnel_name}_${name}"
    else
        INFO "密钥对已存在: ${tunnel_name}_${name}"
    fi
}

# 列出现有隧道
list_tunnels() {
    echo -e "\n${Blue}=== 现有WireGuard隧道 ===${Font}"
    local tunnels=()
    local count=0

    for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
        [[ -f "$tunnel_info" ]] || continue
        local tunnel_name=$(basename "$tunnel_info" .conf)
        source "$tunnel_info"

        count=$((count + 1))
        tunnels+=("$tunnel_name")

        local status_text="未运行"
        local color="${Red}"
        if wg show "$WG_INTERFACE" &>/dev/null; then
            status_text="运行中"
            color="${Green}"
        fi
        # 使用 -e 让颜色转义生效
        echo -e "$count. 隧道名称: $tunnel_name"
        echo -e "   接口: $WG_INTERFACE"
        echo -e "   端口: $WG_PORT"
        echo -e "   网段: $WG_NETWORK"
        echo -e "   状态: ${color}${status_text}${Font}"
        echo
    done

    if [[ $count -eq 0 ]]; then
        echo "暂无WireGuard隧道"
        return 1
    fi

    return 0
}

# 选择隧道
select_tunnel() {
    local prompt_msg=${1:-"请选择要操作的隧道"}

    if ! list_tunnels; then
        return 1
    fi

    local tunnels=()
    for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
        [[ -f "$tunnel_info" ]] || continue
        tunnels+=($(basename "$tunnel_info" .conf))
    done

    echo "$prompt_msg:"
    read -p "请输入隧道编号 [1-${#tunnels[@]}]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#tunnels[@]} ]]; then
        ERROR "无效选择"
        return 1
    fi

    local selected_tunnel="${tunnels[$((choice-1))]}"
    load_tunnel_config "$selected_tunnel"
    return 0
}

# 加载隧道配置
load_tunnel_config() {
    local tunnel_name=$1
    local tunnel_info="${WG_TUNNELS_DIR}/${tunnel_name}.conf"

    if [[ ! -f "$tunnel_info" ]]; then
        ERROR "隧道配置不存在: $tunnel_name"
        return 1
    fi

    source "$tunnel_info"
    CURRENT_TUNNEL="$tunnel_name"

    # 重新设置目录变量（因为隧道配置文件中没有保存这些变量）
    WG_DIR="/etc/wireguard"
    WG_CONFIG_DIR="${WG_DIR}/configs"
    WG_KEYS_DIR="${WG_DIR}/keys"
    WG_TUNNELS_DIR="${WG_DIR}/tunnels"

    INFO "已加载隧道配置: $tunnel_name ($WG_INTERFACE)"
    return 0
}

# 保存隧道配置信息
save_tunnel_info() {
    local tunnel_name=$1
    local tunnel_info="${WG_TUNNELS_DIR}/${tunnel_name}.conf"

    cat > "$tunnel_info" << EOF
# WireGuard隧道配置信息
TUNNEL_NAME="$tunnel_name"
WG_INTERFACE="$WG_INTERFACE"
WG_PORT="$WG_PORT"
WG_NETWORK="$WG_NETWORK"
WG_SERVER_IP="$WG_SERVER_IP"
PUBLIC_IP="$PUBLIC_IP"
NETWORK_INTERFACE="$NETWORK_INTERFACE"
SERVER_PUBLIC_KEY="$(cat "${WG_KEYS_DIR}/${tunnel_name}_server_public.key" 2>/dev/null || echo "")"
CREATED_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

    INFO "隧道信息已保存: $tunnel_name"
}

# 设置新隧道
setup_new_tunnel() {
    echo -e "\n${Blue}=== 创建新的WireGuard隧道 ===${Font}"

    # 获取隧道名称
    while true; do
        read -p "请输入新隧道名称 (如: home, office, vpn1): " tunnel_name
        if [[ -z "$tunnel_name" ]]; then
            ERROR "隧道名称不能为空"
            continue
        fi

        # 检查名称是否已存在
        if [[ -f "${WG_TUNNELS_DIR}/${tunnel_name}.conf" ]]; then
            ERROR "隧道名称已存在: $tunnel_name"
            continue
        fi

        # 检查名称格式
        if [[ ! "$tunnel_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            ERROR "隧道名称只能包含字母、数字、下划线和连字符"
            continue
        fi

        break
    done

    # 自动分配接口、端口和网段
    WG_INTERFACE=$(get_next_interface)
    WG_PORT=$(get_next_port)
    WG_NETWORK=$(get_next_network)
    WG_SERVER_IP=$(echo $WG_NETWORK | sed 's/0\/24/1/')
    CURRENT_TUNNEL="$tunnel_name"

    INFO "新隧道配置:"
    INFO "隧道名称: $tunnel_name"
    INFO "接口名称: $WG_INTERFACE"
    INFO "监听端口: $WG_PORT"
    INFO "VPN网段: $WG_NETWORK"
    INFO "服务端IP: $WG_SERVER_IP"

    # 询问是否自定义配置
    echo
    read -p "是否自定义配置? (y/N): " customize
    if [[ "$customize" =~ ^[Yy]$ ]]; then
        customize_tunnel_config
    fi

    # 继续配置流程
    configure_tunnel_server "$tunnel_name"
}

# 自定义隧道配置
customize_tunnel_config() {
    echo -e "\n${Blue}=== 自定义隧道配置 ===${Font}"

    # 自定义配置目录
    echo -e "\n${Yellow}配置目录设置${Font}"
    if [[ -L "/etc/wireguard" ]]; then
        local real_dir=$(readlink "/etc/wireguard")
        echo "当前配置目录: /etc/wireguard -> $real_dir (软链接)"
    else
        echo "当前配置目录: /etc/wireguard (真实目录)"
    fi

    read -p "是否更改配置目录? (y/N): " change_dir
    if [[ "$change_dir" =~ ^[Yy]$ ]]; then
        configure_install_path
    fi

    # 自定义端口
    echo -e "\n${Yellow}网络配置${Font}"
    read -p "设置监听端口 [当前: $WG_PORT]: " custom_port
    if [[ -n "$custom_port" ]]; then
        if [[ "$custom_port" =~ ^[0-9]+$ ]] && [[ $custom_port -ge 1024 ]] && [[ $custom_port -le 65535 ]]; then
            WG_PORT="$custom_port"
        else
            WARN "无效端口，使用默认值: $WG_PORT"
        fi
    fi

    # 自定义网段
    read -p "设置VPN网段 [当前: $WG_NETWORK]: " custom_network
    if [[ -n "$custom_network" ]]; then
        if [[ "$custom_network" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            WG_NETWORK="$custom_network"
            WG_SERVER_IP=$(echo $WG_NETWORK | sed 's/0\/24/1/')
        else
            WARN "无效网段格式，使用默认值: $WG_NETWORK"
        fi
    fi

    INFO "更新后的配置:"
    if [[ -L "/etc/wireguard" ]]; then
        local real_dir=$(readlink "/etc/wireguard")
        INFO "配置目录: /etc/wireguard -> $real_dir"
    else
        INFO "配置目录: /etc/wireguard"
    fi
    INFO "监听端口: $WG_PORT"
    INFO "VPN网段: $WG_NETWORK"
    INFO "服务端IP: $WG_SERVER_IP"
}

# 重置隧道
reset_tunnel() {
    local tunnel_name=$1

    INFO "重置隧道: $tunnel_name"

    # 停止隧道服务
    if wg show "$WG_INTERFACE" &>/dev/null; then
        INFO "停止隧道服务: $WG_INTERFACE"
        wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
    fi

    # 删除相关配置文件
    rm -f "${WG_DIR}/${WG_INTERFACE}.conf"
    rm -f "${WG_CONFIG_DIR}/${tunnel_name}_"*.conf
    rm -f "${WG_KEYS_DIR}/${tunnel_name}_"*.key

    INFO "隧道 $tunnel_name 已重置，开始重新配置..."

    # 重新分配接口、端口和网段（就像创建新隧道一样）
    WG_INTERFACE=$(get_next_interface)
    WG_PORT=$(get_next_port)
    WG_NETWORK=$(get_next_network)
    WG_SERVER_IP=$(echo $WG_NETWORK | sed 's/0\/24/1/')
    CURRENT_TUNNEL="$tunnel_name"

    INFO "重置后的隧道配置:"
    INFO "隧道名称: $tunnel_name"
    INFO "接口名称: $WG_INTERFACE"
    INFO "监听端口: $WG_PORT"
    INFO "VPN网段: $WG_NETWORK"
    INFO "服务端IP: $WG_SERVER_IP"

    # 询问是否自定义配置
    echo
    read -p "是否自定义配置? (y/N): " customize
    if [[ "$customize" =~ ^[Yy]$ ]]; then
        customize_tunnel_config
    fi

    # 重新配置隧道
    configure_tunnel_server "$tunnel_name"
}

# 配置服务端
setup_server() {
    INFO "配置WireGuard服务端..."

    # 检查是否存在现有隧道
    local existing_tunnels=()
    for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
        [[ -f "$tunnel_info" ]] || continue
        existing_tunnels+=($(basename "$tunnel_info" .conf))
    done

    if [[ ${#existing_tunnels[@]} -gt 0 ]]; then
        echo -e "\n${Yellow}检测到现有WireGuard隧道：${Font}"
        list_tunnels

        echo -e "${Yellow}请选择操作：${Font}"
        echo "1. 创建新的隧道"
        echo "2. 重置现有隧道配置"
        echo "3. 取消操作"
        read -p "请选择 [1-3]: " action_choice

        case "$action_choice" in
            1)
                INFO "创建新的隧道"
                setup_new_tunnel
                return
                ;;
            2)
                echo -e "\n${Red}警告：重置隧道将删除所有现有客户端配置！${Font}"
                if ! select_tunnel "请选择要重置的隧道"; then
                    return 1
                fi
                read -p "确认重置隧道 $CURRENT_TUNNEL? (y/N): " confirm_reset
                if [[ ! "$confirm_reset" =~ ^[Yy]$ ]]; then
                    INFO "操作已取消"
                    return 1
                fi
                INFO "重置隧道: $CURRENT_TUNNEL"
                reset_tunnel "$CURRENT_TUNNEL"
                return  # 重置完成后直接返回，避免重复调用
                ;;
            3)
                INFO "操作已取消"
                return 1
                ;;
            *)
                ERROR "无效选择"
                return 1
                ;;
        esac
    else
        INFO "未检测到现有隧道，创建第一个隧道"
        setup_new_tunnel
        return
    fi
}

# 配置隧道服务端
configure_tunnel_server() {
    local tunnel_name=$1

    INFO "配置隧道服务端: $tunnel_name"

    # 配置公网IP
    configure_public_ip


    # 确保依赖命令
    ensure_net_tools

    # 获取配置参数
    local public_ip="$PUBLIC_IP"
    local network_interface
    network_interface=$(get_network_interface)
    if [[ $? -ne 0 ]] || [[ -z "$network_interface" ]]; then
        ERROR "无法获取网络接口，请手动指定"
        read -p "请输入网络接口名称 (如: eth0, ens33): " network_interface
        if [[ -z "$network_interface" ]]; then
            ERROR "网络接口不能为空"
            return 1
        fi
    fi

    # 如果是新隧道，允许用户自定义网络接口
    if [[ -z "$CURRENT_TUNNEL" ]] || [[ "$CURRENT_TUNNEL" != "$tunnel_name" ]]; then
        echo -e "\n${Blue}=== 服务端网络配置 ===${Font}"
        read -p "设置网络接口 [默认: $network_interface]: " custom_interface
        network_interface=${custom_interface:-$network_interface}
        NETWORK_INTERFACE="$network_interface"
    fi

    # 创建目录结构
    create_directories

    # 生成服务端密钥（使用隧道特定的密钥）
    generate_keys "server" "$tunnel_name"

    local server_private=$(cat "${WG_KEYS_DIR}/${tunnel_name}_server_private.key")

    # 根据IP版本配置防火墙规则
    local postup_rules
    local postdown_rules

    # 检查当前使用的IP版本
    if [[ "$PUBLIC_IP" =~ : ]]; then
        # IPv6环境
        INFO "配置IPv6防火墙规则"

        # 检查IPv6 NAT支持
        if ! modinfo ip6table_nat &>/dev/null && ! lsmod | grep -q ip6table_nat; then
            WARN "系统可能不支持IPv6 NAT，某些功能可能受限"
            echo "如果客户端无法访问互联网，请考虑："
            echo "1. 使用IPv6路由而不是NAT"
            echo "2. 配置IPv6防火墙规则"
            echo "3. 或切换到IPv4环境"
        fi

        # IPv6通常使用路由而不是NAT，但这里仍提供NAT选项
        echo "IPv6配置选项："
        echo "1. 使用NAT (MASQUERADE) - 通过NAT转换处理流量转发"
        echo "2. 使用路由转发 - 通过路由表处理流量转发，IPv6推荐方式"
        read -p "请选择 [1-2, 默认: 1]: " ipv6_mode

        if [[ "$ipv6_mode" == "2" ]]; then
            # 仅转发，不使用NAT
            postup_rules="ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT"
            postdown_rules="ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT"
            INFO "使用IPv6路由转发模式"
        else
            # 使用NAT
            postup_rules="ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $network_interface -j MASQUERADE"
            postdown_rules="ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $network_interface -j MASQUERADE"
            INFO "使用IPv6 NAT模式"
        fi
    else
        # IPv4环境
        INFO "配置IPv4防火墙规则"
        postup_rules="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $network_interface -j MASQUERADE"
        postdown_rules="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $network_interface -j MASQUERADE"
    fi

    # 创建服务端配置文件
    if ! cat > "${WG_DIR}/${WG_INTERFACE}.conf" << EOF
[Interface]
PrivateKey = $server_private
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PostUp = $postup_rules
PostDown = $postdown_rules

# 客户端配置将自动添加到此处
EOF
    then
        ERROR "创建服务端配置文件失败"
        return 1
    fi

    # 保存隧道信息
    save_tunnel_info "$tunnel_name"

    # 保存服务端信息（兼容旧版本）
    cat > "${WG_DIR}/server_info.conf" << EOF
PUBLIC_IP=$public_ip
WG_PORT=$WG_PORT
WG_NETWORK=$WG_NETWORK
WG_SERVER_IP=$WG_SERVER_IP
NETWORK_INTERFACE=$network_interface
SERVER_PUBLIC_KEY=$(cat "${WG_KEYS_DIR}/${tunnel_name}_server_public.key")
TUNNEL_NAME=$tunnel_name
EOF

    # 启用IP转发
    if [[ "$PUBLIC_IP" =~ : ]]; then
        # IPv6环境
        INFO "启用IPv6转发"
        # 检查当前运行时的值
        if [[ "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" != "1" ]]; then
            # 删除所有相关的旧配置行（包括注释的）
            sed -i '/net\.ipv6\.conf\.all\.forwarding/d' /etc/sysctl.conf
            # 添加新配置
            echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
            # 立即生效
            sysctl -w net.ipv6.conf.all.forwarding=1
        else
            INFO "IPv6转发已启用"
        fi
    else
        # IPv4环境
        INFO "启用IPv4转发"
        # 检查当前运行时的值
        if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]]; then
            # 删除所有相关的旧配置行（包括注释的）
            sed -i '/net\.ipv4\.ip_forward/d' /etc/sysctl.conf
            # 添加新配置
            echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
            # 立即生效
            sysctl -w net.ipv4.ip_forward=1
        else
            INFO "IPv4转发已启用"
        fi
    fi

    INFO "隧道服务端配置完成: $tunnel_name"
    INFO "接口名称: $WG_INTERFACE"
    INFO "服务端公钥: $(cat "${WG_KEYS_DIR}/${tunnel_name}_server_public.key")"
    INFO "服务端地址: ${public_ip}:${WG_PORT}"
    INFO "VPN网段: $WG_NETWORK"

    # 设置当前隧道
    CURRENT_TUNNEL="$tunnel_name"
}

# 删除隧道
delete_tunnel() {
    if ! select_tunnel "请选择要删除的隧道"; then
        return 1
    fi

    local tunnel_name="$CURRENT_TUNNEL"

    echo -e "\n${Red}警告: 此操作将完全删除隧道 $tunnel_name 及其所有配置文件${Font}"
    echo "包括："
    echo "- 隧道配置文件"
    echo "- 所有客户端配置"
    echo "- 密钥文件"
    echo "- 隧道信息"
    echo
    read -p "确认删除隧道 $tunnel_name? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        INFO "操作已取消"
        return 1
    fi

    # 停止隧道服务
    if wg show "$WG_INTERFACE" &>/dev/null; then
        INFO "停止隧道服务: $WG_INTERFACE"
        case $SERVICE_MANAGER in
            "systemd")
                # 停止和清理自定义systemd服务
                local service_name="wireguard-${WG_INTERFACE}"
                systemctl stop "${service_name}.service" 2>/dev/null || true
                systemctl disable "${service_name}.service" 2>/dev/null || true
                rm -f "/etc/systemd/system/${service_name}.service"

                # 清理可能存在的旧配置
                systemctl stop wg-quick@${WG_INTERFACE} 2>/dev/null || true
                systemctl disable wg-quick@${WG_INTERFACE} 2>/dev/null || true
                rm -rf "/etc/systemd/system/wg-quick@${WG_INTERFACE}.service.d" 2>/dev/null || true

                systemctl daemon-reload
                INFO "已清理systemd服务配置"
                ;;
            *)
                wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                ;;
        esac
    fi

    # 删除配置文件
    rm -f "${WG_DIR}/${WG_INTERFACE}.conf"
    rm -f "${WG_TUNNELS_DIR}/${tunnel_name}.conf"

    # 删除客户端配置
    rm -f "${WG_CONFIG_DIR}/${tunnel_name}_"*.conf

    # 删除密钥文件
    rm -f "${WG_KEYS_DIR}/${tunnel_name}_"*.key

    # 移除防火墙规则
    remove_firewall_rules

    INFO "隧道 $tunnel_name 已完全删除"
    CURRENT_TUNNEL=""
}

# 移除防火墙规则
remove_firewall_rules() {
    if [[ "$FIREWALL_TYPE" == "none" ]]; then
        return 0
    fi

    INFO "移除防火墙规则..."

    case "$FIREWALL_TYPE" in
        "ufw")
            ufw delete allow ${WG_PORT}/udp 2>/dev/null || true
            ufw route delete allow in on ${WG_INTERFACE} 2>/dev/null || true
            ufw route delete allow out on ${WG_INTERFACE} 2>/dev/null || true
            ufw reload
            ;;
        "firewalld")
            firewall-cmd --permanent --remove-port=${WG_PORT}/udp 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --remove-interface=${WG_INTERFACE} 2>/dev/null || true
            firewall-cmd --reload
            ;;
        "iptables")
            iptables -D INPUT -p udp --dport ${WG_PORT} -j ACCEPT 2>/dev/null || true
            ;;
    esac
}

# 显示隧道详细信息
show_tunnel_details() {
    if ! select_tunnel "请选择要查看的隧道"; then
        return 1
    fi

    local tunnel_name="$CURRENT_TUNNEL"

    echo -e "\n${Blue}=== 隧道详细信息: $tunnel_name ===${Font}"
    echo "接口名称: $WG_INTERFACE"
    echo "监听端口: $WG_PORT"
    echo "VPN网段: $WG_NETWORK"
    echo "服务端IP: $WG_SERVER_IP"
    echo "公网地址: $PUBLIC_IP"

    # 显示运行状态
    if wg show "$WG_INTERFACE" &>/dev/null; then
        echo -e "运行状态: ${Green}运行中${Font}"
        echo -e "\n${Blue}=== 接口详情 ===${Font}"
        wg show "$WG_INTERFACE"
    else
        echo -e "运行状态: ${Red}未运行${Font}"
    fi

    # 显示客户端列表
    echo -e "\n${Blue}=== 客户端列表 ===${Font}"
    local client_configs=$(ls "${WG_CONFIG_DIR}/${tunnel_name}_"*.conf 2>/dev/null)
    if [[ -n "$client_configs" ]]; then
        for config in $client_configs; do
            local client_name=$(basename "$config" .conf | sed "s/^${tunnel_name}_//")
            local client_ip=$(grep "Address" "$config" | awk '{print $3}' | cut -d'/' -f1)
            echo "- $client_name ($client_ip)"
        done
    else
        echo "暂无客户端配置"
    fi
}

# 生成客户端配置
generate_client_config() {
    # 选择隧道（select_tunnel内部会调用list_tunnels）
    if ! select_tunnel "请选择要添加客户端的隧道"; then
        ERROR "未找到可用隧道，请先创建WireGuard服务端"
        return 1
    fi

    local tunnel_name="$CURRENT_TUNNEL"
    INFO "为隧道 $tunnel_name 生成客户端配置"

    echo -e "\n${Blue}=== 生成客户端配置 ===${Font}"
    read -p "请输入客户端名称 (如: laptop, phone, tablet): " client_name

    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi

    # 检查客户端名称格式
    if [[ ! "$client_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        ERROR "客户端名称只能包含字母、数字、下划线和连字符"
        return 1
    fi

    # 检查是否已存在（使用隧道特定的命名）
    local client_config_file="${WG_CONFIG_DIR}/${tunnel_name}_${client_name}.conf"
    if [[ -f "$client_config_file" ]]; then
        read -p "客户端 $client_name 在隧道 $tunnel_name 中已存在，是否覆盖? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # 生成客户端密钥（使用隧道特定的密钥）
    generate_keys "$client_name" "$tunnel_name"

    # 分配IP地址
    local client_ip=$(get_next_client_ip "$tunnel_name")

    # 询问路由配置
    echo "路由配置选项:"
    echo "1. 全部流量通过VPN (AllowedIPs = 0.0.0.0/0)"
    echo "2. 仅VPN网段流量 (AllowedIPs = $WG_NETWORK)"
    read -p "请选择 [1-2, 默认: 2]: " route_choice

    local allowed_ips="$WG_NETWORK"
    if [[ "$route_choice" == "1" ]]; then
        allowed_ips="0.0.0.0/0"
    fi

    # 询问是否允许客户端访问服务端节点的宿主机局域网
    echo -e "\n${Blue}=== 服务端局域网访问配置 ===${Font}"
    local server_lan_network=$(get_server_lan_network)
    if [[ -n "$server_lan_network" ]]; then
        echo -e "检测到服务端节点的宿主机局域网段: ${Yellow}$server_lan_network${Font}"
        echo "是否允许此客户端访问服务端节点的宿主机局域网？"
        echo -e "${Yellow}启用后，客户端可以访问服务端局域网内的其他设备（如路由器、NAS、打印机等）${Font}"
        read -p "是否允许访问服务端局域网? (y/N): " allow_server_lan_access

        if [[ "$allow_server_lan_access" =~ ^[Yy]$ ]]; then
            # 将服务端局域网段添加到AllowedIPs
            if [[ "$allowed_ips" == "0.0.0.0/0" ]]; then
                # 如果已经是全部流量，无需额外添加
                INFO "已选择全部流量通过VPN，自动包含服务端局域网访问"
            else
                # 添加服务端局域网段到AllowedIPs
                allowed_ips="$allowed_ips,$server_lan_network"
                INFO "已添加服务端局域网段到客户端路由: $server_lan_network"
            fi
        else
            INFO "客户端将无法访问服务端局域网，仅可访问VPN网段"
        fi
    else
        WARN "无法检测到服务端局域网段，跳过局域网访问配置"
    fi

    # 询问是否允许其他节点访问当前节点的宿主机局域网
    echo -e "\n${Blue}=== 局域网访问配置 ===${Font}"
    echo "是否允许其他VPN节点访问当前节点所属的宿主机局域网？"
    echo -e "${Yellow}建议在24小时开机的Linux设备（如路由器/NAS）上启用${Font}"
    echo "启用后，其他VPN客户端可以通过此节点访问其宿主机的局域网设备"
    read -p "是否启用局域网访问? (y/N): " enable_lan_access

    local client_lan_network=""
    if [[ "$enable_lan_access" =~ ^[Yy]$ ]]; then
        # 使用之前已获取的服务端局域网段用于冲突检查
        # local server_lan_network=$(get_server_lan_network)  # 已在上面获取过

        echo -e "\n请输入当前节点宿主机的局域网段："
        echo "格式示例: 192.168.1.0/24, 192.168.3.0/24, 10.0.0.0/24"
        if [[ -n "$server_lan_network" ]]; then
            echo -e "${Yellow}注意: 服务端局域网段为 $server_lan_network，请勿填写相同网段${Font}"
        fi

        while true; do
            read -p "局域网段 (输入 'n' 跳过): " client_lan_network

            # 检查是否要跳过配置
            if [[ "$client_lan_network" =~ ^[Nn]$ ]] || [[ -z "$client_lan_network" ]]; then
                INFO "跳过局域网访问配置"
                client_lan_network=""
                break
            fi

            # 验证网段格式
            if [[ ! "$client_lan_network" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                WARN "无效的网段格式，请重新输入"
                continue
            fi

            # 检查是否与服务端局域网段冲突
            if [[ -n "$server_lan_network" ]] && [[ "$client_lan_network" == "$server_lan_network" ]]; then
                ERROR "所填网段 $client_lan_network 属于服务端局域网！"
                ERROR "如果客户端节点与服务端节点处于同一个局域网，无须填写此配置"
                WARN "请填写不同的网段，或输入 'n' 跳过局域网访问配置"
                continue
            fi

            INFO "将允许其他VPN节点访问局域网段: $client_lan_network"
            break
        done
    fi

    # 询问DNS配置
    read -p "DNS服务器 [默认: 8.8.8.8,1.1.1.1]: " custom_dns
    local dns_servers=${custom_dns:-"8.8.8.8,1.1.1.1"}

    local client_private=$(cat "${WG_KEYS_DIR}/${tunnel_name}_${client_name}_private.key")
    local server_public=$(cat "${WG_KEYS_DIR}/${tunnel_name}_server_public.key")

    # 生成客户端配置文件（通用格式）
    cat > "$client_config_file" << EOF
[Interface]
PrivateKey = $client_private
Address = $client_ip/32
DNS = $dns_servers

[Peer]
PublicKey = $server_public
Endpoint = $PUBLIC_IP:$WG_PORT
AllowedIPs = $allowed_ips
PersistentKeepalive = 15
EOF

    # 添加客户端到服务端配置
    local client_public=$(cat "${WG_KEYS_DIR}/${tunnel_name}_${client_name}_public.key")

    # 设置服务端的AllowedIPs
    local server_allowed_ips="$client_ip/32"
    if [[ -n "$client_lan_network" ]]; then
        server_allowed_ips="$client_ip/32,$client_lan_network"
        INFO "服务端将允许访问客户端局域网: $client_lan_network"
    fi

    cat >> "${WG_DIR}/${WG_INTERFACE}.conf" << EOF

# Client: ${tunnel_name}_${client_name}
[Peer]
PublicKey = $client_public
AllowedIPs = $server_allowed_ips
EOF

    INFO "客户端配置生成完成: $client_config_file"
    INFO "客户端IP地址: $client_ip"

    # 显示配置文件内容
    echo -e "\n${Blue}=== 客户端配置文件内容 ===${Font}"
    cat "$client_config_file"

    # 显示二维码
    show_qrcode "$client_config_file" "${tunnel_name}_${client_name}"

    # 重启WireGuard服务以应用新配置
    if wg show "$WG_INTERFACE" &>/dev/null; then
        INFO "重启WireGuard接口以应用新客户端配置..."
        case $SERVICE_MANAGER in
            "systemd")
                if [[ "$WG_DIR" == "/etc/wireguard" ]]; then
                    # 使用默认路径，可以使用systemd服务
                    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
                        systemctl restart wg-quick@${WG_INTERFACE}
                        INFO "WireGuard systemd服务已重启"
                    else
                        WARN "systemd服务未运行，尝试手动重启接口"
                        wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                        wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                        INFO "WireGuard接口已重启"
                    fi
                else
                    # 使用自定义路径，手动重启
                    wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                    wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                    INFO "WireGuard接口已重启"
                fi
                ;;
            *)
                # 其他服务管理器或手动管理
                wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                INFO "WireGuard接口已重启"
                ;;
        esac
    else
        INFO "WireGuard接口未运行，新客户端配置将在下次启动时生效"
    fi
}

# 获取下一个可用的客户端IP
get_next_client_ip() {
    local tunnel_name=${1:-"default"}
    local base_ip=$(echo $WG_SERVER_IP | cut -d'.' -f1-3)
    local used_ips=$(grep -h "AllowedIPs.*32" "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null | grep -o "${base_ip}\.[0-9]*" | sort -V)

    for i in {2..254}; do
        local test_ip="${base_ip}.${i}"
        if [[ "$test_ip" != "$WG_SERVER_IP" ]] && ! echo "$used_ips" | grep -q "^${test_ip}$"; then
            echo "$test_ip"
            return
        fi
    done

    ERROR "无可用IP地址"
    exit 1
}

# 检测操作系统类型（用于开机自启动）
detect_startup_method() {
    if [ -f /etc/synoinfo.conf ]; then
        STARTUP_METHOD="synology"
    elif [ -f /etc/unraid-version ]; then
        STARTUP_METHOD="unraid"
    elif [ -f /etc/rc.local ] && grep -q "exit 0" /etc/rc.local; then
        STARTUP_METHOD="rc_local"
    elif command -v crontab >/dev/null 2>&1; then
        STARTUP_METHOD="crontab"
    else
        STARTUP_METHOD="manual"
    fi
    INFO "开机自启动方式: $STARTUP_METHOD"
}

# 配置开机自启动
setup_autostart() {
    local wg_command="wg-quick up \"${WG_DIR}/${WG_INTERFACE}.conf\""

    case $STARTUP_METHOD in
        "synology")
            if ! grep -qF -- "$wg_command" /etc/rc.local; then
                cp -f /etc/rc.local /etc/rc.local.bak 2>/dev/null
                sed -i '/wg-quick/d' /etc/rc.local
                if grep -q 'exit 0' /etc/rc.local; then
                    sed -i "/exit 0/i\\$wg_command" /etc/rc.local
                else
                    echo "$wg_command" >> /etc/rc.local
                fi
                INFO "已配置群晖开机自启动"
            fi
            ;;
        "unraid")
            if ! grep -qF -- "$wg_command" /boot/config/go; then
                echo "$wg_command" >> /boot/config/go
                INFO "已配置Unraid开机自启动"
            fi
            ;;
        "rc_local")
            if ! grep -qF -- "$wg_command" /etc/rc.local; then
                cp -f /etc/rc.local /etc/rc.local.bak 2>/dev/null
                sed -i '/wg-quick/d' /etc/rc.local
                if grep -q 'exit 0' /etc/rc.local; then
                    sed -i "/exit 0/i\\$wg_command" /etc/rc.local
                else
                    echo "$wg_command" >> /etc/rc.local
                fi
                chmod +x /etc/rc.local
                INFO "已配置rc.local开机自启动"
            fi
            ;;
        "crontab")
            local cron_command="@reboot $wg_command"
            crontab -l 2>/dev/null | grep -v "wg-quick" > /tmp/cronjob.tmp
            echo "$cron_command" >> /tmp/cronjob.tmp
            crontab /tmp/cronjob.tmp
            rm -f /tmp/cronjob.tmp
            INFO "已配置crontab开机自启动"
            ;;
        "manual")
            WARN "无法自动配置开机自启动，请手动添加以下命令到系统启动脚本："
            echo -e "${Yellow}$wg_command${Font}"
            ;;
    esac
}

# 移除开机自启动
remove_autostart() {
    local wg_command="wg-quick up \"${WG_DIR}/${WG_INTERFACE}.conf\""

    case $STARTUP_METHOD in
        "synology")
            if [ -f /etc/rc.local ]; then
                sed -i '/wg-quick/d' /etc/rc.local
                INFO "已移除群晖开机自启动"
            fi
            ;;
        "unraid")
            if [ -f /boot/config/go ]; then
                sed -i '/wg-quick/d' /boot/config/go
                INFO "已移除Unraid开机自启动"
            fi
            ;;
        "rc_local")
            if [ -f /etc/rc.local ]; then
                sed -i '/wg-quick/d' /etc/rc.local
                INFO "已移除rc.local开机自启动"
            fi
            ;;
        "crontab")
            crontab -l 2>/dev/null | grep -v "wg-quick" > /tmp/cronjob.tmp
            crontab /tmp/cronjob.tmp
            rm -f /tmp/cronjob.tmp
            INFO "已移除crontab开机自启动"
            ;;
        "manual")
            WARN "请手动从系统启动脚本中移除WireGuard启动命令"
            ;;
    esac
}

# 启动WireGuard服务
start_wireguard() {
    if [[ -z "$CURRENT_TUNNEL" ]]; then
        ERROR "未选择隧道，请先选择要启动的隧道"
        return 1
    fi

    INFO "启动WireGuard隧道: $CURRENT_TUNNEL ($WG_INTERFACE)..."

    case $SERVICE_MANAGER in
        "systemd")
            # 使用自定义systemd服务，避免挂载时序问题
            INFO "使用systemd自定义服务管理WireGuard"

            # 清理可能存在的旧配置
            systemctl stop wg-quick@${WG_INTERFACE} 2>/dev/null || true
            systemctl disable wg-quick@${WG_INTERFACE} 2>/dev/null || true
            rm -rf "/etc/systemd/system/wg-quick@${WG_INTERFACE}.service.d" 2>/dev/null || true

            # 创建自定义systemd服务
            local service_name="wireguard-${WG_INTERFACE}"
            cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=WireGuard Auto Start for ${WG_INTERFACE}
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/wg-quick up ${WG_DIR}/${WG_INTERFACE}.conf
ExecStop=/usr/bin/wg-quick down ${WG_DIR}/${WG_INTERFACE}.conf

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable "${service_name}.service"
            systemctl start "${service_name}.service"

            # 检查自定义服务状态和接口状态
            sleep 2  # 等待服务启动
            if systemctl is-active --quiet "${service_name}.service" && wg show ${WG_INTERFACE} &>/dev/null; then
                INFO "WireGuard服务启动成功"
                wg show
            else
                ERROR "WireGuard服务启动失败"
                systemctl status "${service_name}.service"
                return 1
            fi
            ;;
        "openrc")
            rc-update add wg-quick.${WG_INTERFACE} default
            rc-service wg-quick.${WG_INTERFACE} start
            if wg show ${WG_INTERFACE} &> /dev/null; then
                INFO "WireGuard服务启动成功"
                wg show
            else
                ERROR "WireGuard服务启动失败"
                return 1
            fi
            ;;
        *)
            # 手动启动接口
            wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
            if wg show ${WG_INTERFACE} &> /dev/null; then
                INFO "WireGuard接口启动成功"
                wg show
                # 配置开机自启动
                setup_autostart
            else
                ERROR "WireGuard接口启动失败"
                return 1
            fi
            ;;
    esac
}

# 停止WireGuard服务
stop_wireguard() {
    if [[ -z "$CURRENT_TUNNEL" ]]; then
        ERROR "未选择隧道，请先选择要停止的隧道"
        return 1
    fi

    INFO "停止WireGuard隧道: $CURRENT_TUNNEL ($WG_INTERFACE)..."

    case $SERVICE_MANAGER in
        "systemd")
            # 停止和清理自定义systemd服务
            local service_name="wireguard-${WG_INTERFACE}"
            systemctl stop "${service_name}.service" 2>/dev/null || true
            systemctl disable "${service_name}.service" 2>/dev/null || true
            rm -f "/etc/systemd/system/${service_name}.service"

            # 清理可能存在的旧配置
            systemctl stop wg-quick@${WG_INTERFACE} 2>/dev/null || true
            systemctl disable wg-quick@${WG_INTERFACE} 2>/dev/null || true
            rm -rf "/etc/systemd/system/wg-quick@${WG_INTERFACE}.service.d" 2>/dev/null || true

            systemctl daemon-reload
            INFO "已清理systemd服务配置"
            ;;
        "openrc")
            rc-service wg-quick.${WG_INTERFACE} stop
            rc-update del wg-quick.${WG_INTERFACE} default
            ;;
        *)
            wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf"
            # 移除开机自启动
            remove_autostart
            ;;
    esac

    INFO "WireGuard隧道已停止: $CURRENT_TUNNEL"
}

# 查看服务状态
show_status() {
    echo -e "\n${Blue}=== WireGuard隧道状态总览 ===${Font}"

    # 检查是否有隧道
    local tunnel_count=0
    local running_count=0

    for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
        [[ -f "$tunnel_info" ]] || continue
        tunnel_count=$((tunnel_count + 1))

        source "$tunnel_info"

        echo -e "\n${Blue}=== 隧道: $TUNNEL_NAME ===${Font}"
        echo "接口: $WG_INTERFACE"
        echo "端口: $WG_PORT"
        echo "网段: $WG_NETWORK"
        echo "公网地址: $PUBLIC_IP:$WG_PORT"

        # 检查接口是否运行
        if wg show "$WG_INTERFACE" &>/dev/null; then
            echo -e "状态: ${Green}运行中${Font}"
            running_count=$((running_count + 1))

            echo -e "\n${Blue}=== 接口详情 ===${Font}"
            wg show "$WG_INTERFACE"

            echo -e "\n${Blue}=== 连接统计 ===${Font}"
            wg show "$WG_INTERFACE" dump
        else
            echo -e "状态: ${Red}未运行${Font}"
        fi

        # 显示客户端数量
        local client_count=$(ls "${WG_CONFIG_DIR}/${TUNNEL_NAME}_"*.conf 2>/dev/null | wc -l)
        echo "客户端数量: $client_count"
    done

    if [[ $tunnel_count -eq 0 ]]; then
        echo "暂无WireGuard隧道"
        return 1
    fi

    echo -e "\n${Blue}=== 总览 ===${Font}"
    echo "总隧道数: $tunnel_count"
    echo "运行中: $running_count"
    echo "已停止: $((tunnel_count - running_count))"

    # 检查防火墙状态
    echo -e "\n${Blue}=== 防火墙状态 ===${Font}"
    detect_firewall

    case "$FIREWALL_TYPE" in
        "ufw")
            echo "UFW规则:"
            ufw status | grep -E "(${WG_PORT}|${WG_INTERFACE})"
            ;;
        "firewalld")
            echo "firewalld规则:"
            firewall-cmd --list-ports | grep -q "${WG_PORT}/udp" && echo "端口${WG_PORT}/udp: 已开放" || echo "端口${WG_PORT}/udp: 未开放"
            firewall-cmd --zone=trusted --list-interfaces | grep -q "${WG_INTERFACE}" && echo "接口${WG_INTERFACE}: 已信任" || echo "接口${WG_INTERFACE}: 未信任"
            ;;
        "iptables")
            echo "iptables规则:"
            # 检查INPUT链的默认策略
            local input_policy=$(iptables -L INPUT -n | head -1 | grep -o "policy [A-Z]*" | awk '{print $2}')
            if [[ "$input_policy" == "ACCEPT" ]]; then
                # 默认策略是ACCEPT，检查是否有明确的DROP/REJECT规则针对该端口
                if iptables -L INPUT -n | grep -E "(DROP|REJECT)" | grep -q "${WG_PORT}"; then
                    echo "端口${WG_PORT}: 被明确阻止"
                else
                    echo "端口${WG_PORT}: 已开放 (默认策略ACCEPT)"
                fi
            else
                # 默认策略是DROP，检查是否有明确的ACCEPT规则
                if iptables -L INPUT -n | grep -q "${WG_PORT}"; then
                    echo "端口${WG_PORT}: 已开放"
                else
                    echo "端口${WG_PORT}: 未开放 (默认策略DROP)"
                fi
            fi
            iptables -L FORWARD -n -v | grep -q "${WG_INTERFACE}" && echo "转发规则: 已配置" || echo "转发规则: 未配置"
            ;;
        *)
            echo "无防火墙或未检测到"
            ;;
    esac
}

# 列出客户端配置
list_clients() {
    local tunnel_name=${1:-""}

    if [[ -n "$tunnel_name" ]]; then
        echo -e "\n${Blue}=== 隧道 $tunnel_name 的客户端配置 ===${Font}"
        local configs=$(ls "${WG_CONFIG_DIR}/${tunnel_name}_"*.conf 2>/dev/null)
        if [[ -n "$configs" ]]; then
            for config in $configs; do
                local name=$(basename "$config" .conf | sed "s/^${tunnel_name}_//")
                local ip=$(grep "Address" "$config" | awk '{print $3}' | cut -d'/' -f1)
                echo "- $name ($ip)"
            done
            return 0  # 有客户端配置
        else
            echo "暂无客户端配置"
            return 1  # 无客户端配置
        fi
    else
        echo -e "\n${Blue}=== 所有客户端配置 ===${Font}"
        if [[ -d "$WG_CONFIG_DIR" ]]; then
            local configs=$(ls "$WG_CONFIG_DIR"/*.conf 2>/dev/null)
            if [[ -n "$configs" ]]; then
                for config in $configs; do
                    local full_name=$(basename "$config" .conf)
                    local ip=$(grep "Address" "$config" | awk '{print $3}' | cut -d'/' -f1)

                    # 尝试解析隧道名称和客户端名称
                    if [[ "$full_name" =~ ^([^_]+)_(.+)$ ]]; then
                        local tunnel="${BASH_REMATCH[1]}"
                        local client="${BASH_REMATCH[2]}"
                        echo "- $client (隧道: $tunnel, IP: $ip)"
                    else
                        echo "- $full_name ($ip)"
                    fi
                done
            else
                echo "暂无客户端配置"
                return 1  # 无客户端配置
            fi
        else
            echo "配置目录不存在"
            return 1  # 目录不存在
        fi
        return 0  # 有客户端配置
    fi
}

# 删除客户端配置
delete_client() {
    # 选择隧道
    if ! select_tunnel "请选择要删除客户端的隧道"; then
        ERROR "未找到可用隧道"
        return 1
    fi

    local tunnel_name="$CURRENT_TUNNEL"

    # 显示该隧道的客户端
    if ! list_clients "$tunnel_name"; then
        INFO "该隧道暂无客户端配置，无法删除"
        return 1
    fi

    echo
    read -p "请输入要删除的客户端名称: " client_name

    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi

    local config_file="${WG_CONFIG_DIR}/${tunnel_name}_${client_name}.conf"
    if [[ ! -f "$config_file" ]]; then
        ERROR "客户端配置不存在: $client_name (隧道: $tunnel_name)"
        return 1
    fi

    read -p "确认删除客户端 $client_name (隧道: $tunnel_name)? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi

    # 删除配置文件
    rm -f "$config_file"

    # 删除密钥文件
    rm -f "${WG_KEYS_DIR}/${tunnel_name}_${client_name}_private.key"
    rm -f "${WG_KEYS_DIR}/${tunnel_name}_${client_name}_public.key"

    # 从服务端配置中删除客户端
    if [[ -f "${WG_DIR}/${WG_INTERFACE}.conf" ]]; then
        sed -i "/# Client: ${tunnel_name}_${client_name}/,/^$/d" "${WG_DIR}/${WG_INTERFACE}.conf"
    fi

    INFO "客户端 $client_name 已从隧道 $tunnel_name 中删除"

    # 重启服务以应用更改
    if wg show "$WG_INTERFACE" &>/dev/null; then
        INFO "重启WireGuard接口以应用客户端删除..."
        case $SERVICE_MANAGER in
            "systemd")
                if [[ "$WG_DIR" == "/etc/wireguard" ]]; then
                    # 使用默认路径，可以使用systemd服务
                    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
                        systemctl restart wg-quick@${WG_INTERFACE}
                        INFO "WireGuard systemd服务已重启"
                    else
                        WARN "systemd服务未运行，尝试手动重启接口"
                        wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                        wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                        INFO "WireGuard接口已重启"
                    fi
                else
                    # 使用自定义路径，手动重启
                    wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                    wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                    INFO "WireGuard接口已重启"
                fi
                ;;
            *)
                # 其他服务管理器或手动管理
                wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
                wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                INFO "WireGuard接口已重启"
                ;;
        esac
    else
        INFO "WireGuard接口未运行，客户端删除已完成"
    fi
}

# 显示客户端配置
show_client_config() {
    # 选择隧道
    if ! select_tunnel "请选择要查看客户端的隧道"; then
        ERROR "未找到可用隧道"
        return 1
    fi

    local tunnel_name="$CURRENT_TUNNEL"

    # 显示该隧道的客户端
    if ! list_clients "$tunnel_name"; then
        INFO "该隧道暂无客户端配置，请先生成客户端配置"
        return 1
    fi

    echo
    read -p "请输入要查看的客户端名称: " client_name

    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi

    local config_file="${WG_CONFIG_DIR}/${tunnel_name}_${client_name}.conf"
    if [[ ! -f "$config_file" ]]; then
        ERROR "客户端配置不存在: $client_name (隧道: $tunnel_name)"
        return 1
    fi

    echo -e "\n${Blue}=== 客户端配置: $client_name (隧道: $tunnel_name) ===${Font}"
    cat "$config_file"

    # 显示二维码
    show_qrcode "$config_file" "${tunnel_name}_${client_name}"
}

# 安装WireGuard客户端（仅作为客户端使用）
install_wireguard_client() {
    echo -e "\n${Blue}=== 安装 WireGuard 客户端 ===${Font}"

    check_root
    detect_os || return 1

    # 安装WireGuard工具
    if install_wireguard; then
        INFO "WireGuard 客户端组件安装完成"
    else
        ERROR "WireGuard 客户端安装失败"
        return 1
    fi

    # 确保必要命令依赖（非交互）
    ensure_net_tools
    ensure_resolvconf

    # 询问是否导入现有客户端配置
    echo
    read -p "是否导入现有的客户端配置文件(.conf)? (y/N): " import_now
    if [[ "$import_now" =~ ^[Yy]$ ]]; then
        import_client_config || WARN "导入配置失败，可稍后手动导入"
    else
        INFO "您可以将服务端生成客户端配置文件上传到本设备，重新运行脚本加载并启动配置！"
    fi
}

# 导入客户端配置（Linux）
import_client_config() {
    echo -e "\n${Blue}=== 导入客户端配置 ===${Font}"

    read -p "请输入本机上客户端配置文件的路径（例如 /root/wg-client.conf）: " src_path
    if [[ -z "$src_path" ]] || [[ ! -f "$src_path" ]]; then
        ERROR "文件不存在: $src_path"
        return 1
    fi

    # 确保目录
    WG_DIR="/etc/wireguard"
    mkdir -p "$WG_DIR"

    local base_name
    base_name=$(basename "$src_path")
    local dst_path="$WG_DIR/$base_name"

    # 建立软链接指向源文件（不复制）
    rm -f "$dst_path"
    ln -s "$src_path" "$dst_path"
    INFO "已创建到配置的软链接: $dst_path -> $src_path"

    # 立即启动该配置
    if wg-quick up "$dst_path"; then
        INFO "已连接: $dst_path"
        wg show || true
    else
        ERROR "连接失败，请检查配置"
        return 1
    fi

    # 直接配置开机自启动（不交互）
    detect_service_manager
    detect_startup_method

    # 解析接口名
    local iface_name
    iface_name=$(basename "$dst_path" .conf)
    WG_INTERFACE="$iface_name"
    WG_DIR="/etc/wireguard"

    if setup_autostart; then
        INFO "已尝试配置开机自启动"
    else
        WARN "开机自启动配置可能失败，请手动检查服务管理器设置"
    fi

    return 0
}

# 卸载WireGuard（客户端）
uninstall_wireguard_client() {
    echo -e "\n${Blue}=== 卸载 WireGuard 客户端 ===${Font}"

    check_root
    detect_os || return 1

    # 尝试停止所有已存在的 wg-quick 接口（避免占用）
    local ifaces
    ifaces=$(wg show interfaces 2>/dev/null)
    if [[ -n "$ifaces" ]]; then
        for i in $ifaces; do
            wg-quick down "$i" 2>/dev/null || true
        done
    fi

    # 根据包管理器卸载 wireguard-tools / wireguard
    case $PACKAGE_MANAGER in
        "apt-get")
            apt-get remove -y wireguard wireguard-tools 2>/dev/null || true
            ;;
        "yum")
            yum remove -y wireguard-tools 2>/dev/null || true
            ;;
        "dnf")
            dnf remove -y wireguard-tools 2>/dev/null || true
            ;;
        "zypper")
            zypper remove -y wireguard-tools 2>/dev/null || true
            ;;
        "pacman")
            pacman -R --noconfirm wireguard-tools 2>/dev/null || true
            ;;
        "apk")
            apk del wireguard-tools 2>/dev/null || true
            ;;
        "opkg")
            opkg remove wireguard-tools 2>/dev/null || true
            ;;
        *)
            WARN "未知包管理器，无法自动卸载WireGuard客户端"
            ;;
    esac

    INFO "WireGuard 客户端卸载流程完成（如有残留，请手动清理）"
}


# 卸载WireGuard
uninstall_wireguard() {
    echo -e "\n${Blue}=== WireGuard 卸载确认 ===${Font}"

    # 检查当前运行的隧道
    local running_tunnels=()
    local all_tunnels=()

    # 获取所有隧道信息
    for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
        [[ -f "$tunnel_info" ]] || continue
        local tunnel_name=$(basename "$tunnel_info" .conf)
        all_tunnels+=("$tunnel_name")

        # 加载隧道配置
        source "$tunnel_info"
        if wg show "$WG_INTERFACE" &>/dev/null; then
            running_tunnels+=("$tunnel_name ($WG_INTERFACE)")
        fi
    done

    # 显示将要删除的内容
    echo -e "${Yellow}此操作将删除以下内容：${Font}"
    echo "1. WireGuard软件包"

    if [[ ${#all_tunnels[@]} -gt 0 ]]; then
        echo "2. 所有隧道配置 (${#all_tunnels[@]}个):"
        for tunnel in "${all_tunnels[@]}"; do
            echo "   - $tunnel"
        done
    else
        echo "2. 配置文件目录"
    fi

    if [[ ${#running_tunnels[@]} -gt 0 ]]; then
        echo -e "3. ${Red}当前运行的隧道 (${#running_tunnels[@]}个):${Font}"
        for tunnel in "${running_tunnels[@]}"; do
            echo -e "   - ${Red}$tunnel${Font}"
        done
    fi

    echo "4. 所有客户端配置文件"
    echo "5. 所有密钥文件"

    # 显示配置目录信息
    if [[ -L "/etc/wireguard" ]]; then
        local real_dir=$(readlink "/etc/wireguard")
        echo -e "6. 配置目录: /etc/wireguard -> ${Yellow}$real_dir${Font} (软链接和真实目录)"
    else
        echo "6. 配置目录: /etc/wireguard"
    fi

    echo -e "\n${Red}警告: 此操作不可逆，所有WireGuard配置将永久丢失！${Font}"
    echo -e "${Yellow}建议在卸载前备份重要的配置文件${Font}"

    # 第一次确认
    read -p "确认要完全卸载WireGuard吗? (y/N): " confirm1
    if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
        INFO "卸载操作已取消"
        return 1
    fi



    # 第二次确认（如果有运行的隧道）
    if [[ ${#running_tunnels[@]} -gt 0 ]]; then
        echo -e "\n${Red}检测到正在运行的隧道，强制卸载将中断网络连接！${Font}"
        read -p "确认强制停止所有隧道并卸载? (y/N): " confirm2
        if [[ ! "$confirm2" =~ ^[Yy]$ ]]; then
            INFO "卸载操作已取消"
            return 1
        fi
    fi

    INFO "开始卸载WireGuard..."

    # 停止所有隧道服务
    if [[ ${#all_tunnels[@]} -gt 0 ]]; then
        INFO "停止所有WireGuard隧道..."
        for tunnel_info in "${WG_TUNNELS_DIR}"/*.conf; do
            [[ -f "$tunnel_info" ]] || continue
            source "$tunnel_info"

            if wg show "$WG_INTERFACE" &>/dev/null; then
                INFO "停止隧道: $WG_INTERFACE"
                wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null || true
            fi

            # 清理所有相关的systemd服务
            local service_name="wireguard-${WG_INTERFACE}"
            systemctl stop "${service_name}.service" 2>/dev/null || true
            systemctl disable "${service_name}.service" 2>/dev/null || true
            rm -f "/etc/systemd/system/${service_name}.service"

            # 清理可能存在的旧配置
            systemctl stop wg-quick@${WG_INTERFACE} 2>/dev/null || true
            systemctl disable wg-quick@${WG_INTERFACE} 2>/dev/null || true
            rm -rf "/etc/systemd/system/wg-quick@${WG_INTERFACE}.service.d" 2>/dev/null || true
        done

        # 重新加载systemd配置
        systemctl daemon-reload
        INFO "已清理所有systemd服务配置"
    fi

    # 删除配置文件
    INFO "删除配置文件..."
    if [[ -L "/etc/wireguard" ]]; then
        local real_dir=$(readlink "/etc/wireguard")
        INFO "删除软链接: /etc/wireguard"
        rm -f "/etc/wireguard"
        INFO "删除真实配置目录: $real_dir"
        rm -rf "$real_dir"
    else
        INFO "删除配置目录: $WG_DIR"
        rm -rf "$WG_DIR"
    fi

    # 卸载软件包
    INFO "卸载WireGuard软件包..."
    case $PACKAGE_MANAGER in
        "apt-get")
            $PACKAGE_MANAGER remove -y wireguard wireguard-tools 2>/dev/null || true
            ;;
        "yum"|"dnf")
            $PACKAGE_MANAGER remove -y wireguard-tools 2>/dev/null || true
            ;;
        "zypper")
            $PACKAGE_MANAGER remove -y wireguard-tools 2>/dev/null || true
            ;;
        "pacman")
            $PACKAGE_MANAGER -R --noconfirm wireguard-tools 2>/dev/null || true
            ;;
        "apk")
            $PACKAGE_MANAGER del wireguard-tools 2>/dev/null || true
            ;;
        "opkg")
            $PACKAGE_MANAGER remove wireguard-tools 2>/dev/null || true
            ;;
        *)
            WARN "未知包管理器: $PACKAGE_MANAGER，请手动卸载WireGuard"
            ;;
    esac

    # 清理系统配置
    INFO "清理系统配置..."

    # 恢复IP转发设置（可选）
    echo -e "\n${Yellow}是否恢复IP转发设置到默认状态?${Font}"
    echo "这将禁用系统的IP转发功能，可能影响其他网络服务"
    read -p "恢复IP转发设置? (y/N): " restore_forward

    if [[ "$restore_forward" =~ ^[Yy]$ ]]; then
        # 注释掉sysctl.conf中的转发设置
        if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            sed -i 's/^net\.ipv4\.ip_forward=1/#net.ipv4.ip_forward=1/' /etc/sysctl.conf
            sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
            INFO "已禁用IPv4转发"
        fi
        if grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
            sed -i 's/^net\.ipv6\.conf\.all\.forwarding=1/#net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
            sysctl -w net.ipv6.conf.all.forwarding=0 2>/dev/null || true
            INFO "已禁用IPv6转发"
        fi
    else
        INFO "保留IP转发设置"
    fi

    echo -e "\n${Green}WireGuard已完全卸载${Font}"
    echo "如需重新安装，请重新运行此脚本"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mWireGuard 多隧道管理工具\033[0m —————————————————————————————————"
        echo -e "\033[1;36m                                     版本: ${SCRIPT_VERSION}  作者：AI老G\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m1、安装WireGuard/创建隧道 - 服务端\033[0m"
        echo -e "\033[1;32m2、安装WireGuard/加载配置 - 客户端\033[0m"
        echo -e "\033[1;32m3、生成客户端配置\033[0m"
        echo -e "\033[1;32m4、查看隧道状态\033[0m"
        echo -e "\033[1;32m5、查看客户端配置\033[0m"
        echo -e "\033[1;32m6、删除客户端配置\033[0m"
        echo -e "\033[1;32m7、启动WireGuard隧道\033[0m"
        echo -e "\033[1;32m8、停止WireGuard隧道\033[0m"
        echo -e "\033[1;32m9、隧道管理\033[0m"
        echo -e "\033[1;32m10、卸载WireGuard\033[0m"
        echo -e "\033[1;32m11、卸载WireGuard（客户端）\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -p "请输入您的选择（1-11，按q退出）：" choice

        case "$choice" in
            1)
                # 检查WireGuard是否已安装
                if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
                    INFO "WireGuard已安装，直接创建隧道"
                    detect_service_manager
                    detect_firewall
                    detect_startup_method
                    if setup_server; then
                        configure_firewall
                        start_wireguard
                    fi
                else
                    INFO "WireGuard未安装，开始完整安装流程"
                    detect_os
                    configure_install_path
                    detect_service_manager
                    detect_firewall
                    detect_startup_method
                    if install_wireguard; then
                        if setup_server; then
                            configure_firewall
                            start_wireguard
                        fi
                    fi
                fi
                ;;
            2)
                install_wireguard_client
                ;;
            3)
                generate_client_config
                ;;
            4)
                show_status
                ;;
            5)
                show_client_config
                ;;
            6)
                delete_client
                ;;
            7)
                start_wireguard_menu
                ;;
            8)
                stop_wireguard_menu
                ;;
            9)
                tunnel_management_menu
                continue  # 从子菜单返回后直接继续，不显示"按任意键继续"
                ;;
            10)
                uninstall_wireguard
                ;;
            11)
                uninstall_wireguard_client
                ;;
            [Qq])
                exit 0
                ;;
            *)
                ERROR "输入错误，按任意键重新输入！"
                read -r -n 1
                continue
                ;;
        esac

        echo
        read -n 1 -p "按任意键继续..."
    done
}

# 启动WireGuard隧道菜单
start_wireguard_menu() {
    # 检测服务管理系统
    detect_service_manager

    if ! select_tunnel "请选择要启动的隧道"; then
        ERROR "未找到可用隧道，请先创建隧道"
        return 1
    fi

    start_wireguard
}

# 停止WireGuard隧道菜单
stop_wireguard_menu() {
    # 检测服务管理系统
    detect_service_manager

    if ! select_tunnel "请选择要停止的隧道"; then
        ERROR "未找到可用隧道"
        return 1
    fi

    stop_wireguard
}

# 隧道管理菜单
tunnel_management_menu() {
    while true; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mWireGuard 隧道管理\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、查看所有隧道\033[0m"
        echo -e "\033[1;32m2、查看隧道详细信息\033[0m"
        echo -e "\033[1;32m3、删除隧道\033[0m"
        echo -e "\033[1;32m4、查看所有客户端\033[0m"
        echo -e "\033[1;32m5、修改配置目录\033[0m"
        echo -e "\033[1;32m6、返回主菜单\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -p "请输入您的选择（1-6）：" choice

        case "$choice" in
            1)
                list_tunnels || echo "暂无隧道"
                ;;
            2)
                show_tunnel_details
                ;;
            3)
                delete_tunnel
                ;;
            4)
                list_clients
                ;;
            5)
                configure_install_path
                ;;
            6)
                return 0
                ;;
            *)
                ERROR "输入错误，按任意键重新输入！"
                read -r -n 1
                continue
                ;;
        esac

        # 执行完操作后暂停，等待用户确认（返回主菜单选项已经return，不会执行到这里）
        echo
        read -n 1 -p "按任意键继续..."
    done
}

# 检测服务管理系统
detect_service_manager() {
    if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
        SERVICE_MANAGER="systemd"
    elif command -v service &> /dev/null; then
        SERVICE_MANAGER="sysv"
    elif command -v rc-service &> /dev/null; then
        SERVICE_MANAGER="openrc"
    else
        SERVICE_MANAGER="none"
        WARN "未检测到支持的服务管理系统，WireGuard需要手动管理"
    fi
    INFO "服务管理系统: $SERVICE_MANAGER"
}

# 检测防火墙系统
detect_firewall() {
    FIREWALL_TYPE="none"

    # 检测UFW
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            FIREWALL_TYPE="ufw"
            INFO "检测到活跃的UFW防火墙"
        else
            INFO "检测到UFW但未启用"
        fi
    # 检测firewalld
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            FIREWALL_TYPE="firewalld"
            INFO "检测到活跃的firewalld防火墙"
        else
            INFO "检测到firewalld但未启用"
        fi
    # 检测iptables
    elif command -v iptables &> /dev/null; then
        # 检查INPUT链的默认策略和规则数量
        local input_policy=$(iptables -L INPUT -n | head -1 | grep -o "policy [A-Z]*" | awk '{print $2}')
        local input_rules=$(iptables -L INPUT --line-numbers | wc -l)

        # 如果默认策略是DROP，或者有自定义规则（超过3行：标题行+空行+默认规则），则认为防火墙启用
        if [[ "$input_policy" == "DROP" ]] || [[ $input_rules -gt 3 ]]; then
            FIREWALL_TYPE="iptables"
            if [[ "$input_policy" == "DROP" ]]; then
                INFO "检测到iptables防火墙 (默认策略: DROP)"
            else
                INFO "检测到iptables防火墙 (有自定义规则)"
            fi
        else
            INFO "检测到iptables但防火墙未启用 (默认策略: ACCEPT，无自定义规则)"
        fi
    else
        WARN "未检测到防火墙系统"
    fi

    INFO "防火墙类型: $FIREWALL_TYPE"
}

# 配置防火墙规则
configure_firewall() {
    if [[ "$FIREWALL_TYPE" == "none" ]]; then
        INFO "无需配置防火墙规则"
        return 0
    fi

    INFO "配置防火墙规则..."

    case "$FIREWALL_TYPE" in
        "ufw")
            # UFW配置
            INFO "配置UFW防火墙规则"

            # 允许WireGuard端口
            ufw allow ${WG_PORT}/udp comment "WireGuard"

            # 配置转发规则
            ufw route allow in on ${WG_INTERFACE}
            ufw route allow out on ${WG_INTERFACE}

            # 重新加载UFW
            ufw reload

            INFO "UFW防火墙配置完成"
            ;;

        "firewalld")
            # firewalld配置
            INFO "配置firewalld防火墙规则"

            # 允许WireGuard端口
            firewall-cmd --permanent --add-port=${WG_PORT}/udp

            # 添加WireGuard接口到trusted区域
            firewall-cmd --permanent --zone=trusted --add-interface=${WG_INTERFACE}

            # 启用伪装（NAT）
            firewall-cmd --permanent --add-masquerade

            # 重新加载配置
            firewall-cmd --reload

            INFO "firewalld防火墙配置完成"
            ;;

        "iptables")
            # iptables配置
            INFO "配置iptables防火墙规则"

            # 允许WireGuard端口
            iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

            # 保存iptables规则（根据不同发行版）
            if command -v iptables-save &> /dev/null; then
                if [[ -f /etc/iptables/rules.v4 ]]; then
                    iptables-save > /etc/iptables/rules.v4
                elif [[ -f /etc/sysconfig/iptables ]]; then
                    iptables-save > /etc/sysconfig/iptables
                else
                    WARN "无法自动保存iptables规则，请手动保存"
                fi
            fi

            INFO "iptables防火墙配置完成"
            ;;

        *)
            WARN "未知防火墙类型，请手动配置以下规则："
            echo "- 允许UDP端口 ${WG_PORT}"
            echo "- 允许${WG_INTERFACE}接口的转发流量"
            ;;
    esac
}



# 检测现有WireGuard配置
detect_existing_config() {
    local default_dir="/etc/wireguard"

    # 检查 /etc/wireguard 是否存在配置
    if [[ -d "$default_dir" ]] || [[ -L "$default_dir" ]]; then
        # 检查是否有配置文件
        if [[ -n "$(ls "$default_dir"/*.conf 2>/dev/null)" ]] || [[ -n "$(ls "$default_dir"/tunnels/*.conf 2>/dev/null)" ]]; then
            INFO "检测到现有WireGuard配置"

            # 显示真实的配置目录路径（仅用于用户了解）
            if [[ -L "$default_dir" ]]; then
                # 是软链接，显示真实路径
                local real_dir=$(readlink "$default_dir")
                INFO "配置目录: $default_dir -> $real_dir (软链接)"
                INFO "实际存储位置: $real_dir"
            else
                # 是真实目录
                INFO "配置目录: $default_dir (真实目录)"
            fi

            # 程序运行时始终使用统一路径
            WG_DIR="$default_dir"
            WG_CONFIG_DIR="${WG_DIR}/configs"
            WG_KEYS_DIR="${WG_DIR}/keys"
            WG_TUNNELS_DIR="${WG_DIR}/tunnels"

            return 0
        fi
    fi

    return 1
}

# 检查WireGuard运行状态
check_wireguard_status() {
    # 检查WireGuard是否已安装
    if ! command -v wg &> /dev/null; then
        INFO "WireGuard未安装，将在选择安装选项时进行安装"
        return 1
    fi

    # 检查是否有运行中的接口
    local running_interfaces
    running_interfaces=$(wg show interfaces 2>/dev/null)

    if [[ -n "$running_interfaces" ]]; then
        INFO "检测到WireGuard已安装并运行中"
        return 0
    else
        INFO "WireGuard已安装但未运行"
        return 2
    fi
}

# 脚本入口
check_root

# 检查WireGuard状态
wg_status_code=0
check_wireguard_status
wg_status_code=$?

case $wg_status_code in
    0)
        # WireGuard运行中，检测现有配置
        if detect_existing_config; then
            INFO "已加载现有WireGuard配置，直接进入管理界面"
        else
            WARN "检测到WireGuard运行但无法确定配置路径，使用默认路径"
        fi
        ;;
    1)
        # WireGuard未安装，首次使用时配置路径
        INFO "首次使用，将在安装时配置路径"
        ;;
    2)
        # WireGuard已安装但未运行，检测配置
        if ! detect_existing_config; then
            INFO "检测到WireGuard已安装，将在创建隧道时配置路径"
        fi
        ;;
esac

main_menu
