#!/bin/bash

##############################################################################
#                           DNS 配置自动化工具 v1.0                           #
#            适用因重启服务器导致 DNS 会被重置的场景，用于配置并锁定 DNS      #
#               下述 154DNS 仅适用于 DuckyCloud/Hytron 专用 DNS。            #
#               其他服务器可使用自定义选项(9)手动设置 DNS 地址。             #
##############################################################################

#--------------------------- 颜色定义（可选） ---------------------------------#
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

#--------------------------- 脚本开场信息 ------------------------------------#
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}       DNS 配置自动化工具 v1.0        ${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "${YELLOW}适用：重启服务器后 DNS 会被重置的情况${NC}"
echo -e "${YELLOW}用于：配置并锁定 /etc/resolv.conf 文件${NC}"
echo -e "${YELLOW}注：下述 154DNS 仅适用 DuckyCloud/Hytron${NC}"
echo -e "${YELLOW}其他服务器请使用 9 自定义 DNS          ${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

#--------------------------- 权限检查 ----------------------------------------#
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 权限运行此脚本！${NC}"
    exit 1
fi

#--------------------------- DNS 列表定义 ------------------------------------#
# 如需新增/修改，直接在此处增加键值对即可
declare -A DNS_SERVERS=(
    ["Default"]="154.83.83.83"
    ["HK"]="154.83.83.84"
    ["JP"]="154.83.83.85"
    ["TW"]="154.83.83.86"
    ["US"]="154.83.83.88"
    ["UK"]="154.83.83.89"
    ["DE"]="154.83.83.90"
    ["SG"]="154.83.83.87"
)

#--------------------------- 服务停止函数 ------------------------------------#
stop_service_if_active() {
    local service_name="$1"
    if systemctl is-active "$service_name" &>/dev/null; then
        echo -e "检测到 ${service_name} 正在运行，正在停止服务..."
        if systemctl disable --now "$service_name" &>/dev/null; then
            echo -e "已停止并禁用 ${service_name} 服务"
        else
            echo -e "${RED}无法停止 ${service_name} 服务，终止脚本${NC}"
            exit 1
        fi
    fi
}

#--------------------------- 回滚函数 ----------------------------------------#
rollback_dns() {
    echo -e "\n${YELLOW}正在回滚 DNS 配置...${NC}"
    if [ -f /etc/resolv.conf.bak ]; then
        # 确保可写
        chattr -i /etc/resolv.conf 2>/dev/null
        cp -f /etc/resolv.conf.bak /etc/resolv.conf
        # 再次锁定
        chattr +i /etc/resolv.conf
        echo -e "${GREEN}已恢复原始 DNS 配置${NC}"
    else
        echo -e "${RED}未找到备份文件，无法回滚${NC}"
    fi
    exit 1
}

#--------------------------- 信号和错误捕获 ----------------------------------#
# 任何执行错误（ERR）或用户中断（Ctrl+C / SIGINT / SIGTERM）都会执行回滚
trap rollback_dns ERR SIGINT SIGTERM

#--------------------------- 停止冲突服务 ------------------------------------#
stop_service_if_active "systemd-resolved"
stop_service_if_active "resolvconf"

#--------------------------- 解锁 resolv.conf --------------------------------#
if lsattr /etc/resolv.conf 2>/dev/null | grep -q '^....i'; then
    echo "检测到 /etc/resolv.conf 已被锁定，正在解锁..."
    if chattr -i /etc/resolv.conf &>/dev/null; then
        echo "已解锁 /etc/resolv.conf"
    else
        echo -e "${RED}无法解锁 /etc/resolv.conf，终止脚本${NC}"
        exit 1
    fi
fi

#--------------------------- 备份原有配置 ------------------------------------#
if [ -f /etc/resolv.conf ]; then
    echo -e "${BLUE}备份原有 DNS 配置...${NC}"
    cp -f /etc/resolv.conf /etc/resolv.conf.bak
    rm -f /etc/resolv.conf
fi

#--------------------------- 用户交互选择 ------------------------------------#
echo -e "${BOLD}请选择 DNS 服务器位置：${NC}"
echo "1) 随机 (Default)   ${DNS_SERVERS["Default"]}"
echo "2) 香港 (HK)        ${DNS_SERVERS["HK"]}"
echo "3) 日本 (JP)        ${DNS_SERVERS["JP"]}"
echo "4) 台湾 (TW)        ${DNS_SERVERS["TW"]}"
echo "5) 美国 (US)        ${DNS_SERVERS["US"]}"
echo "6) 英国 (UK)        ${DNS_SERVERS["UK"]}"
echo "7) 德国 (DE)        ${DNS_SERVERS["DE"]}"
echo "8) 新加坡 (SG)      ${DNS_SERVERS["SG"]}"
echo "9) 自定义 DNS"
echo ""

read -p "请输入选项 (1-9): " choice
case $choice in
    1) selected="Default" ;;
    2) selected="HK" ;;
    3) selected="JP" ;;
    4) selected="TW" ;;
    5) selected="US" ;;
    6) selected="UK" ;;
    7) selected="DE" ;;
    8) selected="SG" ;;
    9)
        read -p "请输入自定义 DNS 服务器地址: " custom_dns
        # 简单校验一下 IPv4 格式
        if [[ $custom_dns =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            DNS_SERVERS["Custom"]=$custom_dns
            selected="Custom"
        else
            echo -e "${RED}无效的 DNS 地址格式，使用默认 DNS${NC}"
            selected="Default"
        fi
        ;;
    *)
        echo -e "${YELLOW}无效选项，使用默认 DNS${NC}"
        selected="Default"
        ;;
esac

#--------------------------- 写入新的 resolv.conf ----------------------------#
# 注意：如果自定义 DNS 为 "Custom"，对应取 DNS_SERVERS["Custom"]
if ! echo -e "# 注意：该文件已被脚本锁定。\n# 如需修改请先执行：chattr -i /etc/resolv.conf\nnameserver ${DNS_SERVERS[$selected]}" > /etc/resolv.conf; then
    echo -e "${RED}写入新的 DNS 信息失败，回滚到原始配置${NC}"
    rollback_dns
fi

#--------------------------- 锁定配置文件 -------------------------------------#
chattr +i /etc/resolv.conf
echo -e "${GREEN}DNS 已设置为 ${selected} (${DNS_SERVERS[$selected]})${NC}"
echo -e "文件已锁定，防止系统自动修改。"
echo -e "如需修改 DNS，请先执行: ${BOLD}sudo chattr -i /etc/resolv.conf${NC}"

#--------------------------- 测试 DNS 是否可用 --------------------------------#
echo -e "\n正在测试 DNS 解析可用性..."
if ping -c 1 google.com &>/dev/null; then
    echo -e "${GREEN}DNS 配置测试成功！${NC}"
else
    echo -e "${RED}警告：DNS 解析测试失败，正在回滚到原始配置...${NC}"
    rollback_dns
fi

echo -e "\n${GREEN}脚本执行完毕！${NC}使用过程中如有问题，请根据提示进行解锁或回滚。"
