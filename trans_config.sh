#!/bin/bash
function13() {
	clear
	echo -e "\e[33m"
	echo -e "—————————————————————————————————使  用  说  明———————————————————————————————————"
	echo -e "1、本脚本为小雅EMBY全家桶的定制化安装脚本，使用于群晖系统环境，不保证其他系统通用；"
	echo -e "\n"
	echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
	echo -e "\n"
	echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行脚本，按CTRL+C立即退出；"
	echo -e "\n"
	echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：http://qr61.cn/oVTrfl/q9n5NeV"
	echo -e "——————————————————————————————————————————————————————————————————————————————————"
	echo -e "\e[0m"
    
    read -ep "请输入您要转换config的小雅媒体库路径：" media_dir
    if [[ -d "$media_dir/config" && -f "$media_dir/config/data/library.db" ]]; then
        echo -e "\033[1;37m您选择转换config的小雅媒体库路径是: \033[1;35m$media_dir\033[0m"
        echo -e "\n"
        read -ep "确认就按Y/y：" f13_select_1
        if ! [[ $f13_select_1 == [Yy] ]]; then
			echo "选择错误，程序将退出。"
        	exit 1
        fi
    else
        echo "$media_dir/config/data/library.db数据库文件不存在！"
        echo -e "\n"
        echo -e "\033[1;31m您选择的个目录不正确，程序退出。\033[0m"
        exit 1
    fi
    mv $media_dir/config/data/library.db $media_dir/config/data/library.org.db
    chmod 777 $media_dir/config/data/library.org.db
    curl -o $media_dir/config/data/library.db https://xy.ggbond.org/xy/library.lc.db
    curl -o $media_dir/temp.sql	https://xy.ggbond.org/xy/all.sql
	docker run -it --security-opt seccomp=unconfined --rm --net=host -v $media_dir:/media -e LANG=C.UTF-8  ailg/ggbond:latest sqlite3 /media/config/data/library.db ".read /media/temp.sql"
	#rm -f $media_dir/temp.sql
}

function13


