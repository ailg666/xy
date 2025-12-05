#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CONTAINER_NAME="pgyvpn"
IMAGE_NAME="crpi-orhk6a4lutw1gb13.cn-hangzhou.personal.cr.aliyuncs.com/bestoray/pgyvpn"
RC_LOCAL_PATH="/etc/rc.local"
IP_BIN="$(command -v ip 2>/dev/null || echo /sbin/ip)"

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*"; }
log_error() { echo "[ERROR] $*" 1>&2; }

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "请以 root 身份运行：sudo $SCRIPT_NAME"
        exit 1
    fi
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "未检测到 docker。请先安装 docker 再运行本脚本。"
        echo "常见安装命令：curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
}

ensure_tun_device() {
    if [ -c /dev/net/tun ]; then
        return 0
    fi

    if ! modprobe tun; then
        log_error "'modprobe tun' 命令执行失败。内核可能不支持 TUN/TAP。"
        return 1
    fi

    sleep 1

    if [ -c /dev/net/tun ]; then
        chmod 666 /dev/net/tun || true
        return 0
    else
        log_error "无法创建 /dev/net/tun 设备。"
        return 1
    fi
}

setup_tun_autostart() {
    local MODPROBE
    MODPROBE="$(command -v modprobe 2>/dev/null || echo /sbin/modprobe)"
    local tun_lines="${MODPROBE} tun || true"

    if [ -d /run/systemd/system ] && systemctl list-unit-files | grep -q "rc-local.service"; then
        if [ ! -f "$RC_LOCAL_PATH" ]; then
            printf '%s\n' '#!/bin/sh -e' '' 'exit 0' > "$RC_LOCAL_PATH"
        fi
        chmod +x "$RC_LOCAL_PATH"
        if ! grep -q "modprobe tun" "$RC_LOCAL_PATH"; then
            awk -v ins="$tun_lines" '
              BEGIN{added=0}
              /^exit 0$/ && !added { print ins; print; added=1; next }
              { print }
              END { if (!added) print ins }
            ' "$RC_LOCAL_PATH" > "$RC_LOCAL_PATH.tmp" && mv "$RC_LOCAL_PATH.tmp" "$RC_LOCAL_PATH"
            chmod +x "$RC_LOCAL_PATH"
        fi
        systemctl enable rc-local.service >/dev/null 2>&1 || true
        systemctl start rc-local.service >/dev/null 2>&1 || true
    else
        local cron_file="/etc/cron.d/enable-tun"
        printf "@reboot root %s\n" "sh -c '$tun_lines'" > "$cron_file"
        chmod 644 "$cron_file"
    fi
}

ensure_ipv4_forwarding() {
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || echo 1 > /proc/sys/net/ipv4/ip_forward || true
    else
        echo 1 > /proc/sys/net/ipv4/ip_forward || true
    fi
    
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/^net\.ipv4\.ip_forward[[:space:]]*=/d' /etc/sysctl.conf
        printf '\nnet.ipv4.ip_forward=1\n' >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1 || true
    fi
}

detect_host_main_interface() {
    HOST_MAIN_IF=""
    HOST_MAIN_IF="$($IP_BIN -4 route get 223.5.5.5 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
    if [ -z "${HOST_MAIN_IF}" ]; then
        HOST_MAIN_IF="$($IP_BIN -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' | head -n1)"
    fi
}

