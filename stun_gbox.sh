#!/bin/sh

logo() {
    cat << 'LOGO' | echo -e "$(cat -)"

—————————————————————————————————— A I 老 G ———————————————————————————————————————

       $$$$$$\          $$$$$$$\   $$$$$$\  $$\   $$\ 
      $$  __$$\         $$  __$$\ $$  __$$\ $$ |  $$ |
      $$ /  \__|        $$ |  $$ |$$ /  $$ |\$$\ $$  |
      $$ |$$$$\ $$$$$$\ $$$$$$$\ |$$ |  $$ | \$$$$  / 
      $$ |\_$$ |\______|$$  __$$\ $$ |  $$ | $$  $$<  
      $$ |  $$ |        $$ |  $$ |$$ |  $$ |$$  /\$$\ 
      \$$$$$$  |        $$$$$$$  | $$$$$$  |$$ /  $$ |
       \______/         \_______/  \______/ \__|  \__|

———————————————————————————————————————————————————————————————————————————————————
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
# 有问题可入群交流：TG电报：https://t.me/ailg666；加微入群：ailg_666；
# 如果您喜欢这个脚本，可以请我喝咖啡：https://ailg.ggbond.org/3q.jpg
LOGO
}

logo

# 检查并安装 jq（如果不存在）
if ! command -v jq >/dev/null 2>&1; then
    # 备份源配置文件
    cp /etc/apk/repositories /etc/apk/repositories.bak
    
    # 替换为清华镜像源
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
    
    # 执行 jq 安装
    apk add --no-cache -q jq >/dev/null 2>&1
    
    # 检查是否安装成功，失败则恢复源并中止执行
    if ! command -v jq >/dev/null 2>&1; then
        cp /etc/apk/repositories.bak /etc/apk/repositories
        echo "错误: jq 安装失败，已恢复源配置，脚本中止执行"
        exit 1
    fi
fi

# 检查并安装 ping（如果不存在）
if ! command -v ping >/dev/null 2>&1; then
    # 备份源配置文件（如果之前没有备份）
    if [ ! -f /etc/apk/repositories.bak ]; then
        cp /etc/apk/repositories /etc/apk/repositories.bak
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
    fi
    
    # 执行 iputils 安装（包含 ping）
    apk add --no-cache -q iputils >/dev/null 2>&1
    
    # 检查是否安装成功
    if ! command -v ping >/dev/null 2>&1; then
        if [ -f /etc/apk/repositories.bak ]; then
            cp /etc/apk/repositories.bak /etc/apk/repositories
        fi
        echo "错误: ping 安装失败，已恢复源配置，脚本中止执行"
        exit 1
    fi
fi

# 参数处理
DOMAIN_RAW=$1
OPEN_API_URL=$2
TOKEN=$3
PORT=$4

# 检查必需参数
if [ -z "$DOMAIN_RAW" ] || [ -z "$OPEN_API_URL" ] || [ -z "$TOKEN" ] || [ -z "$PORT" ]; then
    echo "错误: 缺少必需参数"
    echo "用法: $0 <DOMAIN> <OPEN_API_URL> <TOKEN> <PORT>"
    echo "示例: $0 v4.abc.com http://192.168.5.33:3002/openapi/v1 your_token 12345"
    exit 1
fi

# 处理域名：去掉 *. 或 . 开头
DOMAIN="$DOMAIN_RAW"
if [ "${DOMAIN#\*.}" != "$DOMAIN" ]; then
    DOMAIN="${DOMAIN#\*.}"
fi
if [ "${DOMAIN#.}" != "$DOMAIN" ]; then
    DOMAIN="${DOMAIN#.}"
fi

# 处理 Open API URL：去掉末尾的 /
OPEN_API_URL="${OPEN_API_URL%/}"

# 验证 Open API URL 格式和端口号
if ! echo "$OPEN_API_URL" | grep -qE '^https?://[^:]+:3002/'; then
    echo "错误: Open API URL 格式不正确或端口号不是 3002"
    echo "期望格式: http://hostname:3002/path 或 https://hostname:3002/path"
    echo "当前值: ${OPEN_API_URL}"
    exit 1
fi

# 从 Open API URL 中提取主机名（IP 或域名）
# 提取 http://hostname:3002 或 https://hostname:3002 中的 hostname 部分
HOSTNAME=$(echo "$OPEN_API_URL" | sed -E 's|^https?://([^:/]+).*|\1|')

if [ -z "$HOSTNAME" ]; then
    echo "错误: 无法从 Open API URL 中提取主机名"
    exit 1
fi

# 执行 ping 检查
if ! ping -c 1 -W 2 "$HOSTNAME" >/dev/null 2>&1; then
    echo "错误: 无法 ping 通主机 ${HOSTNAME}，请检查网络连接"
    exit 1
fi

# 构建新的 API 端点：将端口 3002 替换为 4567，并替换路径为 /api/sunpanel/update-items
# 提取协议和主机部分，替换端口，然后添加新路径
NEW_API_URL=$(echo "$OPEN_API_URL" | sed -E 's|^(https?://[^:]+):3002(/.*)?$|\1:4567/api/sunpanel/update-items|')

# 构建 domainPort（域名:端口）
DOMAIN_PORT="${DOMAIN}:${PORT}"

# 构建 JSON 请求体
JSON_BODY=$(jq -n -c \
    --arg apiUrl "$OPEN_API_URL" \
    --arg token "$TOKEN" \
    --arg domainPort "$DOMAIN_PORT" \
    '{
        "apiUrl": $apiUrl,
        "token": $token,
        "domainPort": $domainPort
    }')

# 执行 curl 请求
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$NEW_API_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY")

# 分离响应体和 HTTP 状态码
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# 检查响应
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "操作完成！"
else
    echo "错误: 请求失败，HTTP 状态码: ${HTTP_CODE}"
    echo "响应内容:"
    echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"
    exit 1
fi

