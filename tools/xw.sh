#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
WARP_PORT=40000

# 0. 启动即清屏
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 核心检测函数 ---
check_warp_socket() {
    (echo > /dev/tcp/127.0.0.1/$WARP_PORT) >/dev/null 2>&1
}

wait_for_port() {
    echo -ne "${INFO} 正在等待 WARP 服务启动..."
    for i in {1..15}; do
        if check_warp_socket; then
            echo -e "\r${OK} WARP 服务响应正常 (127.0.0.1:$WARP_PORT)    "
            return 0
        fi
        echo -ne "."
        sleep 1
    done
    echo -e "\r${WARN} WARP 服务响应超时，请检查日志。    "
    return 1
}

check_xray_outbound() {
    if jq -e '.outbounds[] | select(.tag=="warp_proxy")' "$CONFIG_FILE" >/dev/null; then return 0; else return 1; fi
}

check_rule_ui() {
    local site=$1 
    if jq -e --arg site "$site" '.routing.rules[] | select(.outboundTag=="warp_proxy" and (.domain | index($site)))' "$CONFIG_FILE" >/dev/null; then
        # 绿色
        echo -e "${GREEN}WARP 托管${PLAIN}"
    else
        # 黄色，或直连符号
        echo -e "${YELLOW}默认直连${PLAIN}"
    fi
}

apply_changes() {
    echo -e "${INFO} 正在重启 Xray 服务..."
    systemctl restart xray
    echo -e "${GREEN}配置已更新！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# --- Xray 配置修改 ---
ensure_outbound() {
    if check_xray_outbound; then return; fi
    echo -e "${INFO} 添加 Xray 出口 (Socks5:$WARP_PORT)..."
    local out_obj='{"tag": "warp_proxy", "protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": '$WARP_PORT'}]}}'
    jq --argjson obj "$out_obj" '.outbounds += [$obj]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

remove_outbound() {
    echo -e "${INFO} 移除 Xray 出口..."
    jq 'del(.outbounds[] | select(.tag=="warp_proxy"))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    jq 'del(.routing.rules[] | select(.outboundTag=="warp_proxy"))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

toggle_rule() {
    local name=$1; local sites_json=$2 
    ensure_outbound
    if ! check_warp_socket; then
        echo -e "${WARN} WARP 未运行！请先执行选项 1 安装。"
        read -n 1 -s -r; return
    fi
    local first_site=$(echo "$sites_json" | jq -r '.[0]')
    local is_enabled=false
    if jq -e --arg site "$first_site" '.routing.rules[] | select(.outboundTag=="warp_proxy" and (.domain | index($site)))' "$CONFIG_FILE" >/dev/null; then is_enabled=true; fi

    if [ "$is_enabled" = true ]; then
        echo -e "操作: ${YELLOW}关闭 $name 分流${PLAIN}"
        jq --argjson sites "$sites_json" 'del(.routing.rules[] | select(.outboundTag=="warp_proxy" and (.domain == $sites)))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
        echo -e "操作: ${GREEN}开启 $name 分流${PLAIN}"
        local new_rule="{\"type\": \"field\", \"domain\": $sites_json, \"outboundTag\": \"warp_proxy\"}"
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    apply_changes
}

# --- 功能模块 ---
install_warp() {
    echo -e "\n${BLUE}正在安装 WARP (Socks5 模式)...${PLAIN}"
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh c
    echo -e "\n${INFO} 检查服务状态..."
    if wait_for_port; then
        ensure_outbound; systemctl restart xray
        echo -e "${OK} 安装成功！Xray 已自动对接。"
    else
        echo -e "${ERR} 安装可能失败，请查看上方报错。"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

uninstall_warp() {
    echo -e "\n${RED}正在卸载 WARP...${PLAIN}"
    if command -v warp &>/dev/null; then warp u; else wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh u; fi
    remove_outbound; systemctl restart xray
    echo -e "${GREEN}卸载清理完毕。${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

menu_brush_ip() {
    echo -e "\n${BLUE}调用优选 IP 工具...${PLAIN}"
    if command -v warp &>/dev/null; then warp i; else wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh i; fi
    read -n 1 -s -r -p "按任意键继续..."
}

# --- 主菜单 ---
while true; do
    clear
    # 状态栏使用图标，更直观
    if check_warp_socket; then STATUS_SOCK="${GREEN}● 运行中${PLAIN}"; else STATUS_SOCK="${RED}● 未运行${PLAIN}"; fi
    if check_xray_outbound; then STATUS_XRAY="${GREEN}● 已连接${PLAIN}"; else STATUS_XRAY="${YELLOW}● 未连接${PLAIN}"; fi
    
    # 规则检测 (UI函数)
    STATUS_NF=$(check_rule_ui "geosite:netflix")
    STATUS_AI=$(check_rule_ui "geosite:openai")

    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}           WARP 分流管理面板 (Xray Warp)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  WARP 服务: ${STATUS_SOCK}    Xray 接口: ${STATUS_XRAY}"
    echo -e "---------------------------------------------------"
    echo -e "  1. 安装 / 重装 WARP   ${GRAY}(自动配置 Socks5 端口 40000)${PLAIN}"
    echo -e "  2. 彻底卸载 WARP      ${GRAY}(卸载并清理残留规则)${PLAIN}"
    echo -e "  3. 优选 WARP IP       ${GRAY}(当 Netflix 依然看不了时使用)${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  [分流策略控制台]"
    # 使用 printf 进行对齐，或者手动使用点阵线
    echo -e "  4. Netflix 媒体库 ....... [ ${STATUS_NF} ]"
    echo -e "  5. 全能 AI 分流包 ....... [ ${STATUS_AI} ]"
    echo -e "     ${GRAY}(含 OpenAI, Claude, Grok)${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    read -p "请输入选项 [0-5]: " choice
    case "$choice" in
        1) install_warp ;;
        2) uninstall_warp ;;
        3) menu_brush_ip ;;
        4) toggle_rule "Netflix" '["geosite:netflix"]' ;;
        5) toggle_rule "AI Services" '["geosite:openai","geosite:anthropic","geosite:twitter"]' ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
