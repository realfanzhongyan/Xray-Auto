#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

JAIL_FILE="/etc/fail2ban/jail.local"

# 0. 启动即清屏
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 核心辅助函数 ---

get_conf() {
    local key=$1
    # 提取 value
    grep "^${key}\s*=" "$JAIL_FILE" | awk -F'=' '{print $2}' | tr -d ' '
}

set_conf() {
    local key=$1; local val=$2
    if grep -q "^${key}\s*=" "$JAIL_FILE"; then
        sed -i "s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_FILE"
    else
        sed -i "2i ${key} = ${val}" "$JAIL_FILE"
    fi
}

restart_f2b() {
    echo -e "${INFO} 正在重载配置..."
    systemctl restart fail2ban
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}配置已生效！${PLAIN}"
    else
        echo -e "${RED}Fail2ban 重启失败，请检查配置！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

get_status() {
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        local count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}运行中 (Active)${PLAIN} | 当前封禁: ${RED}${count:-0}${PLAIN} IP"
    else
        echo -e "${RED}已停止 (Stopped)${PLAIN}"
    fi
}

# --- 校验函数 ---
validate_time() {
    if [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; then return 0; else return 1; fi
}
validate_int() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then return 0; else return 1; fi
}

# --- 功能模块 ---

change_param() {
    local name=$1; local key=$2; local type=$3
    local current=$(get_conf "$key")
    echo -e "\n${BLUE}正在修改: ${name}${PLAIN}"
    echo -e "当前值: ${GREEN}${current}${PLAIN}"
    
    while true; do
        read -p "请输入新值 (留空取消): " new_val
        if [ -z "$new_val" ]; then echo "取消修改。"; read -n 1 -s -r; return; fi
        if [ "$type" == "time" ]; then validate_time "$new_val" && break; fi
        if [ "$type" == "int" ]; then validate_int "$new_val" && break; fi
        echo -e "${RED}格式错误，请重试。${PLAIN}"
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    echo -e "\n${BLUE}--- 服务开关 ---${PLAIN}"
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        read -p "是否停止并禁用 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then systemctl stop fail2ban; systemctl disable fail2ban; echo -e "${RED}服务已停止。${PLAIN}"; fi
    else
        read -p "是否启用并启动 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then systemctl enable fail2ban; systemctl start fail2ban; echo -e "${GREEN}服务已启动。${PLAIN}"; fi
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

unban_ip() {
    echo -e "\n${BLUE}--- 手动解封 IP (Unban Manager) ---${PLAIN}"
    
    # 获取被封禁列表
    # 原始输出包含 "Banned IP list: IP1 IP2 ...", 我们提取冒号后面的部分
    local banned_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | sed 's/^[ \t]*//')
    
    # 如果列表为空或全是空格
    if [ -z "$banned_list" ] || [ "$banned_list" == " " ]; then
        banned_list="无 (None)"
    fi

    echo -e "当前被封禁 IP (Banned List):"
    echo -e "${RED}${banned_list}${PLAIN}"
    echo -e "---------------------------------------------------"
    
    read -p "请输入要解封的 IP (留空取消): " target_ip
    [ -z "$target_ip" ] && return
    
    fail2ban-client set sshd unbanip "$target_ip"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}指令已发送。${PLAIN}"
    else
        echo -e "${RED}操作失败 (可能是服务未运行或 IP 未被封禁)。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

