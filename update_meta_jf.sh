#!/bin/bash

if [ -s /etc/xiaoya/docker_address.txt ]; then
	docker_addr=$(head -n1 /etc/xiaoya/docker_address.txt)
else
	echo "请先配置 /etc/xiaoya/docker_address.txt，以便获取docker 地址"
	exit
fi

cd /media/temp || exit

aria2c -o config_jf.mp4 --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/config_jf.mp4"
aria2c -o pikpak_jf.mp4 --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/PikPak_jf.mp4"
aria2c -o all_jf.mp4 --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/all_jf.mp4"

cd /media || exit
rm -rf /media/config
echo "执行解压............"
start_time1=$(date +%s)
7z x -aoa  -bb1 -mmt=16 temp/config_jf.mp4 2>/dev/null

cd /media/xiaoya || exit

7z x -aoa  -bb1 -mmt=16 /media/temp/all_jf.mp4 2>/dev/null
7z x -aoa  -bb1 -mmt=16 /media/temp/pikpak_jf.mp4 2>/dev/null

end_time1=$(date +%s)
total_time1=$((end_time1 - start_time1))
total_time1=$((total_time1 / 60))
echo "解压执行时间：$total_time1 分钟"

#host=$(echo $docker_addr|cut -f1,2 -d:)
echo -e "\033[33m"
echo "刮削数据已经下载解压完成！"
echo -e "\033[0m"
