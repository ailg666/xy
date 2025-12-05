#!/bin/bash
# ---------------------------------------------------------
# 工业级智能硬盘休眠守护进程 (Multi-Drive Adaptive Spindown)
# v3.3 - 参数传递版
# ---------------------------------------------------------
# 
# 用法:
#   方式1 (本地执行):
#     ./hd_sleep.sh "/dev/disk/by-id/ata-XXX" "/dev/disk/by-id/ata-YYY"
#
#   方式2 (远程执行):
#     hd_1="/dev/disk/by-id/ata-XXX"
#     hd_2="/dev/disk/by-id/ata-YYY"
#     curl -sSLf https://ailg.ggbond.org/hd_sleep.sh | bash -s "${hd_1}" "${hd_2}"
#
# ---------------------------------------------------------

# ================= 参数接收 =================
if [ $# -eq 0 ]; then
    echo "❌ [Error] No drive specified!"
    echo ""
    echo "Usage:"
    echo "  $0 <drive_id_1> [drive_id_2] [drive_id_3] ..."
    echo ""
    echo "Example:"
    echo "  $0 /dev/disk/by-id/ata-WDC_WD20SPZX-22UA7T0_WD-WX62E21FN938"
    echo ""
    echo "Remote execution:"
    echo '  curl -sSLf https://ailg.ggbond.org/hd_sleep.sh | bash -s "/dev/disk/by-id/xxx"'
    exit 1
fi

# 从命令行参数构建硬盘列表
TARGET_DRIVES=("$@")

echo "Received ${#TARGET_DRIVES[@]} drive(s) from command line arguments."

# ================= 配置区域 =================

# 基础检查间隔 (秒)
# 建议 60 秒，太短会浪费 CPU，太长会导致休眠延迟
POLL_INTERVAL=60

# 每日最大允许唤醒次数 (超过此数值，当天保持唤醒)
MAX_SPINUPS=3

# ==========================================================

# ================= 前置依赖检查 =================
for cmd in hdparm smartctl awk; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ [Error] Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

# ================= 配置参数验证 =================
if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [ "$POLL_INTERVAL" -lt 10 ]; then
    echo "❌ [Error] POLL_INTERVAL must be a number >= 10 seconds"
    exit 1
fi

if ! [[ "$MAX_SPINUPS" =~ ^[0-9]+$ ]] || [ "$MAX_SPINUPS" -lt 1 ]; then
    echo "❌ [Error] MAX_SPINUPS must be a number >= 1"
    exit 1
fi

# --- 全局变量声明 ---
declare -A drive_status       # 状态: sleeping, active, disabled(熔断)
declare -A drive_spinups      # 当日启停计数
declare -A drive_timeout      # 当前超时时间 (秒)
declare -A drive_idle_sec     # 当前闲置时间 (秒)
declare -A drive_last_io      # 上一次的IO扇区数
declare -A drive_short_name   # 短文件名 (如 sdb)
declare -a VALID_DRIVES       # 有效硬盘列表

last_date=$(date +%F)

# --- 工具函数 ---

# 1. 初始化检查：验证路径并获取短文件名
init_drive() {
    local disk_id="$1"
    
    if [ ! -e "$disk_id" ]; then
        echo "❌ [Error] Invalid path: $disk_id (Skipping)"
        return 1
    fi
    
    # 解析出 sdb, sdc 等内核名称用于查 IO
    local short_name=$(basename "$(readlink -f "$disk_id")")
    if [[ -z "$short_name" ]]; then
        echo "❌ [Error] Cannot resolve kernel name for $disk_id (Skipping)"
        return 1
    fi

    # 初始化该硬盘的状态
    drive_status["$disk_id"]="active"
    drive_spinups["$disk_id"]=0
    drive_timeout["$disk_id"]=120 # 初始 30分钟
    drive_idle_sec["$disk_id"]=0
    drive_short_name["$disk_id"]="$short_name"
    
    # 获取初始 IO（读扇区数$6 + 写扇区数$10）
    local initial_io=$(awk -v dev="$short_name" '$3 == dev {print $6 + $10}' /proc/diskstats)
    
    if [[ -z "$initial_io" ]]; then
        echo "❌ [Error] Cannot read IO stats for $short_name (Skipping)"
        return 1
    fi
    drive_last_io["$disk_id"]=$initial_io
    
    echo "✅ [Init] Monitoring: $short_name ($disk_id)"
    return 0
}

# 2. 检查电源状态 (返回 0=Active, 2=Standby)
# 添加 2>&1 确保 smartctl 的报错也不会刷屏，只看退出码
check_power_status() {
    smartctl -n standby -i "$1" > /dev/null 2>&1
    return $?
}

# 3. 计算超时策略
update_strategy() {
    local id="$1"
    local count=${drive_spinups["$id"]}
    
    case $count in
        0) drive_timeout["$id"]=120 ;; # 30m
        1) drive_timeout["$id"]=240 ;; # 60m
        2) drive_timeout["$id"]=360 ;; # 90m
        *) drive_timeout["$id"]="unlimited" ;;
    esac
}

