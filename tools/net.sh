#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"
GRAY="\033[90m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
GAI_CONF="/etc/gai.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi

# ==============================================================================
# 核心辅助函数
# ==============================================================================
# 1. 连通性检测 
check_connectivity() {
    local target_ver=$1
    local ret_code=1

    if [ "$target_ver" == "v4" ]; then
        # 优先尝试 Cloudflare (1.1.1.1)
        if curl -s4m 1 https://1.1.1.1 >/dev/null 2>&1; then
            return 0
        # 备选尝试 Google (8.8.8.8) - 避免单点故障
        elif curl -s4m 1 https://8.8.8.8 >/dev/null 2>&1; then
            return 0
        # 再次备选 OpenDNS (208.67.222.222)
        elif curl -s4m 1 https://208.67.222.222 >/dev/null 2>&1; then
            return 0
        fi
        
    elif [ "$target_ver" == "v6" ]; then
        # 优先尝试 Cloudflare (2606:4700:4700::1111)
        if curl -s6m 1 https://2606:4700:4700::1111 >/dev/null 2>&1; then
            return 0
        # 备选尝试 Google (2001:4860:4860::8888)
        elif curl -s6m 1 https://2001:4860:4860::8888 >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 如果所有靶点都失败，才判定为无网络
    return 1
}

# 2. SSH 连接方式检测 (兼容 sudo)
check_ssh_connection() {
    # 优先尝试读取 SUDO_SSH_CLIENT (如果通过 sudo 运行)
    local client_info="${SUDO_SSH_CLIENT:-$SSH_CLIENT}"
    
    # 如果还为空，尝试通过 who 命令获取 (兜底方案)
    if [ -z "$client_info" ]; then
        client_info=$(who -m 2>/dev/null | awk '{print $NF}' | tr -d '()')
    fi

    # 判定逻辑：包含冒号 : 且不包含点 . (简单判定v6) 或者包含两个以上冒号
    if [[ "$client_info" =~ : ]]; then
        echo "v6"
    else
        echo "v4"
    fi
}

# 3. 系统级 IPv6 开关
toggle_system_ipv6() {
    local state=$1
    if [ "$state" == "off" ]; then
        # 安全拦截
        if [ "$(check_ssh_connection)" == "v6" ]; then
            echo -e "${RED}[危险拦截] 检测到您当前通过 IPv6 连接 SSH！${PLAIN}"
            echo -e "${YELLOW}禁止在此状态下关闭系统 IPv6，否则您将立即失联。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return 1
        fi
        
        echo -e "${YELLOW}正在通过 sysctl 禁用 IPv6...${PLAIN}"
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        # 持久化
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYSCTL_CONF"
    else
        echo -e "${GREEN}正在恢复系统 IPv6...${PLAIN}"
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
    fi
    return 0
}

# 4. 设置系统优先级 (gai.conf)
set_system_prio() {
    [ ! -f "$GAI_CONF" ] && touch "$GAI_CONF"
    # 清理旧规则
    sed -i '/^precedence ::ffff:0:0\/96  100/d' "$GAI_CONF"
    
    # 如果是 v4 优先，写入规则
    if [ "$1" == "v4" ]; then 
        echo "precedence ::ffff:0:0/96  100" >> "$GAI_CONF"
    fi
    # 注意：v6 优先是 Linux 默认行为，所以只要删掉上面的规则就是 v6 优先
}

