#!/bin/bash

# =========================================================
# Linux TCP 极致优化脚本 (终极版)
# 核心特性: 自动内核升级 / 极致低延迟 / 极致带宽 / 智能适配
# 适配系统: CentOS 7+ / Debian 9+ / Ubuntu 16+ / Alma / Rocky
# =========================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.conf"
CUSTOM_SYSCTL_CONF="/etc/sysctl.d/99-extreme-tcp.conf"
BACKUP_SYSCTL_CONF="/etc/sysctl.conf.bak_before_opt"

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本!${PLAIN}"
    exit 1
fi

# =========================================================
#  内核检查与升级模块
# =========================================================

get_os_release() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    else
        release="unknown"
    fi
}

install_kernel() {
    get_os_release
    echo -e "${GREEN}正在尝试自动升级内核...${PLAIN}"
    
    if [[ "${release}" == "centos" ]]; then
        # CentOS/Alma/Rocky: 使用 ELRepo 安装最新内核
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        if grep -q "release 7" /etc/redhat-release; then
            yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        elif grep -q "release 8" /etc/redhat-release; then
            yum install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
        else
             # 尝试通用安装 (CentOS Stream / 9)
             yum install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
        fi
        
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        
        # 更新引导
        if [ -f "/boot/grub2/grub.cfg" ]; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
            grub2-set-default 0
        elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
            grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
            grub2-set-default 0
        fi

    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        # Debian/Ubuntu: 更新系统并安装最新可用内核
        apt-get update
        apt-get install -y linux-image-amd64 || apt-get install -y linux-image-generic
        update-grub
    else
        echo -e "${RED}不支持的系统，无法自动升级内核，请手动升级。${PLAIN}"
        return 1
    fi

    echo -e "${GREEN}内核安装完成! 需要重启系统才能生效。${PLAIN}"
    read -p "是否立即重启? [y/n]: " is_reboot
    if [[ "${is_reboot}" == "y" || "${is_reboot}" == "Y" ]]; then
        reboot
    else
        echo -e "${YELLOW}请稍后手动重启，重启后再次运行脚本开启 BBR。${PLAIN}"
        exit 0
    fi
}

check_kernel_and_bbr() {
    kernel_version=$(uname -r | cut -d- -f1)
    major_version=$(echo $kernel_version | cut -d. -f1)
    minor_version=$(echo $kernel_version | cut -d. -f2)

    echo -e "当前内核版本: ${BLUE}$kernel_version${PLAIN}"

    if [[ $major_version -lt 4 ]] || [[ $major_version -eq 4 && $minor_version -lt 9 ]]; then
        echo -e "${RED}警告: 当前内核版本低于 4.9，无法开启 BBR。${PLAIN}"
        echo -e "${YELLOW}检测到您需要极致性能，建议升级内核。${PLAIN}"
        read -p "是否尝试自动升级内核? [y/n] (默认 n): " upgrade_choice
        if [[ "${upgrade_choice}" == "y" || "${upgrade_choice}" == "Y" ]]; then
            install_kernel
        else
            echo -e "${YELLOW}已取消内核升级。脚本将应用除 BBR 外的其他优化。${PLAIN}"
            return 1
        fi
    fi
    return 0
}

# =========================================================
#  核心优化模块
# =========================================================

apply_optimization() {
    echo -e "${BLUE}正在应用 [低延迟+低重传+高速度] TCP 配置...${PLAIN}"

    # 备份
    if [ ! -f "$BACKUP_SYSCTL_CONF" ]; then
        cp "$SYSCTL_CONF" "$BACKUP_SYSCTL_CONF"
    fi

    # 写入配置 (针对非NAT环境特化)
    cat > "$CUSTOM_SYSCTL_CONF" <<EOF
# =================================================================
# 极致 TCP 优化配置 (Non-NAT Specialized)
# =================================================================

# --- 基础资源限制 ---
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192

# --- 拥塞控制 (BBR + FQ) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP 窗口与缓冲区 (平衡性能与内存) ---
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 8192 262144 16777216
net.ipv4.tcp_wmem = 8192 262144 16777216
net.ipv4.tcp_window_scaling = 1

# --- 极致低延迟核心设置 ---
# 限制发送缓冲区积压，极大降低 RTT
net.ipv4.tcp_notsent_lowat = 16384
# 空闲后立即恢复全速发送
net.ipv4.tcp_slow_start_after_idle = 0

# --- 非 NAT 环境特化设置 ---
# 开启时间戳: 在非 NAT 环境下，开启可更精准计算 RTT 并启用 PAWS，提升高速网络稳定性
net.ipv4.tcp_timestamps = 1
# 开启选择性确认 (SACK, DSACK, FACK) 快速处理丢包
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1

# --- 连接复用与握手优化 ---
# 允许重用 TIME_WAIT 连接 (Web/代理服务核心优化)
net.ipv4.tcp_tw_reuse = 1
# 开启 TCP Fast Open (减少一次 RTT)
net.ipv4.tcp_fastopen = 3
# 缩短连接保活时间
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
# 缩短 FIN 等待时间
net.ipv4.tcp_fin_timeout = 30

# --- 高并发队列 ---
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.tcp_syncookies = 1

# --- 路由设置 ---
# 禁止 IP 转发 (除非你是路由器，否则服务器应关闭此项以节省 CPU)
net.ipv4.ip_forward = 0
EOF

    # 加载模块与配置
    modprobe tcp_bbr 2>/dev/null
    sysctl -p "$CUSTOM_SYSCTL_CONF" >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1

    echo -e "${GREEN}优化配置已应用!${PLAIN}"
    
    # 结果验证
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "拥塞控制: ${GREEN}BBR 已启动 (极致速度)${PLAIN}"
    else
        echo -e "拥塞控制: ${RED}BBR 未启动 (可能需要重启或内核不支持)${PLAIN}"
    fi
    echo -e "队列管理: ${GREEN}$(sysctl net.core.default_qdisc | awk '{print $3}')${PLAIN}"
    echo -e "延迟优化: ${GREEN}tcp_notsent_lowat = 16k (已生效)${PLAIN}"
}

restore_config() {
    echo -e "${BLUE}正在恢复配置...${PLAIN}"
    rm -f "$CUSTOM_SYSCTL_CONF"
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}系统配置已恢复至默认状态。${PLAIN}"
}

# =========================================================
#  主菜单
# =========================================================

show_menu() {
    clear
    echo -e "================================================="
    echo -e "    ${GREEN}Linux TCP 终极优化脚本 (非 NAT 版)${PLAIN}    "
    echo -e "================================================="
    echo -e " ${GREEN}1.${PLAIN} 使用 [低延迟+低重传+高速度] TCP 配置"
    echo -e " ${GREEN}2.${PLAIN} 恢复使用脚本前的配置"
    echo -e " ${GREEN}3.${PLAIN} 退出脚本"
    echo -e "================================================="
    read -p " 请输入选择 [1-3]: " num

    case "$num" in
        1)
            check_kernel_and_bbr
            # 无论是否升级内核，都尝试应用配置(如果未升级则BBR不生效但其他生效)
            apply_optimization
            ;;
        2)
            restore_config
            ;;
        3)
            exit 0
            ;;
        *)
            echo -e "${RED}请输入正确的数字 [1-3]${PLAIN}"
            sleep 1
            show_menu
            ;;
    esac
}

show_menu
