#!/bin/bash
PROJECT="NodeHatch"
TMP_DIR="/var/tmp/nodehatch_monitor"
LOG_FILE="/root/nodehatch_monitor.log"
mkdir -p "$TMP_DIR"
NOW=$(date +%s)

# 初始化日志文件头
if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,container,cpu_delta_seconds,memory_bytes,net_rx_total,net_tx_total,disk_bytes,uptime_seconds" > "$LOG_FILE"
fi

# 获取运行中的容器列表
containers=$(incus ls --project "$PROJECT" --format=json | jq -r '.[] | select(.status == "Running") | .name')

for container in $containers; do
    # 获取容器实时状态
    state_json=$(incus query "/1.0/instances/$container/state?project=$PROJECT" 2>/dev/null) || continue

    # 解析基础指标
    cpu_usage_ns=$(jq -r '.cpu.usage' <<<"$state_json")
    cpu_usage_seconds=$((cpu_usage_ns / 1000000000))
    memory_usage=$(jq -r '.memory.usage' <<<"$state_json")
    eth0_rx=$(jq -r '.network.eth0.counters.bytes_received // 0' <<<"$state_json")
    eth0_tx=$(jq -r '.network.eth0.counters.bytes_sent // 0' <<<"$state_json")
    disk_bytes=$(jq -r '.disk.root.usage' <<<"$state_json")

    # 计算运行时间
    started_at=$(jq -r '.started_at' <<<"$state_json")
    started_ts=$(date -d "$started_at" +%s 2>/dev/null)
    uptime=$(( started_ts ? NOW - started_ts : 0 ))

    # 处理CPU增量
    prev_file="$TMP_DIR/$container.prev"
    cpu_delta=0
    if [[ -f "$prev_file" ]]; then
        prev_cpu=$(jq -r '.cpu_usage_seconds' "$prev_file")
        prev_ts=$(jq -r '.timestamp' "$prev_file")
        time_elapsed=$((NOW - prev_ts))
        
        if (( time_elapsed > 0 )); then
            cpu_delta=$((cpu_usage_seconds - prev_cpu))
        fi
    fi

    # 保存当前状态（仅保留CPU相关数据）
    jq -n --arg ts "$NOW" \
          --arg cpu "$cpu_usage_seconds" \
          '{timestamp: $ts|tonumber, 
            cpu_usage_seconds: $cpu|tonumber}' > "$prev_file"

    # 记录日志（直接使用网络总量）
    echo "$NOW,$container,$cpu_delta,${memory_usage%.*},$eth0_rx,$eth0_tx,${disk_bytes%.*},$uptime" >> "$LOG_FILE"
done