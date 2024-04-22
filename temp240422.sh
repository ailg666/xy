#!/bin/bash
#运行环境初始化
# shellcheck shell=bash
# shellcheck disable=SC2086
# shellcheck disable=SC1091
# shellcheck disable=SC2154
# shellcheck disable=SC2162
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

cd /etc/nginx/http.d
curl -O https://xy.ggbond.org/xy/ep.test
mv externalPlayer_jf.js  externalPlayer_jf.js.bak
mv ep.test externalPlayer_jf.js