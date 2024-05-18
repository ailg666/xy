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

diy_img() {
		while :; do
			read -erp $'\033[1;33m请输入您要扩容镜像的完整路径（如：/volume1/emby-img/emby-ailg.img）：\033[0m\n' img_path
			if [[ -f ${img_path} ]]; then
				break
			else
				ERROR "您输入的镜像文件不存在，请重新输入或按CTRL+C退出！"
			fi
		done
		diy_path
	}

	diy_path() {
		while :; do
			read -erp $'\033[1;33m请输入您要扩容镜像的挂载路径（即emby的媒体库路径，如：/volume3/emby-xy）：\033[0m\n' img_mount
			if ! [[ -d ${img_mount} ]]; then
				ERROR "您输入的挂载目录不存在，请重新输入或按CTRL+C退出！"
			elif [[ "$(ls -A "${img_mount}")" ]]; then
				umount ${img_mount}
				[[ "$(ls -A "${img_mount}")" ]] && ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出" || break
			else
				break
			fi
		done
	}

	get_img(){
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
				loop_device=$(echo "$line" | awk '{print $1}')
				_mount_path=$(mount | grep -E "${loop_device}" | awk '{print $3}')
				_img_path=$(echo "$line" | awk '{print $6}')
				if [ ! -z "${_mount_path}" ];then
					img_list[$index]=${_img_path}
					path_list[$index]=${_mount_path}
					echo -e "${Yellow}[$index]\t${_img_path}, 挂载在: ${_mount_path}${NC}"
					((index++))
				fi
			done < <(losetup -l | grep -E "\b$img\b")
		done
		echo -e "${Yellow}[$index]\t手动输入${NC}"

		if ! $results_found; then
			echo "未检测到您安装的老G版镜像，请手动输入！"
			diy_img
		else
			while :; do
				read -erp "请输入您要扩容的镜像序号: " img_index
				if [ "$img_index" -eq "$((index))" ]; then
					diy_img
					break
				elif [ "$img_index" -ge 1 ] && [ "$img_index" -le "$((index - 1))" ]; then
					img_mount=${path_list[$img_index]}
					img_path=${img_list[$img_index]}
					break
				else
					ERROR "您输入的序号不正确，请重新输入！"
				fi
			done
		fi
	}

	if [ -f /etc/synoinfo.conf ];then
		OSNAME='synology'
	elif [ -f /etc/unraid-version ];then
		OSNAME='unraid'
	elif command -v crontab >/dev/null 2>&1 && ps -ef | grep '[c]rond' >/dev/null 2>&1; then
		OSNAME='other'
	else
		WARN "您的系统不支持crontab，需要手动配置开机自启挂载，如您不会请用常规方式安装，按CTRL+C退出！"
	fi

    #检查运行参数是否合法
	if [[ "$1" == "-f" ]]; then
		get_img
	elif [[ "$1" == "-m" ]];then
        if [[ -z "$2" ]] || [[ -z "$3" ]]; then
			ERROR "运行方式错误，程序退出！"
			exit 1
		else
			img_path=$2
			img_mount=$3
			if [ ! -f "${img_path}" ];then
				ERROR "文件不存在或处理的文件类型不正确，程序退出！"
				exit 1
			fi
			#! [[ -d ${img_mount} ]] || [ "$(ls -A "${img_mount}")" ] && ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出" && exit 1
			if ! [[ -d ${img_mount} ]]; then
				ERROR "您输入的挂载目录不存在，请重新输入或按CTRL+C退出！"
				exit 1
			elif [[ "$(ls -A "${img_mount}")" ]]; then
				umount ${img_mount}
				[[ "$(ls -A "${img_mount}")" ]] && ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出" && exit 1
			fi
		fi
    else
		if [[ -z "$2" ]]; then
			ERROR "运行方式错误，程序退出！"
			exit 1
		else
			img_path=$1
			img_mount=$2
			if [ ! -f "${img_path}" ];then
				ERROR "文件不存在或处理的文件类型不正确，程序退出！"
				exit 1
			fi
			#! [[ -d ${img_mount} ]] || [ "$(ls -A "${img_mount}")" ] && ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出" && exit 1
			if ! [[ -d ${img_mount} ]]; then
				ERROR "您输入的挂载目录不存在，请重新输入或按CTRL+C退出！"
				exit 1
			elif [[ "$(ls -A "${img_mount}")" ]]; then
				umount ${img_mount}
				[[ "$(ls -A "${img_mount}")" ]] && ERROR "您输入的挂载目录非空，请重新选择或按CTRL+C退出" && exit 1
			fi
		fi
	fi
	#检查名字是否合法
	img_name=$(basename "${img_path}")
	case "${img_name}" in
		"emby-ailg.img" | "emby-ailg.mp4")
			img_size=80269934592
			;;
		"emby-ailg-lite.img" | "emby-ailg-lite.mp4")
			img_size=57982058496
			;;
		"jellyfin-ailg.img" | "jellyfin-ailg.mp4")
			;;
		"jellyfin-ailg-lite.img" | "jellyfin-ailg-lite.mp4")
			;;
		*)
		ERROR "您输入的不是老G的镜像，或已改名，确保文件名正确后重新运行脚本！"
		! mount | grep -qF ${img_mount} && mount $(losetup -j "$img_path" | cut -d: -f1 || losetup -f) ${img_mount}
		exit 1
		;;
	esac

	if [[ "${img_path}" == *.mp4 ]];then
		mv -f "${img_path}" "${img_path%.mp4}.img"
		img_path="${img_path%.mp4}.img"
	fi

    if [ "$1" != "-m" ];then
        INFO "您选择扩容的镜像是：$img_path"
        if [ -z "$3" ];then
            while :;do
                read -erp $'\033[1;33m请输入您要扩容的大小（单位：GB，默认5GB）：\033[0m' expand_size
                expand_size=${expand_size:-5}
                ! [[ $expand_size =~ ^-?[0-9]+$ ]] && ERROR "您输入的数值不正确，请输入整数数字！" && continue
                limit_size=$(($(df ${img_path} | tail -n 1 | awk '{print $4}')/1024/1024*8/10))
                [ "${expand_size}" -le "${limit_size}" ] && break
                ERROR "您输入的数值不正确，不能超过${limit_size}，即：剩余可用空间的80%，请重新输入！"
            done
        else
            expand_size=$3
            if ! [[ $expand_size =~ ^-?[0-9]+$ ]];then
                ERROR "您输入的数值不正确，请输入整数数字！"
                ! mount | grep -qF ${img_mount} && mount $(losetup -j "$img_path" | cut -d: -f1 || losetup -f) ${img_mount}
                exit 1
            else
				limit_size=$(($(df ${img_path} | tail -n 1 | awk '{print $4}')/1024/1024*8/10))
				[ "${expand_size}" -gt "${limit_size}" ] && ERROR "您输入的数值不正确，不能超过${limit_size}，即：剩余可用空间的80%，程序退出！" && exit 1
			fi
        fi
        while read container_id; do
            docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' $container_id | grep -E "${img_mount}/xiaoya\b" | grep -q ' /media'
            if [ $? -eq 0 ]; then
                emby_name=$(docker ps -a --format '{{.Names}}' --filter "id=$container_id")
                break
            fi
        done < <(docker ps -a --no-trunc --filter "ancestor=emby/embyserver:4.8.0.56" --filter "ancestor=amilys/embyserver:4.8.0.56" --format '{{.ID}}')

        docker ps | grep -qF "$emby_name" && docker stop "$emby_name" && shut_emby=true
        if mount | grep -qF "$img_mount";then
            umount $img_mount
            [ ! -z "$(mount | grep -E "$img_mount")" ] && ERROR "${img_mount}卸载失败，请检查并自行终止该文件夹进程占用后，重新运行脚本！" && exit 1
        fi

        INFO "正在为${img_path}扩容，请耐心等待……"
        #dd if=/dev/zero bs=1G count=5 >> ${img_path}
        org_size=$(du -b ${img_path} | cut -f1)
        if [ "${expand_size}" -ge 0 ];then
            truncate -s +${expand_size}G ${img_path}
        else
            new_block=$(((org_size+${expand_size}*1024*1024*1024-10000000)/4096))
            new_size=$((${new_block}*4096+10000000))
            loop_device=$(losetup -j "$img_path" | cut -d: -f1)
            if [ ! -z "${loop_device}" ];then
                mount | grep -q "${loop_device}" && umount "${loop_device}"
                [ ! -z "${loop_device}" ] && losetup -d "${loop_device}"
            fi
            loop_device=$(losetup -f)
            [ $? -eq 0 ] && losetup -o 10000000 ${loop_device} ${img_path}
            [ $? -eq 0 ] && e2fsck -f -y ${loop_device} >/dev/null 2>&1
            [ $? -eq 0 ] && resize2fs ${loop_device} ${new_block} >> /tmp/exp_ailg.log 2>&1 
            [ $? -eq 0 ] && truncate -s ${new_size} ${img_path}
        fi
        loop_device=$(losetup -j "$img_path" | cut -d: -f1)
        [ ! -z "${loop_device}" ] && mount | grep -q "${loop_device}" && umount "${loop_device}"
        for i in {1..3};do
            [ ! -z "${loop_device}" ] && losetup -d "${loop_device}" && sleep 1
            loop_device=$(losetup -j "$img_path" | cut -d: -f1)
        done

        loop_device=${loop_device:-$(losetup -f)}
        [ $? -eq 0 ] && losetup -o 10000000 ${loop_device} ${img_path}
        #[ "$flag" -eq 0 ] && e2fsck -f -y ${loop_device} >/dev/null 2>&1
        e2fsck -f -y ${loop_device} | awk 'END{print}' | grep -qF '/19936553' >/dev/null 2>&1
		if [ $? -ne 0 ];then
            ERROR "文件系统检查更新失败，请重启设备后重试"
            INFO "正在恢复原镜像大小……"
            truncate -s ${org_size} ${img_path}
            ! mount | grep -qF ${img_mount} && mount $(losetup -j "$img_path" | cut -d: -f1 || losetup -f) ${img_mount}
            exit 1
        else
            resize2fs ${loop_device} >> /tmp/exp_ailg.log 2>&1
		fi
        INFO "操作完成，请检查容量是否正常！"
        mount ${loop_device} ${img_mount} && [ "${shut_emby}" ] && INFO "正在为您启动关闭的emby容器" && docker start "${emby_name}"
    else
		loop_device=$(losetup -j "$img_path" | cut -d: -f1)
        [ ! -z "${loop_device}" ] && mount | grep -q "${loop_device}" && umount "${loop_device}"
        for i in {1..3};do
            [ ! -z "${loop_device}" ] && losetup -d "${loop_device}" && sleep 1
            loop_device=$(losetup -j "$img_path" | cut -d: -f1)
        done
        loop_device=${loop_device:-$(losetup -f)}
        [ $? -eq 0 ] && losetup -o 10000000 ${loop_device} ${img_path}
        mount ${loop_device} ${img_mount}
	    [ $? -eq 0 ] && INFO "${img_path}已成功挂载到${img_mount}目录"
		COMMAND="/usr/bin/exp_ailg -m \"$img_path\" \"$img_mount\""
		if [[ $OSNAME == "synology" ]];then
			if ! grep -qF -- "$COMMAND" /etc/rc.local; then
				cp -f /etc/rc.local /etc/rc.local.bak
				sed -i '/exp_ailg/d' /etc/rc.local
				if grep -q 'exit 0' /etc/rc.local; then
					sed -i "/exit 0/i\/usr/bin/exp_ailg -m \"$img_path\" \"$img_mount\"" /etc/rc.local
				else
					echo -e "/usr/bin/exp_ailg -m \"$img_path\" \"$img_mount\"" >> /etc/rc.local
				fi
			fi
        elif [[ $OSNAME == "unraid" ]];then
            if ! grep -qF -- "$COMMAND" /boot/config/go; then
				echo -e "/usr/bin/exp_ailg -m \"$img_path\" \"$img_mount\"" >> /boot/config/go
			fi
        elif [[ $OSNAME == "other" ]];then
            CRON="@reboot /usr/bin/exp_ailg -m "$img_path" "$img_mount""
            crontab -l | grep -v exp_ailg > /tmp/cronjob.tmp
            echo -e "${CRON}" >> /tmp/cronjob.tmp
            crontab /tmp/cronjob.tmp
        else
            WARN "以下命令请自行配置开机自启动：${Yellow}/usr/bin/exp_ailg -m "$img_path" "$img_mount"${NC}"
        fi	
    fi
