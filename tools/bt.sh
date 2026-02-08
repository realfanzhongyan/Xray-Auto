#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"

# 0. 启动即清屏
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 依赖。${PLAIN}"; exit 1; fi

# --- 核心函数 ---

get_status() {
    # 1. 检测 BT 封禁
    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent")))' "$CONFIG_FILE" >/dev/null; then
        STATUS_BT="${GREEN}已封禁 (Blocked)${PLAIN}"
        IS_BT_BLOCKED=true
    else
        STATUS_BT="${RED}已允许 (Allowed)${PLAIN}"
        IS_BT_BLOCKED=false
    fi

    # 2. 检测私有 IP 封禁
    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private")))' "$CONFIG_FILE" >/dev/null; then
        STATUS_PRIVATE="${GREEN}已封禁 (Blocked)${PLAIN}"
        IS_PRIVATE_BLOCKED=true
    else
        STATUS_PRIVATE="${RED}已允许 (Allowed)${PLAIN}"
        IS_PRIVATE_BLOCKED=false
    fi
}

apply_changes() {
    echo -e "${INFO} 正在重启 Xray 服务以应用规则..."
    systemctl restart xray
    echo -e "${GREEN}规则已生效！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# --- 功能模块 ---

toggle_bt() {
    echo -e "\n${BLUE}切换 BT/P2P 下载拦截状态${PLAIN}"
    if [ "$IS_BT_BLOCKED" = true ]; then
        echo -e "操作: ${RED}解除封禁${PLAIN} (允许 BT 下载)"
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
        echo -e "操作: ${GREEN}开启封禁${PLAIN} (禁止 BT 下载)"
        local new_rule='{"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    apply_changes
}

toggle_private() {
    echo -e "\n${BLUE}切换私有 IP (局域网) 拦截状态${PLAIN}"
    if [ "$IS_PRIVATE_BLOCKED" = true ]; then
        echo -e "操作: ${RED}解除封禁${PLAIN} (允许访问内网 IP)"
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
        echo -e "操作: ${GREEN}开启封禁${PLAIN} (禁止访问内网 IP)"
        local new_rule='{"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    apply_changes
}

# --- 主菜单 ---

while true; do
    get_status
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          流量拦截管理 (Traffic Blocker)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  BT / P2P 下载   : ${STATUS_BT}"
    echo -e "  私有 IP (局域网): ${STATUS_PRIVATE}"
    echo -e "---------------------------------------------------"
    echo -e "  1. 开启/关闭 ${YELLOW}BT 下载封禁${PLAIN}"
    echo -e "  2. 开启/关闭 ${YELLOW}私有 IP 封禁${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    read -p "请输入选项 [0-2]: " choice

    case "$choice" in
        1) toggle_bt ;;
        2) toggle_private ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
