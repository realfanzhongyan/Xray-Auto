#!/bin/bash

# =========================================================
# 定义颜色
# =========================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# =========================================================
# 卸载逻辑
# =========================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# 2. 确认交互
clear
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${RED}               Xray 一键卸载 (Uninstall Xray)               ${PLAIN}"
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${YELLOW}警告：此操作将执行以下清理：${PLAIN}"
echo -e "  1. 停止并移除 Xray 服务"
echo -e "  2. 删除 Xray 核心文件、配置文件、日志"
echo -e "  3. 删除所有管理脚本 (info, net, bbr, 等)"
echo -e "  4. 清理残留的安装目录"
echo -e "${RED}=============================================================${PLAIN}"
echo ""
read -p "确认要彻底卸载吗？[y/n]: " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${GREEN}操作已取消。${PLAIN}"
    exit 0
fi

echo -e "\n${GREEN}>>> 正在停止服务...${PLAIN}"

# 3. 停止服务
systemctl stop xray >/dev/null 2>&1
systemctl disable xray >/dev/null 2>&1

# 4. 删除文件
echo -e "${GREEN}>>> 正在删除文件...${PLAIN}"

# 删除服务文件
rm -f /etc/systemd/system/xray.service
rm -f /lib/systemd/system/xray.service

# 删除核心与配置
# 注意：这里会连同 config.json 和证书一起删除，确保彻底
rm -rf /usr/local/bin/xray
rm -rf /usr/local/etc/xray
rm -rf /usr/local/share/xray
rm -rf /var/log/xray

# 5. 删除工具脚本 (根据你之前截图中的工具列表)
# 这一步非常关键，确保把 /usr/local/bin 下的快捷命令清理干净
TOOLS=(
    "xray"      # 核心命令
    "info"      # 信息查看
    "net"       # 网络管理
    "bbr"       # BBR 管理
    "bt"        # 宝塔面板
    "f2b"       # Fail2ban
    "ports"     # 端口管理
    "sni"       # SNI 检测
    "swap"      # Swap 管理
    "xw"        # 防火墙管理
    "remove"    # 本脚本自己 (最后删除)
    "uninstall" # 别名
)

for tool in "${TOOLS[@]}"; do
    if [ -f "/usr/local/bin/$tool" ]; then
        rm -f "/usr/local/bin/$tool"
        echo -e "   [OK] 已删除命令: ${tool}"
    fi
done

# 6. 重载系统守护进程
systemctl daemon-reload
systemctl reset-failed

# 7. (可选) 清理安装源码目录
# 如果用户是在 /root/xray-install 运行的，可以选择是否删除它
# 为了安全起见，通常不建议脚本自动删除用户当前的 working directory，
# 但可以尝试删除标准的安装路径
if [ -d "/root/xray-install" ]; then
    rm -rf "/root/xray-install"
fi

echo -e "\n${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      卸载完成 (Uninstallation Complete)      ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "提示: 系统 BBR 设置与已安装的依赖 (如 git, curl) 未移除，"
echo -e "      以免影响系统其他服务。"
echo ""
