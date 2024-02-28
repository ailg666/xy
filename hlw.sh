#!/usr/bin/bash
docker run -d --name emby -v /etc/nsswitch.conf:/etc/nsswitch.conf \
-v /mnt/media_rw/d48ded09-158b-4536-b78b-0279c6936327/.ugreen_nas/312373/Docker/emby-xy/config:/config \
-v /mnt/media_rw/d48ded09-158b-4536-b78b-0279c6936327/.ugreen_nas/312373/Docker/emby-xy/xiaoya:/media \
--user 0:0 \
-p 9096:8096 \
-p 9920:8920 \
-p 1909:1900/udp \
-p 7399:7359/udp \
--device /dev/dri:/dev/dri \
--privileged --add-host="xiaoya.host:192.168.0.105" --restart always amilys/embyserver:4.8.0.56