# 5. 应用策略总控
apply_strategy() {
    local sys_action=$1
    local xray_strategy=$2
    local desc=$3

    # --- 执行系统级变更 ---
    if [ "$sys_action" == "v4_only" ]; then
        if ! toggle_system_ipv6 "off"; then return; fi # 如果被拦截则停止
        set_system_prio "v4"
    elif [ "$sys_action" == "v6_only" ]; then
        toggle_system_ipv6 "on"
        set_system_prio "v6"
    else
        # 双栈模式
        toggle_system_ipv6 "on"
        if [ "$sys_action" == "v4_prio" ]; then set_system_prio "v4"; else set_system_prio "v6"; fi
    fi

    # --- 连通性复查 ---
    if [ "$xray_strategy" == "UseIPv4" ] && ! check_connectivity "v4"; then
        echo -e "${RED}错误：本机无法连接 IPv4 网络，无法执行纯 IPv4 策略！${PLAIN}"
        # 回滚系统设置
        toggle_system_ipv6 "on"
        read -n 1 -s -r; return
    fi

    # --- 修改 Xray 配置 ---
    echo -e "${BLUE}正在更新 Xray 配置...${PLAIN}"
    
    # 先确保 routing 对象存在 (防止 jq 报错)
    if [ -f "$CONFIG_FILE" ]; then
        tmp=$(mktemp)
        # 1. 如果 routing 不存在，先创建它
        jq 'if .routing == null then .routing = {} else . end' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        # 2. 设置 domainStrategy
        jq --arg s "$xray_strategy" '.routing.domainStrategy = $s' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        rm -f "$tmp"
        
        systemctl restart xray
        echo -e "${GREEN}设置成功！当前运行模式: ${YELLOW}${desc}${PLAIN}"
    else
        echo -e "${RED}错误：找不到配置文件 $CONFIG_FILE${PLAIN}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# ==============================================================================
# 状态显示逻辑
# ==============================================================================
get_current_status() {
    # 1. 获取 Xray 策略
    local xray_conf="Unknown"
    if [ -f "$CONFIG_FILE" ]; then
        xray_conf=$(jq -r '.routing.domainStrategy // "Unknown"' "$CONFIG_FILE")
    fi
    
    # 2. 获取系统 IPv6 开关 (0=开启, 1=禁用)
    local sys_v6_val=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    [ -z "$sys_v6_val" ] && sys_v6_val=0

    # 3. 获取优先级
    local is_v4_prio=false
    if grep -q "^precedence ::ffff:0:0/96  100" "$GAI_CONF" 2>/dev/null; then
        is_v4_prio=true
    fi

    # 4. 判定逻辑 (修复混合状态显示)
    
    # 情况 A: Xray 强制 IPv6
    if [ "$xray_conf" == "UseIPv6" ]; then
        STATUS_TEXT="${YELLOW}仅 IPv6 (Xray 强制)${PLAIN}"
        
    # 情况 B: Xray 强制 IPv4
    elif [ "$xray_conf" == "UseIPv4" ]; then
        if [ "$sys_v6_val" -eq 1 ]; then
            # Xray 限 v4 且 系统也禁了 v4 -> 真正的纯净模式
            STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
        else
            # Xray 限 v4 但 系统 v6 还开着 -> 混合模式
            STATUS_TEXT="${YELLOW}仅 IPv4 (Xray 策略)${PLAIN} ${GRAY}- 系统 IPv6 仍开启${PLAIN}"
        fi
        
    # 情况 C: 系统禁用 IPv6
    elif [ "$sys_v6_val" -eq 1 ]; then
        STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
        
    # 情况 D: 双栈模式 (Xray 没限制，系统也没限制)
    else
        if [ "$is_v4_prio" = true ]; then
            STATUS_TEXT="${GREEN}双栈网络 (IPv4 优先)${PLAIN}"
        else
            STATUS_TEXT="${GREEN}双栈网络 (IPv6 优先 - 默认)${PLAIN}"
        fi
    fi
}

# --- 交互菜单 ---
while true; do
    get_current_status
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          网络优先级切换 (Network Priority)       ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  当前状态: ${STATUS_TEXT}"
    echo -e "---------------------------------------------------"
    echo -e "  [双栈模式]"
    echo -e "  1. IPv4 优先   ${GRAY}- IPv6 保持开启${PLAIN}"
    echo -e "  2. IPv6 优先   ${GRAY}- IPv4 保持开启${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  [强制模式]"
    echo -e "  3. 仅 IPv4     ${GRAY}- 系统禁用 IPv6 + Xray 强制 v4${PLAIN}"
    echo -e "  4. 仅 IPv6     ${GRAY}- 系统保留 IPv4 + Xray 强制 v6${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-4]: " choice

    case "$choice" in
        1) apply_strategy "v4_prio" "IPIfNonMatch" "IPv4 优先 (双栈)" ;;
        2) apply_strategy "v6_prio" "IPIfNonMatch" "IPv6 优先 (双栈)" ;;
        3) apply_strategy "v4_only" "UseIPv4"      "纯 IPv4 模式" ;;
        4) apply_strategy "v6_only" "UseIPv6"      "纯 IPv6 模式" ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
