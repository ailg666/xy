#!/bin/bash
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

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

img_expand(){
	WARN "如果您已经修改了老G版镜像的默认名字，请勿使用本脚本，或改回原名后重新运行！按任意键继续，或按CTRL+C退出！"
	read -n 1
	declare -a img_list
	declare -a path_list

	imgs=("emby-ailg.img" "emby-ailg-lite.img" "jellyfin-ailg.img" "jellyfin-ailg-lite.img")

	index=1
	results_found=false
	for img in "${imgs[@]}"; do
		while IFS= read -r line; do
			results_found=true
			_mount_path=$(echo "$line" | awk '{print $3}')
			_img_path=$(echo "$line" | awk '{print $1}')
			img_list[$index]=${_img_path}
			path_list[$index]=${_mount_path}
			echo "[$index]: ${_img_path}, 挂载在: ${_mount_path}"
			((index++))
		done < <(mount | grep -E "\b$img\b")
	done

	if ! $results_found; then
		echo "未检测到您安装的老G版镜像，请手动输入！"
		while :;do
			read -erp $'\033[1;33m请输入您要扩容镜像的完整路径（如：/volume1/emby-img/emby-ailg.img）：\033[0m\n' img_path
			if [[ -f ${img_path} ]];then
				img_name=$(basename "${img_path}")
				case "${img_name}" in
					"emby-ailg.img")
						img_size=80269934592
						;;
					"emby-ailg-lite.img")
						img_size=57982058496
						;;
					"jellyfin-ailg.img")
						;;
					"jellyfin-ailg-lite.img")
						;;
					*)
						ERROR "您输入的不是老G的镜像，或已改名，确保文件名正确后重新运行脚本！"
						exit 1
						;;
				esac
			else
				echo "The specified path '${img_path}' is not a file."
			fi
				 [[ "$(ls -A ${img_path}" ]] break || ERROR "输入错误！镜像文件不存在！请重新输入"
		done
		while :;do
			read -erp $'\033[1;33m请输入您要扩容镜像的挂载路径（即emby的媒体库路径，如：/volume3/emby-xy）：\033[0m\n' img_mount
			[[ -d ${img_mount} ]] && break || ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出"
		done
	else
		read -erp "请输入您要扩容的镜像序号: " img_index
		img_mount=${path_list[$img_index]}
		img_path=${img_list[$img_index]}
		img_name=$(basename "${img_path}")
	fi

	INFO "您选择扩容的镜像是：$img_path"
	read -erp $'\033[1;33m请输入您要扩容的大小（单位：GB，默认5GB）：\033[0m' expand_size
	expand_size=${expand_size:-5}
	docker ps -a --no-trunc --filter "ancestor=emby/embyserver:4.8.0.56" --filter "ancestor=amilys/embyserver:4.8.0.56" --format '{{.ID}}' | while read container_id; do
		docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' $container_id | grep -E "${img_mount}/xiaoya\b" | grep -q ' /media'
		if [ $? -eq 0 ]; then
			emby_name=$(docker ps -a --format '{{.Names}}' --filter "id=$container_id")
			break
		fi
	done
	docker stop $emby_name
	sleep 1
	umount $img_mount
	[ ! -z "$(mount | grep -E "$img_mount")" ] && ERROR "${img_mount}卸载失败，请检查并自行终止该文件夹进程占用后，重新运行脚本！" && exit 1

	INFO "正在为${img_path}扩容，请耐心等待……"
	#dd if=/dev/zero bs=1G count=5 >> ${img_path}
	org_size=$(du -b ${img_path} | cut -f1)
	truncate -s +"${expand_size}GB" ${img_path}
	loop_device=$(losetup -j "$img_path" | cut -d: -f1)
	[ ! -z "${loop_device}" ] && umount ${loop_device}
	losetup -d ${loop_device}
	loop_device=${loop_device:-$(losetup -f)}
	losetup -o 10000000 ${loop_device} ${img_path}
	#e2fsck -f -y ${loop_device} 2>&1 | tee /tmp/e2fsck.log
	e2fsck -f -y ${loop_device} 2>/dev/null
	if [ $? -ne 0 ];then
		ERROR "文件系统检查更新失败，请重启设备后重试"
		INFO "正在恢复原镜像大小……"
		truncate -s ${org_size} ${img_path}
	else
		resize2fs ${loop_device}
	fi
	INFO "操作完成!请检查容量是否正常！"
	[ ! -z ${emby_name} ] && INFO "正在为您启动关闭的emby容器" && docker start $emby_name
}
img_expand
