#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"

# 0. 权限检测
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 核心功能 ---

# 获取当前状态
get_status() {
    # Swap 大小
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then
        STATUS_SWAP="${RED}未启用${PLAIN}"
    else
        STATUS_SWAP="${GREEN}已启用 (${SWAP_TOTAL}MB)${PLAIN}"
    fi

    # Swappiness 值
    SWAPPINESS=$(cat /proc/sys/vm/swappiness)
}

# 添加 Swap
add_swap() {
    echo -e "\n${BLUE}正在创建 Swap 分区...${PLAIN}"
    read -p "请输入 Swap 大小 (单位 MB，推荐 1024 或 2048): " swap_size
    [ -z "$swap_size" ] && swap_size=1024

    # 清理旧的
    if [ -f /swapfile ]; then swapoff /swapfile 2>/dev/null; rm -f /swapfile; fi

    # 创建新的
    fallocate -l ${swap_size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # 写入 fstab (持久化)
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    echo -e "${GREEN}成功创建 ${swap_size}MB Swap！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# 删除 Swap
del_swap() {
    echo -e "\n${YELLOW}正在删除 Swap...${PLAIN}"
    swapoff /swapfile 2>/dev/null
    rm -f /swapfile
    # 从 fstab 移除
    sed -i '/\/swapfile/d' /etc/fstab
    echo -e "${GREEN}Swap 已删除。${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# [新功能] 调整 Swappiness
set_swappiness() {
    echo -e "\n${BLUE}当前亲和度 (Swappiness): ${YELLOW}${SWAPPINESS}${PLAIN}"
    echo -e "说明: 值越小(0-10)，越倾向于使用物理内存(速度快)。"
    echo -e "      值越大(60-100)，越倾向于使用硬盘交换(适合内存极小的情况)。"
    echo -e "------------------------------------------------"
    
    # 默认值是 60
    read -p "请输入新的值 [0-100] (默认: 60): " new_val

    # 核心逻辑：若直接回车(变量为空)，则赋值为 60
    [ -z "$new_val" ] && new_val=60

    if [[ ! "$new_val" =~ ^[0-9]+$ ]] || [ "$new_val" -lt 0 ] || [ "$new_val" -gt 100 ]; then
        echo -e "${RED}输入错误，请输入 0-100 之间的数字。${PLAIN}"
    else
        # 临时生效
        sysctl -w vm.swappiness=$new_val >/dev/null
        
        # 永久生效 (修改 /etc/sysctl.conf)
        if grep -q "vm.swappiness" /etc/sysctl.conf; then
            sed -i "s/^vm.swappiness.*/vm.swappiness = $new_val/" /etc/sysctl.conf
        else
            echo "vm.swappiness = $new_val" >> /etc/sysctl.conf
        fi
        echo -e "${GREEN}设置成功！当前亲和度已改为: ${new_val}${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# --- 主菜单 ---
while true; do
    clear
    get_status
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}           虚拟内存管理 (Swap Manager)            ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  Swap 状态   : ${STATUS_SWAP}"
    echo -e "  Swappiness  : ${YELLOW}${SWAPPINESS}${PLAIN} (亲和度)"
    echo -e "---------------------------------------------------"
    echo -e "  1. 添加 / 修改 Swap 容量"
    echo -e "  2. 关闭 / 删除 Swap"
    echo -e "---------------------------------------------------"
    echo -e "  3. 调整 Swappiness 亲和度 ${GRAY}(性能优化)${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-3]: " choice

    case "$choice" in
        1) add_swap ;;
        2) del_swap ;;
        3) set_swappiness ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
