#!/bin/bash

mode=$(uname -m)
case $mode in
    x86_64)
        exp_x86 "$1" "$2" "$3"
        ;;
    armv7l | aarch64)
        exp_arm "$1" "$2" "$3"
        ;;
    *)
        echo -e  "\033[1;31m不支持您设备的CPU架构，程序退出！\033[0m" || exit 1
        ;;
esac
