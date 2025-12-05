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

if ! command -v jq >/dev/null 2>&1; then
  cp /etc/apk/repositories /etc/apk/repositories.bak
  sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
  apk add --no-cache -q jq >/dev/null 2>&1
  if ! command -v jq >/dev/null 2>&1; then
    cp /etc/apk/repositories.bak /etc/apk/repositories
    echo "jq install failed" >&2
    exit 1
  fi
fi

NEW_IP=$1
NEW_PORT=$2
API_TOKEN=$3
DOMAIN=$4
RULE_NAME=${5:-ailg}
ACCOUNT_ID=${6:-""}

if [ -z "$NEW_IP" ] || [ -z "$NEW_PORT" ] || [ -z "$API_TOKEN" ] || [ -z "$DOMAIN" ]; then
  echo "usage: $0 <NEW_IP> <NEW_PORT> <API_TOKEN> <DOMAIN> [RULE_NAME] [ACCOUNT_ID]" >&2
  exit 1
fi

if [ -z "$ACCOUNT_ID" ]; then
  ACCOUNTS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json")
  ACCOUNT_ID=$(echo "$ACCOUNTS_RESPONSE" | jq -r '.result[0].id')
  if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "null" ]; then
    echo "failed to get account id" >&2
    echo "$ACCOUNTS_RESPONSE" | jq '.' >&2
    exit 1
  fi
fi

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
  echo "failed to get zone id" >&2
  exit 1
fi

WORKER_NAME="${RULE_NAME}-redirect"
KV_NAMESPACE_NAME="${RULE_NAME}-config"

KV_NAMESPACE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" | jq -r ".result[] | select(.title == \"${KV_NAMESPACE_NAME}\") | .id")
if [ -z "$KV_NAMESPACE_ID" ] || [ "$KV_NAMESPACE_ID" = "null" ]; then
  KV_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"title\":\"${KV_NAMESPACE_NAME}\"}")
  KV_NAMESPACE_ID=$(echo "$KV_RESPONSE" | jq -r '.result.id')
  if [ -z "$KV_NAMESPACE_ID" ] || [ "$KV_NAMESPACE_ID" = "null" ]; then
    echo "kv namespace create failed" >&2
    echo "$KV_RESPONSE" | jq '.' >&2
    exit 1
  fi
fi

curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/ip" -H "Authorization: Bearer ${API_TOKEN}" --data "$NEW_IP" >/dev/null
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/port" -H "Authorization: Bearer ${API_TOKEN}" --data "$NEW_PORT" >/dev/null
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/domain" -H "Authorization: Bearer ${API_TOKEN}" --data "$DOMAIN" >/dev/null

WORKER_CODE=$(cat <<'EOF'
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});
async function handleRequest(request) {
  const url = new URL(request.url);
  const pathSegments = url.pathname.split('/').filter(Boolean);
  if (pathSegments.length > 0) {
  const subdomain = pathSegments[0];
  if (typeof CONFIG === 'undefined') {
    return new Response("KV not bound", { status: 500 });
  }
  let targetDomain = await CONFIG.get('domain');
  let targetPort = await CONFIG.get('port');
  if (!targetDomain || !targetPort) {
    return new Response("config missing", { status: 500 });
  }
  const rest = pathSegments.slice(1).join('/');
  const restPath = rest ? '/' + rest : '';
  const search = url.search || '';
  const targetUrl = `https://${subdomain}.${targetDomain}:${targetPort}${restPath}${search}`;
  return Response.redirect(targetUrl, 302);
  }
  return new Response("specify path", { status: 404 });
}
EOF
)

WORKER_CODE_FILE=$(mktemp)
echo "$WORKER_CODE" > "$WORKER_CODE_FILE"

METADATA_JSON=$(jq -n -c --arg namespace_id "$KV_NAMESPACE_ID" '{ "body_part":"script", "compatibility_date":"2024-01-01", "bindings":[{ "name":"CONFIG","namespace_id":$namespace_id,"type":"kv_namespace" }] }')

WORKER_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" -H "Authorization: Bearer ${API_TOKEN}" -F "metadata=${METADATA_JSON};type=application/json" -F "script=@${WORKER_CODE_FILE};type=application/javascript")

rm -f "$WORKER_CODE_FILE"

WORKER_SUCCESS=$(echo "$WORKER_RESPONSE" | jq -r '.success // false')
if [ "$WORKER_SUCCESS" != "true" ] && [ -n "$(echo "$WORKER_RESPONSE" | jq -r '.errors // empty')" ]; then
  echo "worker create/update warning" >&2
  echo "$WORKER_RESPONSE" | jq '.' >&2
fi

DNS_SUBDOMAIN="${RULE_NAME}.${DOMAIN}"
ROUTE_PATTERN="${DNS_SUBDOMAIN}/*"

EXISTING_ROUTE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" | jq -r ".result[] | select(.pattern == \"${ROUTE_PATTERN}\") | .id // empty")
if [ -n "$EXISTING_ROUTE" ] && [ "$EXISTING_ROUTE" != "null" ]; then
  curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes/${EXISTING_ROUTE}" -H "Authorization: Bearer ${API_TOKEN}" >/dev/null
  ROUTE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"pattern\":\"${ROUTE_PATTERN}\",\"script\":\"${WORKER_NAME}\"}")
else
  ROUTE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"pattern\":\"${ROUTE_PATTERN}\",\"script\":\"${WORKER_NAME}\"}")
fi

WILDCARD_RESPONSE=""
EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${DNS_SUBDOMAIN}" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" | jq -r '.result[0].id')

DNS_RECORD_NAME="$RULE_NAME"
DNS_RECORD_VALUE="8.8.8.8"

if [ -n "$EXISTING_RECORD" ] && [ "$EXISTING_RECORD" != "null" ]; then
  DNS_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${EXISTING_RECORD}" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${DNS_RECORD_VALUE}\",\"proxied\":true}")
else
  DNS_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${DNS_RECORD_VALUE}\",\"proxied\":true}")
fi

DNS_SUCCESS=$(echo "$DNS_RESPONSE" | jq -r '.success')
if [ "$DNS_SUCCESS" != "true" ]; then
  echo "dns update failed" >&2
  echo "$DNS_RESPONSE" | jq '.' >&2
  exit 1
fi

WILDCARD_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=*.${DOMAIN}" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" | jq -r '.result[0].id')
if [ -n "$WILDCARD_RECORD" ] && [ "$WILDCARD_RECORD" != "null" ]; then
  WILDCARD_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${WILDCARD_RECORD}" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
else
  WILDCARD_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
fi

WILDCARD_SUCCESS=$(echo "$WILDCARD_RESPONSE" | jq -r '.success')
if [ "$WILDCARD_SUCCESS" != "true" ]; then
  echo "wildcard dns warning" >&2
fi

echo "done: https://${DNS_SUBDOMAIN}/* -> ${WORKER_NAME}"
