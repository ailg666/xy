#!/bin/bash
docker run -d --name emby -v /etc/nsswitch.conf:/etc/nsswitch.conf \
-v /volume1/docker/embymeitiku/config:/config \
-v /volume1/docker/embymeitiku/xiaoya:/media \
-e LANG=C.UTF-8 \
--user 0:0 \
--net=host \
--device /dev/dri:/dev/dri \
--privileged --add-host="xiaoya.host:127.0.0.1" --restart always amilys/embyserver:4.8.0.56