is_valid_ipv4() {
    local ip="$1"
    echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    IFS='.' read -r a b c d <<EOF
$ip
EOF
    for n in "$a" "$b" "$c" "$d"; do
        if [ "$n" -gt 255 ] || [ "$n" -lt 0 ]; then
            return 1
        fi
    done

    if [ "$a" -eq 10 ]; then
        return 0
    fi

    if [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; then
        return 0
    fi

    if [ "$a" -eq 192 ] && [ "$b" -eq 168 ]; then
        return 0
    fi

    return 1
}

is_valid_cidr() {
    local cidr="$1"
    echo "$cidr" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$' || return 1
    local ip="${cidr%/*}"
    local mask="${cidr#*/}"
    is_valid_ipv4 "$ip" || return 1
    [ "$mask" -ge 0 ] && [ "$mask" -le 32 ] || return 1

    IFS='.' read -r a b c d <<EOF
$ip
EOF

    if [ "$a" -eq 10 ]; then
        return 0
    fi

    if [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; then
        return 0
    fi

    if [ "$a" -eq 192 ] && [ "$b" -eq 168 ]; then
        return 0
    fi

    return 1
}

prompt_inputs() {
    echo
    read -rp "请输入蒲公英账号用户名: " PGY_USERNAME
    while [ -z "${PGY_USERNAME:-}" ]; do
        read -rp "用户名不能为空，请重新输入: " PGY_USERNAME
    done

    read -rsp "请输入蒲公英账号密码（不会显示）: " PGY_PASSWORD; echo
    while [ -z "${PGY_PASSWORD:-}" ]; do
        read -rsp "密码不能为空，请重新输入: " PGY_PASSWORD; echo
    done

    read -rp "请输入组网目标网段(CIDR，必须是私网网段，如 192.168.50.0/24): " TARGET_CIDR
    while ! is_valid_cidr "${TARGET_CIDR:-}"; do
        read -rp "格式不正确或不是私网网段，请输入私网 CIDR(如 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16): " TARGET_CIDR
    done

    read -rp "请输入另一个蒲公英 docker 的虚拟IP(必须是私网地址): " PEER_VIP
    while ! is_valid_ipv4 "${PEER_VIP:-}"; do
        read -rp "格式不正确或不是私网地址，请输入私网 IPv4(如 10.0.0.1, 172.16.3.2, 192.168.1.1): " PEER_VIP
    done
}

ensure_container_absent_or_replace() {
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        log_warn "容器 $CONTAINER_NAME 已存在。"
        read -rp "是否删除并继续安装? [y/N]: " ans
        case "${ans:-N}" in
            y|Y)
                docker rm -f "$CONTAINER_NAME" >/dev/null || true
                ;;
            *)
                log_error "已取消，退出。"
                exit 1
                ;;
        esac
    fi
}

run_container() {
    log_info "启动容器 $CONTAINER_NAME ..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --device=/dev/net/tun \
        --net=host \
        --cap-add=NET_ADMIN \
        --env PGY_USERNAME="${PGY_USERNAME}" \
        --env PGY_PASSWORD="${PGY_PASSWORD}" \
        "$IMAGE_NAME"
}

inject_rules_into_pgystart() {
    local marker="# injected by pgyvpn_setup"
    local inject_block="${marker}\niptables -F\niptables -I FORWARD -i oray_vnc -j ACCEPT\niptables -I FORWARD -o oray_vnc -j ACCEPT\niptables -t nat -I POSTROUTING -o oray_vnc -j MASQUERADE\nip route replace ${TARGET_CIDR} via ${PEER_VIP}"
    if [ -n "${HOST_MAIN_IF:-}" ]; then
        inject_block="${inject_block}\niptables -I FORWARD -i ${HOST_MAIN_IF} -j ACCEPT\niptables -I FORWARD -o ${HOST_MAIN_IF} -j ACCEPT\niptables -t nat -I POSTROUTING -o ${HOST_MAIN_IF} -j MASQUERADE"
    fi

    if docker exec "$CONTAINER_NAME" sh -c "grep -qF '$marker' /usr/share/pgyvpn/script/pgystart"; then
        return 0
    fi

    docker exec "$CONTAINER_NAME" sh -lc "\
awk -v blk=\"$inject_block\" -v cidr=\"${TARGET_CIDR}\" -v peer_vip=\"${PEER_VIP}\" '\
    BEGIN { found = 0 }\
    /while[[:space:]]+true/ {\
        if (found == 0) {\
            print blk;\
            print \"while true\";\
            print \"do\";\
            print \"  if ! ip route show | grep -qF \\\"\" cidr \" via \" peer_vip \"\\\" ; then\";\
            print \"    ip route replace \" cidr \" via \" peer_vip;\
            print \"  fi\";\
            print \"  sleep 60\";\
            print \"done\";\
            found = 1;\
            next\
        }\
    }\
    /^do$/ && found { next }\
    /^[[:space:]]*sleep/ && found { next }\
    /^done$/ && found { found = 0; next }\
    { print }\
' /usr/share/pgyvpn/script/pgystart \
> /tmp/pgystart && \
mv /tmp/pgystart /usr/share/pgyvpn/script/pgystart && \
chmod +x /usr/share/pgyvpn/script/pgystart"
}

restart_and_verify() {
    log_info "重启容器..."
    docker restart "$CONTAINER_NAME" >/dev/null
    sleep 3
}

main() {
    require_root
    require_docker
    ensure_tun_device
    prompt_inputs
    ensure_ipv4_forwarding
    detect_host_main_interface
    ensure_container_absent_or_replace
    run_container
    inject_rules_into_pgystart
    restart_and_verify

    echo
    log_info "安装完成。"
    echo -e "\033[1;36m喜欢这个脚本，可以请我喝咖啡：https://ailg.ggbond.org/3q.jpg\033[0m"
    echo -e "\033[1;36m关注AI老G，访问<https://space.bilibili.com/252166818\033[0m>"
}

main "$@"