add_whitelist() {
    echo -e "\n${BLUE}--- 添加白名单 (Whitelist Manager) ---${PLAIN}"
    
    # 获取白名单列表
    local current_list=$(grep "^ignoreip" "$JAIL_FILE" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    
    echo -e "当前已放行 IP (Current List):"
    echo -e "${YELLOW}${current_list:-无}${PLAIN}"
    echo -e "---------------------------------------------------"
    
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    read -p "输入 IP (回车自动添加本机 ${current_ip}): " input_ip
    
    if [ -z "$input_ip" ]; then input_ip="$current_ip"; fi
    if [ -z "$input_ip" ]; then echo -e "${RED}无法获取 IP。${PLAIN}"; sleep 1; return; fi
    
    if echo "$current_list" | grep -Fq "$input_ip"; then
        echo -e "${YELLOW}该 IP 已存在。${PLAIN}"; sleep 1; return
    fi
    
    sed -i "/^ignoreip/ s/$/ ${input_ip}/" "$JAIL_FILE"
    restart_f2b
}

view_logs() {
    clear
    echo -e "${BLUE}=== 系统封禁/解封历史 (Audit Log) ===${PLAIN}"
    echo -e "日志来源: ${GRAY}/var/log/fail2ban.log${PLAIN}"
    echo -e "---------------------------------------------------"

    if [ ! -f /var/log/fail2ban.log ]; then
        echo -e "${YELLOW}暂无日志文件 (服务可能刚安装)。${PLAIN}"
    else
        # [核心优化] 使用 awk 进行格式化对齐
        # 1. sprintf("%9s", $4): 将第4列(PID)强制设为9个字符宽，并右对齐。
        #    这样 [123]: 和 [12345]: 中的冒号就会上下垂直对齐。
        # 2. gsub: 给关键词上色。
        
        grep -E "(Ban|Unban)" /var/log/fail2ban.log 2>/dev/null | tail -n 20 | \
        awk '{
            # 1. 颜色高亮 (先上色，避免影响对齐逻辑)
            gsub(/Unban/, "\033[32m&\033[0m");
            gsub(/Ban/, "\033[31m&\033[0m");
            
            # 2. 对齐 PID 字段 (识别类似 [12345]: 的列)
            if ($4 ~ /^\[.*\]:$/) {
                # 右对齐，宽度设为 9 (PID通常5-6位，9足够容纳)
                $4 = sprintf("%9s", $4)
            }
            
            # 3. 打印重组后的行 (awk 会自动用整齐的空格连接各列)
            print
        }'
    fi
    
    echo -e "---------------------------------------------------"
    read -n 1 -s -r -p "按任意键退出..."
}

menu_exponential() {
    while true; do
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== 指数封禁设置 ===${PLAIN}"
        echo -e "  1. 递增模式开关   [${S_INC}]"
        echo -e "  2. 修改增长系数   [${YELLOW}${fac}${PLAIN}]"
        echo -e "  3. 修改封禁上限   [${YELLOW}${max}${PLAIN}]"
        echo -e "---------------------------------"
        echo -e "  0. 返回"
        echo -e ""
        read -p "请选择: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_param "增长系数" "bantime.factor" "int" ;;
            3) change_param "封禁上限" "bantime.maxtime" "time" ;;
            0) return ;;
        esac
    done
}

# --- 主循环 ---

while true; do
    clear
    VAL_MAX=$(get_conf "maxretry"); VAL_BAN=$(get_conf "bantime"); VAL_FIND=$(get_conf "findtime")
    
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}         Fail2ban 防火墙管理 (F2B Panel)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  状态: $(get_status)"
    echo -e "---------------------------------------------------"
    echo -e "  1. 修改 最大重试次数 [${YELLOW}${VAL_MAX}${PLAIN}]"
    echo -e "  2. 修改 初始封禁时长 [${YELLOW}${VAL_BAN}${PLAIN}]"
    echo -e "  3. 修改 监测时间窗口 [${YELLOW}${VAL_FIND}${PLAIN}]"
    echo -e "---------------------------------------------------"
    echo -e "  4. ${GREEN}手动解封 IP${PLAIN}  (Unban)"
    echo -e "  5. ${GREEN}添加白名单${PLAIN}   (Whitelist)"
    echo -e "  6. 查看封禁日志 (Logs)"
    echo -e "  7. ${YELLOW}指数封禁设置${PLAIN} (Advanced) ->"
    echo -e "---------------------------------------------------"
    echo -e "  8. 开启/停止 Fail2ban 服务 (On/Off)"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-8]: " choice

    case "$choice" in
        1) change_param "最大重试次数" "maxretry" "int" ;;
        2) change_param "初始封禁时长" "bantime"  "time" ;;
        3) change_param "监测时间窗口" "findtime" "time" ;;
        4) unban_ip ;;
        5) add_whitelist ;;
        6) view_logs ;;
        7) menu_exponential ;;
        8) toggle_service ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
