#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"

# 0. 启动即清屏
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 核心函数 ---

get_status() {
    # 读取内核当前生效的配置
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    # 判断 BBR 状态
    if [[ "$cc" == "bbr" ]]; then
        STATUS_BBR="${GREEN}已开启 (BBR)${PLAIN}"
    else
        STATUS_BBR="${YELLOW}未开启 ($cc)${PLAIN}"
    fi

    # 判断队列状态
    if [[ "$qd" == "fq" ]]; then
        STATUS_QDISC="${GREEN}FQ${PLAIN}"
    else
        STATUS_QDISC="${YELLOW}$qd${PLAIN}"
    fi
    
    # 判断是否应用了额外优化 (检查配置文件是否存在且行数够多)
    if [ -f "$SYSCTL_CONF" ] && [ $(wc -l < "$SYSCTL_CONF") -gt 5 ]; then
        STATUS_OPT="${GREEN}已应用高性能参数${PLAIN}"
    else
        STATUS_OPT="${GRAY}默认参数${PLAIN}"
    fi
}

apply_sysctl() {
    echo -e "${INFO} 正在刷新内核参数..."
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}设置已生效！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# --- 功能模块 ---

enable_bbr() {
    echo -e "\n${BLUE}正在开启 BBR 加速...${PLAIN}"
    # 写入基础 BBR 配置
    cat > "$SYSCTL_CONF" <<CONF
# Xray Auto - BBR Base
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
    apply_sysctl
}

disable_bbr() {
    echo -e "\n${BLUE}正在关闭 BBR (恢复 CUBIC)...${PLAIN}"
    # 恢复系统默认 (通常是 fq_codel + cubic)
    cat > "$SYSCTL_CONF" <<CONF
# Xray Auto - BBR Disabled
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = cubic
CONF
    apply_sysctl
}

# 高级优化：调整 TCP 窗口和缓冲区，适合大流量 VPS
optimize_tcp() {
    echo -e "\n${BLUE}正在应用 TCP 高性能参数 (Buffer Optimization)...${PLAIN}"
    # 先保留当前的 CC 算法
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local current_qd=$(sysctl -n net.core.default_qdisc)
    
    cat > "$SYSCTL_CONF" <<CONF
# Xray Auto - Advanced TCP Optimization
net.core.default_qdisc = $current_qd
net.ipv4.tcp_congestion_control = $current_cc

# TCP 缓冲区优化 (针对大带宽)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 低延迟与并发优化
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_syncookies = 1
CONF
    apply_sysctl
}

reset_tcp() {
    echo -e "\n${BLUE}正在重置为保守参数...${PLAIN}"
    # 只保留最基础的 BBR/Cubic 设置，清除缓冲区优化
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local current_qd=$(sysctl -n net.core.default_qdisc)
    
    cat > "$SYSCTL_CONF" <<CONF
# Xray Auto - Base Config
net.core.default_qdisc = $current_qd
net.ipv4.tcp_congestion_control = $current_cc
CONF
    apply_sysctl
}

switch_qdisc() {
    echo -e "\n${BLUE}切换队列调度算法 (Queue Discipline)${PLAIN}"
    echo "1. FQ (Fair Queue) - BBR 的最佳拍档"
    echo "2. FQ_CODEL - 通用性更好，适合 CUBIC"
    read -p "请选择 [1-2]: " q_choice
    
    local target_q=""
    case "$q_choice" in
        1) target_q="fq" ;;
        2) target_q="fq_codel" ;;
        *) return ;;
    esac
    
    # 替换配置文件中的 qdisc 设置
    if grep -q "net.core.default_qdisc" "$SYSCTL_CONF"; then
        sed -i "s/^net.core.default_qdisc.*/net.core.default_qdisc = $target_q/" "$SYSCTL_CONF"
    else
        echo "net.core.default_qdisc = $target_q" >> "$SYSCTL_CONF"
    fi
    apply_sysctl
}

# --- 主循环 ---

while true; do
    get_status
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          内核与网络优化 (BBR Manager)            ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  拥塞算法 : ${STATUS_BBR}"
    echo -e "  队列调度 : ${STATUS_QDISC}"
    echo -e "  高级优化 : ${STATUS_OPT}"
    echo -e "---------------------------------------------------"
    echo -e "  1. ${GREEN}开启 BBR${PLAIN} (Enable BBR + FQ)"
    echo -e "  2. ${YELLOW}关闭 BBR${PLAIN} (Disable -> Cubic)"
    echo -e "---------------------------------------------------"
    echo -e "  3. 应用 TCP 大窗口优化 (Boost Throughput)"
    echo -e "  4. 重置 TCP 缓冲区参数 (Reset to Default)"
    echo -e "  5. 切换队列算法 (FQ / FQ_CODEL)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    read -p "请输入选项 [0-5]: " choice

    case "$choice" in
        1) enable_bbr ;;
        2) disable_bbr ;;
        3) optimize_tcp ;;
        4) reset_tcp ;;
        5) switch_qdisc ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