# 4. 执行休眠并验证 (双重检查 + 熔断)
perform_spindown() {
    local id="$1"
    local s_name=${drive_short_name["$id"]}
    
    echo "💤 [$s_name] Sending spindown command..."
    hdparm -y "$id"
    
    # 第一次验证：等待 5 秒
    sleep 5
    check_power_status "$id"
    if [ $? -eq 2 ]; then
        echo "🌙 [$s_name] Verify Success (5s): Disk is SLEEPING."
        drive_status["$id"]="sleeping"
        drive_idle_sec["$id"]=0
        return
    fi
    
    # 第一次失败，等待 10 秒重试
    echo "⚠️ [$s_name] Verify Failed (5s). Retrying in 10s..."
    sleep 10
    check_power_status "$id"
    if [ $? -eq 2 ]; then
        echo "🌙 [$s_name] Verify Success (15s): Disk is SLEEPING."
        drive_status["$id"]="sleeping"
        drive_idle_sec["$id"]=0
        return
    fi
    
    # 彻底失败：熔断机制
    echo "🔥 [$s_name] CRITICAL FAILURE: Disk refused to sleep twice."
    echo "🔥 [$s_name] Marking drive as DISABLED until tomorrow."
    drive_status["$id"]="disabled"
}

# --- 信号处理 (优雅退出) ---
cleanup() {
    echo ""
    echo "🛑 [Shutdown] Daemon exited."
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- 主程序开始 ---

echo "=== Spindown Daemon v3.3 Started ==="
echo ""

# 1. 遍历并初始化有效硬盘
for disk in "${TARGET_DRIVES[@]}"; do
    if init_drive "$disk"; then
        VALID_DRIVES+=("$disk")
    fi
done

if [ ${#VALID_DRIVES[@]} -eq 0 ]; then
    echo "No valid drives to monitor. Exiting."
    exit 1
fi

echo "Monitoring ${#VALID_DRIVES[@]} drives. Poll Interval: ${POLL_INTERVAL}s."

# 2. 死循环监控
while true; do
    sleep $POLL_INTERVAL
    
    # 检查日期变更
    current_date=$(date +%F)
    if [ "$current_date" != "$last_date" ]; then
        echo "📅 [New Day] Resetting all counters ($current_date)."
        last_date=$current_date
        for id in "${VALID_DRIVES[@]}"; do
            drive_spinups["$id"]=0
            # 新的一天重置熔断状态
            if [ "${drive_status[$id]}" == "disabled" ]; then
                s_name=${drive_short_name["$id"]}
                echo "🔄 [$s_name] Re-enabling previously disabled drive."
                drive_status["$id"]="active"
            fi
            update_strategy "$id"
        done
    fi

    # 遍历每一块硬盘
    for id in "${VALID_DRIVES[@]}"; do
        
        # 跳过已熔断的硬盘
        if [ "${drive_status[$id]}" == "disabled" ]; then
            continue
        fi

        s_name=${drive_short_name["$id"]}
        
        # 获取当前电源状态
        check_power_status "$id"
        p_state=$? # 2=Standby, 0=Active

        # --- 状态机逻辑 ---
        
        # A. 硬盘正在睡觉
        if [ $p_state -eq 2 ]; then
            if [ "${drive_status[$id]}" != "sleeping" ]; then
                # 之前认为它醒着，现在发现它睡了 (可能是自己睡的)
                echo "🛌 [$s_name] Disk is sleeping (External source)."
                drive_status["$id"]="sleeping"
            fi
            drive_idle_sec["$id"]=0
            continue
        fi

        # B. 硬盘醒着
        if [ "${drive_status[$id]}" == "sleeping" ]; then
            # 状态突变：睡 -> 醒 (唤醒事件!)
            count=$(( ${drive_spinups["$id"]} + 1 ))
            drive_spinups["$id"]=$count
            drive_status["$id"]="active"
            
            update_strategy "$id"
            limit=${drive_timeout["$id"]}
            
            echo "🔔 [$s_name] WOKE UP! Spin-ups today: $count / $MAX_SPINUPS"
            if [ "$limit" == "unlimited" ]; then
                echo "🚫 [$s_name] Limit reached. Stay ON today."
            else
                echo "⏱️ [$s_name] Next timeout: $((limit / 60)) mins."
            fi
        fi
        
        # C. 检查是否达到今日限制
        if [ "${drive_timeout[$id]}" == "unlimited" ]; then
            # 更新 IO 统计防止堆积，但不处理
            drive_last_io["$id"]=$(awk -v dev="$s_name" '$3 == dev {print $6 + $10}' /proc/diskstats)
            continue
        fi

        # D. 检查 IO 读写（读扇区数$6 + 写扇区数$10）
        current_io=$(awk -v dev="$s_name" '$3 == dev {print $6 + $10}' /proc/diskstats)
        
        # 检查 IO 数据有效性
        if [[ -z "$current_io" ]]; then
            echo "⚠️ [$s_name] Failed to read IO stats, skipping this cycle."
            continue
        fi
        
        if [ "$current_io" == "${drive_last_io["$id"]}" ]; then
            # 无读写，增加闲置计数
            current_idle=$(( ${drive_idle_sec["$id"]} + $POLL_INTERVAL ))
            drive_idle_sec["$id"]=$current_idle
            target=${drive_timeout["$id"]}

            # 达到阈值，尝试休眠
            if [ $current_idle -ge $target ]; then
                echo "⏳ [$s_name] Idle threshold reached ($((target/60))m). Attempting spindown..."
                perform_spindown "$id"
            fi
        else
            # 有读写，重置计时
            drive_idle_sec["$id"]=0
            drive_last_io["$id"]=$current_io
        fi
        
    done
done