#!/bin/bash

function xy_emby_sync() {
    
    declare -a DIRS=(
        "测试/"
        "动漫/"
        "每日更新/"
        "电影/"
        "电视剧/"
        "纪录片/"
        "纪录片（已刮削）/"
        "综艺/"
        "音乐/"
        "📺画质演示测试（4K，8K，HDR，Dolby）/"
    )

    declare -a DEFAULT_DIRS=(
        "每日更新/"
        "纪录片（已刮削）/"
    )

    declare -a status_keys
    declare -a status_values

    sync_interval=""
    rebuild_db_flag=false # Use boolean flag internally
    cron_env_var=""
    rebuild_env_var=""
    schedule_mode=""
    cron_expression=""


    find_key_index() {
        local search_key="$1"
        local i=0
        
        for key in "${status_keys[@]}"; do
            if [[ "$key" == "$search_key" ]]; then
                echo $i
                return 0
            fi
            i=$((i + 1))
        done
        
        echo -1  # 如果没找到返回-1
        return 1
    }

    get_status() {
        local key="$1"
        local index=$(find_key_index "$key")
        
        if [[ $index -ge 0 ]]; then
            echo "${status_values[$index]}"
        else
            echo "0"  # Return 0 if key doesn't exist yet
        fi
    }

    set_status() {
        local key="$1"
        local value="$2"
        local index=$(find_key_index "$key")
        
        if [[ $index -ge 0 ]]; then
            status_values[$index]=$value
        else
            status_keys+=("$key")
            status_values+=("$value")
        fi
    }

    initialize_status() {
        status_keys=()
        status_values=()
        
        for dir in "${DIRS[@]}"; do
            set_status "$dir" 0
        done
        set_status "Default" 0
        set_status "All" 0

        select_default
    }

    select_default() {
        for dir in "${DIRS[@]}"; do
            set_status "$dir" 0
        done
        for dir in "${DEFAULT_DIRS[@]}"; do
            set_status "$dir" 1
        done
        set_status "Default" 1
        set_status "All" 0
    }

    select_all() {
        for dir in "${DIRS[@]}"; do
            set_status "$dir" 1
        done
        set_status "Default" 0
        set_status "All" 1
    }

    deselect_all() {
        for dir in "${DIRS[@]}"; do
            set_status "$dir" 0
        done
        set_status "Default" 0
        set_status "All" 0
    }

    update_special_statuses() {
        local all_selected=1
        local default_match=1
        local has_selection=0

        for dir in "${DIRS[@]}"; do
            if [[ $(get_status "$dir") -eq 0 ]]; then
                all_selected=0
            else
                has_selection=1 # Mark if at least one item is selected
            fi
        done

        if [[ $has_selection -eq 0 ]]; then # If nothing is selected
            default_match=0
        else
            for dir in "${DIRS[@]}"; do
                local is_default=0
                for default_dir in "${DEFAULT_DIRS[@]}"; do
                    if [[ "$dir" == "$default_dir" ]]; then
                        is_default=1
                        break
                    fi
                done

                local current_status=$(get_status "$dir")

                if ( [[ $is_default -eq 1 ]] && [[ $current_status -eq 0 ]] ) || \
                ( [[ $is_default -eq 0 ]] && [[ $current_status -eq 1 ]] ); then
                    default_match=0
                    break
                fi
            done
        fi

        set_status "All" $all_selected
        set_status "Default" $default_match
    }

    show_menu() {
        clear
        echo "请选择您需要同步的目录："
        echo "---------------------------------------------"
        local i=0
        for dir in "${DIRS[@]}"; do
            local index=$((i + 1))
            local status_char=" "
            if [[ $(get_status "$dir") -eq 1 ]]; then
                status_char="✓"
            fi
            printf "\033[32m%2d) [%s] %s\033[0m\n" "$index" "$status_char" "$dir"
            i=$((i + 1))
        done

        echo "---------------------------------------------"
        local default_index=$(( ${#DIRS[@]} + 1 ))
        local all_index=$(( ${#DIRS[@]} + 2 ))
        local status_char_def=" "
        local status_char_all=" "

        if [[ $(get_status "Default") -eq 1 ]]; then status_char_def="✓"; fi
        if [[ $(get_status "All") -eq 1 ]]; then status_char_all="✓"; fi

        printf "\033[32m%2d) [%s] %s\033[0m\n" "$default_index" "$status_char_def" "默认 (选择: ${DEFAULT_DIRS[*]})"
        printf "\033[32m%2d) [%s] %s\033[0m\n" "$all_index" "$status_char_all" "全部"

        echo "---------------------------------------------"
        echo -e "\033[32m 0) 确认选择并继续\033[0m"
        echo "---------------------------------------------"
        echo -e "\033[33m提示: 输入数字 (如 1, 3, ${default_index}) 切换选中状态，可输入多个 (用逗号分隔), 输入 0 确认.\033[0m"
    }

    process_selection() {
        local input="$1"
        local default_index=$(( ${#DIRS[@]} + 1 ))
        local all_index=$(( ${#DIRS[@]} + 2 ))
        local individual_toggled=0

        IFS=',' read -ra CHOICES <<< "$input"

        for choice in "${CHOICES[@]}"; do
            choice=$(echo "$choice" | xargs)

            if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                if [[ -n "$choice" ]]; then # Only show error if it's not empty input after trimming
                    echo "无效输入: '$choice'. 请输入数字。"
                    sleep 1
                fi
                continue
            fi

            case $choice in
                0) # Confirm
                    return 1 # Signal to exit the loop
                    ;;
                *) # Directory, Default, or All
                    if [[ $choice -ge 1 && $choice -le ${#DIRS[@]} ]]; then
                        local dir_index=$((choice - 1))
                        local dir_name="${DIRS[$dir_index]}"
                        local current_status=$(get_status "$dir_name")
                        if [[ $current_status -eq 0 ]]; then
                            set_status "$dir_name" 1
                        else
                            set_status "$dir_name" 0
                        fi
                        individual_toggled=1

                    elif [[ $choice -eq $default_index ]]; then
                        if [[ $(get_status "Default") -eq 0 ]]; then
                            select_default
                        else
                            deselect_all
                        fi

                    elif [[ $choice -eq $all_index ]]; then
                        if [[ $(get_status "All") -eq 0 ]]; then
                            select_all
                        else
                            deselect_all
                        fi
                    else
                        echo "无效选项: $choice"
                        sleep 1
                    fi
                    ;;
            esac
        done

        if [[ $individual_toggled -eq 1 ]]; then
            update_special_statuses
        fi

        return 0 # Signal to continue the loop
    }

    initialize_status

    while true; do
        show_menu
        read -p "请输入目录选项: " user_choice
        process_selection "$user_choice"
        if [[ $? -eq 1 ]]; then
            break # Exit loop if process_selection returns 1 (user entered 0)
        fi
    done

    echo "---------------------------------------------"
    echo "========== 设置同步目录 =========="
    echo "---------------------------------------------"
    if [ -n "${image_dir}" ] && [ -n "${emby_img}" ]; then
        mount_path="$image_dir/$emby_img"
    fi
    if [ -n "${mount_path}" ]; then
        echo -e "\033[33m检测到您当前使用的小雅Emby速装镜像为：${mount_path}\033[0m"
        read -p "是否使用该镜像创建小雅爬虫同步？(y/n)" sync_path_choice
        if ! [[ "$sync_path_choice" == [yY] ]]; then
            mount_path=""
            echo -e "\033[31m您选择使用其他img镜像创建小雅Emby爬虫同步，务必将小雅Emby也统一改为此镜像，否则可能运行出错！\033[0m"
        fi
    fi
    if [ -z "${mount_path}" ]; then
        while true; do
            echo -e "\033[33m请输入您要同步的Emby速装镜像的完整路径: \033[0m"
            echo -e "\033[33m注：当前仅支持老G速装镜像，例如：/volume6/test/7/emby-ailg-lite-115-4.9.img\033[0m"
            read -p "请输入: " mount_path
            if [[ -n "$mount_path" ]]; then
                if [[ "$mount_path" =~ \.img$ ]]; then
                    echo -e "\033[32m将使用以下目录/img为您创建小雅Emby爬虫同步: ${mount_path}\033[0m"
                    break
                else
                    echo -e "\033[31m输入错误！请确保输入老G速装Emby的img文件的完整路径，请重新输入.\033[0m"
                    sleep 1
                fi
            else
                echo -e "\033[31m错误: 您没有输入任何内容.\033[0m"
                sleep 1
            fi
        done
    fi
    echo "---------------------------------------------"
    echo "========== 设置同步周期 =========="
    echo "---------------------------------------------"
    echo -e "\033[36m请选择同步调度模式：\033[0m"
    echo -e "\033[32m1) 间隔模式 (CYCLE)\033[0m - 任务结束后间隔指定小时数再次执行"
    echo -e "\033[33m2) 定时模式 (CRON)\033[0m - 使用 crond 表达式在固定时间执行"
    echo ""

    while true; do
        read -p "请选择调度模式 [1-2]: " schedule_choice
        schedule_choice=$(echo "$schedule_choice" | xargs)

        case "$schedule_choice" in
            1)
                schedule_mode="cycle"
                echo -e "\033[32m已选择间隔模式 (CYCLE)\033[0m"
                echo ""
                break
                ;;
            2)
                schedule_mode="cron"
                echo -e "\033[33m已选择定时模式 (CRON)\033[0m"
                echo ""
                break
                ;;
            *)
                echo -e "\033[31m错误: 请输入 1 或 2\033[0m"
                ;;
        esac
    done

    if [[ "$schedule_mode" == "cycle" ]]; then
        while true; do
            read -p "请输入同步间隔 (单位: 小时, 必须为 >= 12 的整数): " sync_interval_input
            sync_interval_input=$(echo "$sync_interval_input" | xargs)

            if [[ ! "$sync_interval_input" =~ ^[0-9]+$ ]]; then
                echo -e "\033[31m错误: 输入 '$sync_interval_input' 不是一个有效的整数. 请重新输入.\033[0m"
                continue
            fi

            if [[ "$sync_interval_input" -lt 12 ]]; then
                echo -e "\033[31m错误: 同步间隔必须大于或等于 12 小时. 您输入的是 '$sync_interval_input'. 请重新输入.\033[0m"
                continue
            fi

            echo -e "\033[32m同步间隔设置为: ${sync_interval_input} 小时\033[0m"
            sleep 1
            break
        done
    else
        echo -e "\033[36m请输入 crond 表达式\033[0m"
        echo -e "\033[33m格式说明: 分 时 日 月 周"
        echo -e "示例:"
        echo -e "  每天凌晨 2 点执行: \033[32m0 2 * * *\033[0m"
        echo -e "  每 12 小时执行一次: \033[32m0 */12 * * *\033[0m"
        echo -e "  每周日凌晨 3 点执行: \033[32m0 3 * * 0\033[0m"
        echo -e "  每月 1 号凌晨 1 点执行: \033[32m0 1 1 * *\033[0m"
        echo ""

        while true; do
            read -p "请输入 crond 表达式: " cron_expression
            cron_expression=$(echo "$cron_expression" | xargs)

            if [[ ! "$cron_expression" =~ ^[0-9*,/\-]+\ [0-9*,/\-]+\ [0-9*,?\-]+\ [0-9*,/\-]+\ [0-9*,?\-]+$ ]]; then
                echo -e "\033[31m错误: crond 表达式格式不正确. 请重新输入.\033[0m"
                echo -e "\033[33m正确格式示例: 0 2 * * * (每天凌晨 2 点)\033[0m"
                continue
            fi

            IFS=' ' read -ra FIELDS <<< "$cron_expression"
            minute_field="${FIELDS[0]}"
            hour_field="${FIELDS[1]}"
            day_field="${FIELDS[2]}"
            month_field="${FIELDS[3]}"
            weekday_field="${FIELDS[4]}"

            if [[ "$minute_field" == *\* && "$minute_field" != */* ]] || \
               [[ "$hour_field" == *\* && "$hour_field" != */* ]] || \
               [[ "$day_field" == *\* && "$day_field" != */? ]] || \
               [[ "$month_field" == *\* && "$month_field" != */* ]] || \
               [[ "$weekday_field" == *\* && "$weekday_field" != */? ]]; then
                :
            fi

            echo -e "\033[32mcrond 表达式设置为: ${cron_expression}\033[0m"
            echo -e "\033[36m将按照 crond 表达式定时执行同步任务\033[0m"
            sleep 1
            break
        done
    fi
    echo "---------------------------------------------"
    echo "========== 设置其他选项 =========="
    echo "---------------------------------------------"
    read -p "是否重建本地数据库? (y/n): " rebuild_choice
    if [[ "$rebuild_choice" == [yY] ]]; then
        rebuild_env_var="--rebuild-db"
        echo -e "\033[32m您选择了重建本地数据库.\033[0m"
    else
        rebuild_env_var=""
        echo -e "\033[33m您选择了不重建本地数据库.\033[0m"
    fi
    echo "---------------------------------------------"
    echo -e "\033[33m清理模式默认开启，同步执行后，会删除远程没有但本地有的文件和无效目录！\033[0m"
    read -p "是否关闭清理模式（默认清理）? (y/n): " clean_choice
    if [[ "$clean_choice" == [yY] ]]; then
        clean_env_var="--no-clean"
        echo -e "\033[32m您选择了关闭清理模式.\033[0m"
    else
        clean_env_var=""
        echo -e "\033[33m将为您开启清理模式.\033[0m"
    fi
    echo "---------------------------------------------"
    echo -e "\033[33m当默认模式无法连接同步站源时，可尝试自定义DNS\033[0m"
    read -p "是否使用自定义DNS? (y/n): " dns_choice
    if [[ "$dns_choice" == [yY] ]]; then
        while true; do
            echo -e "\033[33m填写您要使用的自定义DNS（完整URL或IP）: \033[0m"
            echo -e "\033[33m例如：https://dns.alidns.com/dns-query 或 8.8.8.8\033[0m"
            read -p "请输入: " dns_input
            if [[ -n "$dns_input" ]]; then
                if [[ "$dns_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    dns_env_var="--dns-enabled --dns-type UDP --dns-server ${dns_input}"
                    echo -e "\033[32m您选择了UDP自定义DNS: ${dns_input}\033[0m"
                    break
                elif [[ "$dns_input" =~ ^https?:// ]]; then
                    dns_env_var="--dns-enabled --dns-type DOH --dns-server ${dns_input}"
                    echo -e "\033[32m您选择了DOH自定义DNS: ${dns_input}\033[0m"
                    break
                else
                    echo -e "\033[31m错误: 输入格式不正确. 请输入有效的IP地址或以http/https开头的URL.\033[0m"
                    sleep 1
                fi
            else
                echo -e "\033[31m错误: 您没有输入任何内容.\033[0m"
                sleep 1
            fi
        done
    else
        dns_env_var=""
        echo -e "\033[33m将为您使用默认DNS.\033[0m"
    fi

    if [[ -n "${container_mode}" ]]; then
        echo -e "\n\033[1;36m=== 容器类型配置 ===\033[0m"
        echo -e "\033[32m使用预设模式: ${container_mode}\033[0m"
    else
        echo -e "\n\033[1;36m=== 容器类型配置 ===\033[0m"
        echo -e "请选择您的媒体服务器类型："
        echo -e "\033[32m1. Emby\033[0m"
        echo -e "\033[33m2. Jellyfin\033[0m"
        
        local mode_choice=""
        while true; do
            read -p "请输入选择 [1-1，默认1]: " mode_choice
            mode_choice=${mode_choice:-1}
            
            case "$mode_choice" in
                1)
                    container_mode="emby"
                    echo -e "\033[32m已选择: Emby模式\033[0m"
                    break
                    ;;
                2)
                    container_mode="jellyfin" 
                    echo -e "\033[33m已选择: Jellyfin模式\033[0m"
                    break
                    ;;
                *)
                    echo -e "\033[31m错误: 请输入1或2\033[0m"
                    ;;
            esac
        done
    fi

    selected_dirs_array=()
    for dir in "${DIRS[@]}"; do
        if [[ $(get_status "$dir") -eq 1 ]]; then
            selected_dirs_array+=("$dir")
        fi
    done

    output_string=$(printf "%s," "${selected_dirs_array[@]}")
    output_string=${output_string%,}

    docker_emd_names="$(docker ps -a | grep -E 'ailg/xy-emd' | awk '{print $NF}')"
    
    for emd_name in $docker_emd_names; do
        if [[ "${container_mode}" == "jellyfin" ]]; then
            if [[ "$emd_name" == "xy-emd-jf" ]]; then
                docker rm -f "$emd_name"
                echo -e "\033[33m已清理旧容器：$emd_name\033[0m"
            elif [[ "$emd_name" != "xy-emd" ]]; then
                docker stop "$emd_name" 2>/dev/null
                echo -e "\033[36m已停止非标准名称容器：$emd_name\033[0m"
            fi
        else
            if [[ "$emd_name" == "xy-emd" ]]; then
                docker rm -f "$emd_name"
                echo -e "\033[33m已清理旧容器：$emd_name\033[0m"
            elif [[ "$emd_name" != "xy-emd-jf" ]]; then
                docker stop "$emd_name" 2>/dev/null
                echo -e "\033[36m已停止非标准名称容器：$emd_name\033[0m"
            fi
        fi
    done
    local emd_image=""
    if [[ $(uname -m) == "armv7l" ]]; then
        emd_image="ailg/xy-emd:arm7-latest"
    else
        emd_image="ailg/xy-emd:latest"
    fi

    local mode_env_var=""
    local container_name=""
    if [[ "${container_mode}" == "emby" ]]; then
        mode_env_var="-e MODE=emby"
        container_name="xy-emd"
        echo -e "\033[32mxy-emd将使用Emby模式，容器名：${container_name}\033[0m"
    elif [[ "${container_mode}" == "jellyfin" ]]; then
        mode_env_var="-e MODE=jellyfin"
        container_name="xy-emd-jf"
        echo -e "\033[33mxy-emd将使用Jellyfin模式，容器名：${container_name}\033[0m"
    else
        mode_env_var="-e MODE=emby"
        container_name="xy-emd"
        echo -e "\033[33mxy-emd将使用默认emby模式，容器名：${container_name}\033[0m"
    fi

    if docker_pull "${emd_image}"; then
        img_parent_dir=$(dirname "${mount_path}")

        local schedule_env_var=""
        if [[ "$schedule_mode" == "cron" ]]; then
            schedule_env_var="-e CRON=${cron_expression}"
            echo -e "\033[36m使用 CRON 模式启动容器: ${cron_expression}\033[0m"
        else
            schedule_env_var="-e CYCLE=${sync_interval_input}"
            echo -e "\033[36m使用 CYCLE 模式启动容器: ${sync_interval_input} 小时\033[0m"
        fi

        echo -e "\033[36m[DEBUG] 镜像名称: ${emd_image}\033[0m"

        docker run -d --name "${container_name}" ${schedule_env_var} ${mode_env_var} \
            -v "${mount_path}:/media.img" -v "${img_parent_dir}:/ailg" --privileged --net=host --restart=always \
            "${emd_image}" --dirs "${output_string}" ${rebuild_env_var} ${clean_env_var} ${dns_env_var}
        echo -e "小雅Emby爬虫G-Box专用版安装成功了！"
        return 0
    else
        echo "镜像拉取失败，安装失败了！"
        return 1
    fi
}
