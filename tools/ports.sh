#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

# 配置文件路径
CONFIG_FILE="/usr/local/etc/xray/config.json"
SSH_CONFIG="/etc/ssh/sshd_config"

# 检查依赖
if ! command -v jq &> /dev/null; then
    echo -e "${RED}错误: 缺少 jq 依赖，无法解析配置。${PLAIN}"; exit 1
fi

# --- 辅助函数 ---

check_status() {
    local port=$1
    if ss -tulpn | grep -q ":${port} "; then
        echo -e "${GREEN}运行中${PLAIN}"
    else
        echo -e "${RED}未运行${PLAIN}"
    fi
}

open_port() {
    local port=$1
    iptables -I INPUT -p tcp --dport $port -j ACCEPT
    iptables -I INPUT -p udp --dport $port -j ACCEPT
    if [ -f /proc/net/if_inet6 ]; then
        ip6tables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        ip6tables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
    fi
    netfilter-persistent save 2>/dev/null
}

get_ports() {
    CURRENT_SSH=$(grep "^Port" "$SSH_CONFIG" | head -n 1 | awk '{print $2}')
    [ -z "$CURRENT_SSH" ] && CURRENT_SSH=22
    
    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
        CURRENT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
    else
        CURRENT_VISION="N/A"; CURRENT_XHTTP="N/A"
    fi
}

validate_port() {
    if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo -e "${RED}错误: 端口必须是 1-65535 之间的数字！${PLAIN}"
        return 1
    fi
    return 0
}

# --- 修改逻辑 ---

change_ssh() {
    # === 红色警示框开始 ===
    clear
    echo -e "${RED}################################################################${PLAIN}"
    echo -e "${RED}#                    高风险操作警告 (WARNING)                  #${PLAIN}"
    echo -e "${RED}################################################################${PLAIN}"
    echo -e "${RED}#${PLAIN}                                                              ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}  1. 云服务器用户 (阿里云/腾讯云/AWS等)：                     ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}     必须先在网页控制台的【安全组/防火墙】放行新端口！        ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}     (脚本只能修改系统内部防火墙，无法修改云平台安全组)       ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}                                                              ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}  2. 修改后【绝对不要】关闭当前窗口！                         ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}     请新开一个 SSH 窗口测试连接。如果失败，                  ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}     请立即利用当前窗口改回原端口 ($CURRENT_SSH)。                    ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}                                                              ${RED}#${PLAIN}"
    echo -e "${RED}################################################################${PLAIN}"
    echo ""
    
    read -p "我已知晓风险，确认继续修改? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}>>> 操作已取消。${PLAIN}"; sleep 1; return
    fi
    # === 红色警示框结束 ===

    echo ""
    read -p "请输入新的 SSH 端口 [当前: $CURRENT_SSH]: " new_port
    validate_port "$new_port" || return
    
    echo -e "${BLUE}正在修改 SSH 端口...${PLAIN}"
    sed -i "s/^Port.*/Port $new_port/" "$SSH_CONFIG"
    if ! grep -q "^Port" "$SSH_CONFIG"; then echo "Port $new_port" >> "$SSH_CONFIG"; fi
    
    open_port "$new_port"
    
    echo -e "${INFO} 重启 SSH 服务..."
    systemctl restart ssh || systemctl restart sshd
    echo -e "${GREEN}修改成功！请务必新开窗口测试端口 $new_port 。${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

change_vision() {
    read -p "请输入新的 Vision 端口 [当前: $CURRENT_VISION]: " new_port
    validate_port "$new_port" || return

    echo -e "${BLUE}正在修改 Vision 端口...${PLAIN}"
    jq --argjson port $new_port '(.inbounds[] | select(.tag=="vision_node").port) |= $port' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    open_port "$new_port"
    
    echo -e "${INFO} 重启 Xray 服务..."
    systemctl restart xray
    echo -e "${GREEN}修改成功！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

change_xhttp() {
    read -p "请输入新的 XHTTP 端口 [当前: $CURRENT_XHTTP]: " new_port
    validate_port "$new_port" || return

    echo -e "${BLUE}正在修改 XHTTP 端口...${PLAIN}"
    jq --argjson port $new_port '(.inbounds[] | select(.tag=="xhttp_node").port) |= $port' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    open_port "$new_port"
    
    echo -e "${INFO} 重启 Xray 服务..."
    systemctl restart xray
    echo -e "${GREEN}修改成功！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# --- 主循环菜单 ---

while true; do
    get_ports
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          端口管理面板 (Port Manager)             ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  服务            端口          状态"
    echo -e "---------------------------------------------------"
    printf "  1. 修改 SSH     ${YELLOW}%-12s${PLAIN}  %s\n" "$CURRENT_SSH" "$(check_status $CURRENT_SSH)"
    printf "  2. 修改 Vision  ${YELLOW}%-12s${PLAIN}  %s\n" "$CURRENT_VISION" "$(check_status $CURRENT_VISION)"
    printf "  3. 修改 XHTTP   ${YELLOW}%-12s${PLAIN}  %s\n" "$CURRENT_XHTTP" "$(check_status $CURRENT_XHTTP)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    read -p "请输入选项 [0-3]: " choice

    case "$choice" in
        1) change_ssh ;;
        2) change_vision ;;
        3) change_xhttp ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
