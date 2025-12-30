#!/bin/sh

# =================================================================
# Linux 网络全能优化脚本 (菜单版)
# 特性: 智能备份 / 极致优化 / 一键恢复
# =================================================================

# --- 0. 基础变量与颜色设置 ---
BACKUP_FILE="/etc/sysctl.conf.bak.original"
CONFIG_FILE="/etc/sysctl.conf"

# 定义颜色 (兼容性写法)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 1. Root 权限检查 ---
if [ "$(id -u)" != "0" ]; then
    echo "${RED}❌ 错误: 必须使用 Root 权限运行此脚本。${PLAIN}"
    exit 1
fi

# --- 2. 核心功能函数 ---

# [功能1] 检查环境并执行优化
function_optimize() {
    echo "${CYAN}🔍 正在进行环境与内核检测...${PLAIN}"
    
    # 检测 OpenVZ
    if [ -f "/proc/user_beancounters" ]; then
        echo "${RED}❌ 检测到 OpenVZ 环境，无法修改内核参数，脚本终止。${PLAIN}"
        return
    fi

    # 检测内核版本 (要求 >= 4.9)
    KERNEL_MAJOR=$(uname -r | cut -d. -f1)
    KERNEL_MINOR=$(uname -r | cut -d. -f2)
    if [ "$KERNEL_MAJOR" -lt 4 ] || { [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -lt 9 ]; }; then
        echo "${RED}❌ 内核版本过低 ($(uname -r))。BBR 需要 Kernel 4.9+。${PLAIN}"
        return
    fi

    # 尝试加载模块
    if command -v modprobe > /dev/null 2>&1; then
        modprobe tcp_bbr > /dev/null 2>&1
    fi

    # --- 智能备份逻辑 ---
    # 只有当原始备份不存在时才创建，防止多次运行优化覆盖了最初的原始配置
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "${YELLOW}💾 检测到首次运行，正在创建原始配置备份...${PLAIN}"
        if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$BACKUP_FILE"
        else
            touch "$BACKUP_FILE" # 如果原文件不存在，创建一个空的作为备份
        fi
        echo "${GREEN}✅ 原始配置已永久备份至: $BACKUP_FILE${PLAIN}"
    else
        echo "${YELLOW}ℹ️ 检测到已有原始备份，跳过备份步骤。${PLAIN}"
    fi

    # --- 写入优化配置 (完全覆写) ---
    echo "${CYAN}🚀 正在写入 [低重传 + 高速度] 优化方案...${PLAIN}"
    
    cat > "$CONFIG_FILE" << EOF
# =================================================================
# High Performance TCP Tuning (Optimized for Low-Retransmission)
# Applied at: $(date)
# =================================================================

# --- 核心拥塞控制 (BBR + FQ) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 关键优化: 降低 Bufferbloat 与 重传 ---
# 限制发送缓冲区积压，让 BBR 更灵敏，大幅降低延迟和无效重传
net.ipv4.tcp_notsent_lowat = 16384

# --- ECN (显式拥塞通知) ---
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1

# --- SACK & 丢包恢复 ---
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_early_retrans = 3

# --- 缓冲区调优 (适配 1G-10G 带宽) ---
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# --- 连接与网络稳定性 ---
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 10000 65000
net.netfilter.nf_conntrack_max = 1000000
net.core.somaxconn = 65535

# --- 安全设置 ---
# 严禁开启 tcp_tw_recycle (避免 NAT 断流)
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
EOF

    # 应用更改
    sysctl -p > /dev/null 2>&1
    
    # 验证
    CHECK_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    CHECK_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    echo ""
    if [ "$CHECK_CC" = "bbr" ]; then
        echo "${GREEN}🎉 优化成功!${PLAIN}"
        echo "当前拥塞控制: ${YELLOW}$CHECK_CC${PLAIN}"
        echo "当前队列算法: ${YELLOW}$CHECK_QDISC${PLAIN}"
    else
        echo "${RED}⚠️ 警告: 参数已写入，但内核似乎未生效。${PLAIN}"
        echo "请尝试重启系统。"
    fi
}

# [功能2] 恢复原始配置
function_restore() {
    echo "${CYAN}🔙 准备恢复原始配置...${PLAIN}"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "${RED}❌ 错误: 未找到原始备份文件 ($BACKUP_FILE)。${PLAIN}"
        echo "可能是你尚未运行过优化，或者手动删除了备份。"
        return
    fi

    cp "$BACKUP_FILE" "$CONFIG_FILE"
    echo "${GREEN}✅ 已将配置文件恢复至初始状态。${PLAIN}"
    
    echo "🔄 正在重载系统参数..."
    sysctl -p > /dev/null 2>&1
    
    echo "${GREEN}🎉 恢复完成! 系统已回到第一次运行脚本前的状态。${PLAIN}"
}

# --- 3. 菜单主界面 ---
clear
echo "========================================================"
echo "      🐧 Linux 网络参数调优脚本 (Pro版)"
echo "========================================================"
echo ""
echo "  1. 应用 [低重传 + 高速度] 优化方案 (推荐)"
echo "  2. 恢复 [使用前] 的原始配置文件"
echo "  0. 退出脚本"
echo ""
echo "========================================================"
printf "请输入数字 [0-2]: "
read choice

case "$choice" in
    1)
        function_optimize
        ;;
    2)
        function_restore
        ;;
    0)
        exit 0
        ;;
    *)
        echo "${RED}❌ 输入无效，请重新运行脚本。${PLAIN}"
        exit 1
        ;;
esac
