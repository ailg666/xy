#!/bin/bash

ver="202402190042"

upgrade_url="https://xy.ggbond.org/xy/aliyun_clear.sh"
upgrade_url_backup="https://xy.ggbond.org/xy/aliyun_clear.sh"
tg_push_api_url="https://xiaoyapush.ddsrem.com"

retry_command() {
    # 重试次数和最大重试次数
    retries=0
    max_retries=10
    local cmd="$1"
    local success=false
    local output=""

    while ! $success && [ $retries -lt $max_retries ]; do
        output=$(eval "$cmd" 2>&1)
        if [ $? -eq 0 ]; then
            success=true
        else
            retries=$(($retries+1))
            echo "#Failed to execute command \"$(echo "$cmd" | awk '{print $1}')\", retrying in 1 seconds (retry $retries of $max_retries)..." >&2
            sleep 1
        fi
    done

    if $success; then
        echo "$output"
        return 0
    else
        echo "#Failed to execute command after $max_retries retries: $cmd" >&2
        echo "#Command output: $output" >&2
        return 1
    fi
}


#检查脚本更新
if which curl &>/dev/null;then
newsh=$(retry_command "curl -k -s \"$upgrade_url\" 2>/dev/null")
if [ -z "$(echo "$newsh" | grep "^#!/bin/bash")" ];then
    newsh=$(retry_command "curl -k -s \"$upgrade_url_backup\" 2>/dev/null")
fi
fi
latest_ver=$(echo "$newsh" | grep "^ver=" | tr -d '"ver=')
if [ ! "$latest_ver"x = x ] && [ ! "$ver"x = "$latest_ver"x ];then
filename=${0}
dir=$(dirname "$filename")
echo ${0}
echo $filename
echo $dir
if [ "$dir"x = x ];then
    filename="./$filename"
fi
echo ${0}
echo $filename
echo $dir
if [ ! "$(echo "$dir" | awk -F/ '{print $1}')"x = x ];then
    filename="./$filename"
fi
echo ${0}
echo $filename
echo $dir

shell_cmd="sh"
which "bash" >/dev/null
if [ $? -eq 0 ];then
    shell_cmd="bash"
fi

if [ -n "$(cat "$filename" | head -n 1 | grep "^#!/bin/bash")" ];then
    echo "$newsh" > "$filename"
    chmod +x "$filename"
    echo "脚本已自动更新到最新版本$latest_ver"
    echo $filename
    exit 0
fi
fi
