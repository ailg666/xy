#!/bin/bash

# 小雅分享资源选择功能
# 使用方法：
# 1. source share_resources.sh
# 2. select_share_resources "$config_dir"

select_share_resources() {
    local config_dir="$1"
    
    # 定义资源选项和文件名
    share_names=("pikpak" "115" "quark")
    share_descriptions=("小雅pikpak分享资源" "小雅115分享资源" "小雅夸克分享资源")
    
    # 初始化选择状态，默认都不选
    selected_pikpak=0
    selected_115=0
    selected_quark=0
    selected_none=0
    selected_all=0
    
    # 获取选中状态
    get_selected_status() {
        local key=$1
        case $key in
            "pikpak") echo $selected_pikpak ;;
            "115") echo $selected_115 ;;
            "quark") echo $selected_quark ;;
            "none") echo $selected_none ;;
            "all") echo $selected_all ;;
        esac
    }
    
    # 设置选中状态
    set_selected_status() {
        local key=$1
        local value=$2
        case $key in
            "pikpak") selected_pikpak=$value ;;
            "115") selected_115=$value ;;
            "quark") selected_quark=$value ;;
            "none") selected_none=$value ;;
            "all") selected_all=$value ;;
        esac
    }
    
    # 显示选择菜单的函数
    show_share_menu() {
        clear
        echo "请选择需要加载的小雅分享资源："
        echo "-------------------------------"
        for i in {0..2}; do
            local key=${share_names[$i]}
            local status=$(get_selected_status "$key")
            if [ $status -eq 1 ]; then
                echo -e "\033[32m$((i+1))) [✓] ${share_descriptions[$i]}\033[0m"
            else
                echo -e "\033[32m$((i+1))) [ ] ${share_descriptions[$i]}\033[0m"
            fi
        done
        
        # 显示全部不加载选项
        if [ $selected_none -eq 1 ]; then
            echo -e "\033[32m4) [✓] 全部不加载\033[0m"
        else
            echo -e "\033[32m4) [ ] 全部不加载\033[0m"
        fi
        
        # 显示全部加载选项
        if [ $selected_all -eq 1 ]; then
            echo -e "\033[32m5) [✓] 全部加载\033[0m"
        else
            echo -e "\033[32m5) [ ] 全部加载\033[0m"
        fi
        
        echo -e "\033[32m0) 确认并继续\033[0m"
        echo "-------------------------------"
        echo -e "\033[33m提示: 输入数字(如1,2,3)切换选中状态，输入0确认并继续\033[0m"
    }
    
    # 处理用户选择
    process_share_selection() {
        local choice=$1
        
        # 处理多个选择（用逗号分隔）
        IFS=',' read -ra CHOICES <<< "$choice"
        for choice in "${CHOICES[@]}"; do
            # 去除空格
            choice=$(echo $choice | tr -d ' ')
            
            case $choice in
                1|2|3)
                    local key_index=$((choice-1))
                    local key=${share_names[$key_index]}
                    local current_status=$(get_selected_status "$key")
                    
                    # 切换选中状态
                    if [ $current_status -eq 0 ]; then
                        set_selected_status "$key" 1
                    else
                        set_selected_status "$key" 0
                    fi
                    
                    # 更新全部不加载和全部加载的状态
                    update_all_none_status
                    ;;
                4) # 全部不加载
                    if [ $selected_none -eq 0 ]; then
                        # 设置全部不加载
                        for key in "${share_names[@]}"; do
                            set_selected_status "$key" 0
                        done
                        set_selected_status "none" 1
                        set_selected_status "all" 0
                    else
                        # 取消全部不加载
                        set_selected_status "none" 0
                    fi
                    ;;
                5) # 全部加载
                    if [ $selected_all -eq 0 ]; then
                        # 设置全部加载
                        for key in "${share_names[@]}"; do
                            set_selected_status "$key" 1
                        done
                        set_selected_status "all" 1
                        set_selected_status "none" 0
                    else
                        # 取消全部加载
                        set_selected_status "all" 0
                    fi
                    ;;
                0) # 确认选择
                    return 1
                    ;;
                "")
                    # 空输入，直接返回
                    ;;
                *)
                    echo "无效选择: $choice，请重试"
                    sleep 1
                    ;;
            esac
        done
        return 0
    }
    
    # 更新全部加载和全部不加载的状态
    update_all_none_status() {
        # 检查是否全部选中
        local all_selected=1
        local all_unselected=1
        
        for key in "${share_names[@]}"; do
            local status=$(get_selected_status "$key")
            if [ $status -eq 0 ]; then
                all_selected=0
            else
                all_unselected=0
            fi
        done
        
        # 更新状态
        if [ $all_selected -eq 1 ]; then
            set_selected_status "all" 1
            set_selected_status "none" 0
        elif [ $all_unselected -eq 1 ]; then
            set_selected_status "none" 1
            set_selected_status "all" 0
        else
            set_selected_status "all" 0
            set_selected_status "none" 0
        fi
    }
    
    # 检查文件是否有效
    check_file_valid() {
        local file=$1
        # 检查文件是否存在且不是HTML错误页面
        if [ -f "$file" ]; then
            # 检查文件是否包含HTML错误标记
            if grep -q "<title>404 Not Found</title>" "$file" || grep -q "<html" "$file"; then
                return 1  # 文件无效
            else
                return 0  # 文件有效
            fi
        else
            return 1  # 文件不存在
        fi
    }
    
    # 下载选中的资源
    download_selected_resources() {
        local base_url="https://ailg.ggbond.org"
        
        # 下载选中的资源
        for i in {0..2}; do
            local key=${share_names[$i]}
            local status=$(get_selected_status "$key")
            if [ $status -eq 1 ]; then
                INFO "正在下载${share_descriptions[$i]}..."
                local file_name="${key}share_list.txt"
                curl -s -o "$config_dir/$file_name" "$base_url/$file_name"
                
                # 检查下载的文件是否有效
                if check_file_valid "$config_dir/$file_name"; then
                    INFO "成功下载${share_descriptions[$i]}"
                    chmod 777 "$config_dir/$file_name"
                else
                    WARN "下载${share_descriptions[$i]}失败，获取到无效文件"
                    # 删除无效文件
                    [ -f "$config_dir/$file_name" ] && rm -f "$config_dir/$file_name" &>/dev/null
                fi
            else
                [ -f "$config_dir/$file_name" ] && rm -f "$config_dir/$file_name" &>/dev/null
            fi
        done
    }
    
    # 显示交互式菜单
    while true; do
        show_share_menu
        read -p "请输入选项: " choice
        process_share_selection "$choice"
        if [ $? -eq 1 ]; then
            break
        fi
    done
    
    # 下载选中的资源
    download_selected_resources
} 