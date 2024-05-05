#!/bin/sh

base_urls=(
    "https://gitlab.com/xiaoyaliu/data/-/raw/main"
    "https://raw.githubusercontent.com/xiaoyaliu00/data/main"
    "https://cdn.wygg.shop/https://raw.githubusercontent.com/xiaoyaliu00/data/main"
    "https://fastly.jsdelivr.net/gh/xiaoyaliu00/data@latest"
    "https://521github.com/extdomains/github.com/xiaoyaliu00/data/raw/main"
    "https://cors.zme.ink/https://raw.githubusercontent.com/xiaoyaliu00/data/main"
)

success=false
for base_url in "${base_urls[@]}"; do
    remote_ver=$(curl ${base_url}/version.txt 2>/dev/null)
    if [ $? -eq 0 ]; then
        success=true
		download_url="${base_url}"
        echo "有效地址为：$download_url" 
        break
    fi
done
if [ "$success" = false ]; then
    echo "找不到有效下载地址"
    exit 1
fi
    
get_docker_info(){
    if [ "$1"x != x ];then
        get_docker_info | awk '"'$1'"==$1'
        return
    fi
    images=$(docker images --no-trunc)
    for line in $(docker ps | tail -n +2 | grep -v "xiaoyakeeper" | awk '{print $NF}');do
        id=$(docker inspect --format='{{.Image}}' $line | awk -F: '{print $2}')
        echo "$line $(echo "$images" | grep $id | head -n 1)" | tr ':' ' ' | awk '{printf("%s %s %s\n",$1,$2,$5)}'
    done
}

get_xiaoya(){
    get_docker_info | grep "xiaoyaliu/alist" | awk '{print $1}'
}

init_para(){
    xiaoya_name=$1
    config_dir="$(docker inspect --format='{{range $v,$conf := .Mounts}}{{$conf.Source}}:{{$conf.Destination}}{{$conf.Type}}~{{end}}' $xiaoya_name | tr '~' '\n' | grep bind | sed 's/bind//g' | grep ":/data$" | awk -F: '{print $1}')"
    data_dir="$config_dir/data"
    mode="$(docker inspect --format='{{range $m, $conf := .NetworkSettings.Networks}}{{$m}}{{end}}' $xiaoya_name)"
}

config(){
    mkdir -p "${data_dir}"
    touch "${data_dir}/version.txt"
    local_ver=$(cat "${data_dir}/version.txt")
    if [ "$local_ver"x != "$remote_ver"x ] || [ ! -f "${data_dir}/tvbox.zip" ] || [ ! -f "${data_dir}/update.zip" ] || [ ! -f "${data_dir}/index.zip" ]; then
	echo "最新版本 $remote_ver 开始更新下载....."
        echo ""	
        wget -nv -O "${data_dir}/tvbox.zip" $download_url/tvbox.zip 
        wget -nv -O "${data_dir}/update.zip" $download_url/update.zip
        wget -nv -O "${data_dir}/index.zip" $download_url/index.zip 
        wget -nv -O "${data_dir}/version.txt" $download_url/version.txt 
    else
        echo "数据版本已经是最新的无须更新"		
    fi

    crontab -l |grep -E -v "update.zip|tvbox.zip|index.zip|version.txt|update_data.sh" > /tmp/current.crontab
    echo -e "*/15 0,15-23 * * * bash -c \"\$(curl http://docker.xiaoya.pro/update_data.sh)\" -s --no-upgrade" >> /tmp/current.crontab
    crontab /tmp/current.crontab
rm /tmp/current.crontab

    if [ "$mode"x = "bridge"x ]; then
        echo "http://127.0.0.1:81/data" > "${config_dir}"/download_url.txt
    elif [ "$mode"x = "host"x ] ; then
        echo "http://127.0.0.1:5233/data" > "${config_dir}"/download_url.txt
    else
        echo "请自行编辑"${config_dir}"/download_url.txt"	 
    fi
}

update_xiaoya(){
    para_v="$(docker inspect --format='{{range $v,$conf := .Mounts}}-v {{$conf.Source}}:{{$conf.Destination}} {{$conf.Type}}~{{end}}' $xiaoya_name | tr '~' '\n' | grep bind | grep -v "/tmp:/www/data" | sed 's/bind//g' | grep -Eo "\-v .*:.*" | tr '\n' ' ')"
    para_n="$(docker inspect --format='{{range $m, $conf := .NetworkSettings.Networks}}--network={{$m}}{{end}}' $xiaoya_name | grep -Eo "\-\-network=host")"
    tag="latest"
    if [ "$para_n"x != x ];then
        tag="hostmode"
    fi
    para_p="$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}~{{$p}}{{$conf}} {{end}}' $xiaoya_name | tr '~' '\n' | tr '/' ' ' | tr -d '[]{}' | awk '{printf("-p %s:%s\n",$3,$1)}' | grep -Eo "\-p [0-9]{1,10}:[0-9]{1,10}" | tr '\n' ' ')"
    para_i="$(get_docker_info $xiaoya_name | awk '{print $2}'):$tag"
    para_e="$(docker inspect --format='{{range $p, $conf := .Config.Env}}~{{$conf}}{{end}}' $xiaoya_name 2>/dev/null | sed '/^$/d' | tr '~' '\n' | sed '/^$/d' | awk '{printf("-e \"%s\"\n",$0)}' | tr '\n' ' ')"
    docker pull "$para_i" 2>&1
    cur_image=$(get_docker_info $xiaoya_name | awk '{print $3}')
    latest_image=$(docker images --no-trunc | tail -n +2 | tr ':' ' ' | awk '{printf("%s:%s %s\n",$1,$2,$4)}' | grep "$para_i" | awk '{print $2}')
    
    if [ -z "$(echo "~$para_v" | grep ":/www/data")" ];then
        para_v="$para_v"" -v $data_dir:/www/data"
        force_upgrade=true
    fi

    if [ "$cur_image"x != "$latest_image"x ] || [ "$force_upgrade"x = "true"x ];then
        echo "升级小雅到最新版本"
        docker rm -fv "$xiaoya_name"
        eval "$(echo docker run -d "$para_n" "$para_v" "$para_p" "$para_e" --restart=always --name="$xiaoya_name" "$para_i")"
        docker rmi -f $(docker images | grep "$(echo $para_i | awk -F: '{print $1}')" | grep none | grep -Eo "[0-9a-f]{6,128}") >/dev/null 2>&1
    else
        echo "重启小雅生效配置"
        docker restart $xiaoya_name
    fi
}

for i in $(get_xiaoya); do
    init_para $i
    config
    if [ "$1"x != "--no-upgrade"x ];then
        update_xiaoya
    fi
done

