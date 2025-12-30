#!/bin/bash

# =========================================================
# Linux TCP 10Gbps 极致优化脚本 (KVM 虚拟化专用版)
# 核心特性: 软中断优化 / 强制Offload / 128MB窗口 / BBR
# 适用场景: KVM/Xen/VMware 等虚拟化环境下的 10Gbps 网络
# =========================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.conf"
CUSTOM_SYSCTL_CONF="/etc/sysctl.d/99-extreme-kvm-10g.conf"
BACKUP_SYSCTL_CONF="/etc/sysctl.conf.bak_kvm_opt"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本!${PLAIN}"
    exit 1
fi

# =========================================================
#  工具与内核检查
# =========================================================
install_tools() {
    if ! command -v ethtool &> /dev/null; then
        echo -e "${BLUE}正在安装 ethtool (用于开启虚拟网卡 Offload)...${PLAIN}"
        if [ -f /etc/redhat-release ]; then
            yum install -y ethtool
        else
            apt-get update && apt-get install -y ethtool
        fi
    fi
}

install_kernel() {
    echo -e "${GREEN}正在尝试自动升级内核...${PLAIN}"
    if [ -f /etc/redhat-release ]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        if grep -q "release 7" /etc/redhat-release; then
            yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        elif grep -q "release 8" /etc/redhat-release; then
            yum install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
        else
             yum install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
        fi
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        if [ -f "/boot/grub2/grub.cfg" ]; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
            grub2-set-default 0
        fi
    else
        apt-get update
        apt-get install -y linux-image-amd64 || apt-get install -y linux-image-generic
        update-grub
    fi
    echo -e "${GREEN}内核安装完成! 请重启系统。${PLAIN}"
    read -p "是否立即重启? [y/n]: " is_reboot
    if [[ "${is_reboot}" == "y" || "${is_reboot}" == "Y" ]]; then
        reboot
    else
        exit 0
    fi
}

check_kernel() {
    kernel_version=$(uname -r | cut -d- -f1)
    major=$(echo $kernel_version | cut -d. -f1)
    minor=$(echo $kernel_version | cut -d. -f2)
    if [[ $major -lt 4 ]] || [[ $major -eq 4 && $minor -lt 9 ]]; then
        echo -e "${RED}内核版本过低 ($kernel_version)，无法跑满 10G BBR。${PLAIN}"
        read -p "是否升级内核? [y/n]: " choice
        [[ "$choice" == "y" ]] && install_kernel
    fi
}

# =========================================================
#  KVM 专用硬件/驱动层优化
# =========================================================

optimize_kvm_nic() {
    echo -e "${BLUE}正在针对 KVM 虚拟网卡进行 Offload 优化...${PLAIN}"
    NIC_NAME=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
    
    if [ -n "$NIC_NAME" ]; then
        echo -e "检测到主网卡: ${GREEN}$NIC_NAME${PLAIN}"
        
        # 1. 调整 Ring Buffer (如果虚拟网卡支持)
        ethtool -G "$NIC_NAME" rx max tx max >/dev/null 2>&1
        
        # 2. 强制开启 Offload (KVM 性能核心)
        # TSO (TCP Segmentation Offload)
        # GSO (Generic Segmentation Offload)
        # GRO (Generic Receive Offload)
        # SG  (Scatter-Gather)
        # 开启这些功能可以让宿主机处理分片，极大降低虚拟机 CPU 负载
        ethtool -K "$NIC_NAME" tso on gso on gro on sg on >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
             echo -e "网卡 Offload: ${GREEN}已强制开启 (TSO/GSO/GRO)${PLAIN}"
        else
             echo -e "网卡 Offload: ${YELLOW}部分特性开启失败 (取决于宿主机配置)${PLAIN}"
        fi

        # 3. 增加队列长度
        ip link set dev "$NIC_NAME" txqueuelen 10000 >/dev/null 2>&1
    else
        echo -e "${YELLOW}未检测到主网卡，跳过驱动层优化。${PLAIN}"
    fi
}

# =========================================================
#  KVM 专用 Sysctl 优化
# =========================================================

apply_kvm_optimization() {
    install_tools
    optimize_kvm_nic

    echo -e "${BLUE}正在应用 [KVM 10Gbps] TCP 配置...${PLAIN}"

    [ ! -f "$BACKUP_SYSCTL_CONF" ] && cp "$SYSCTL_CONF" "$BACKUP_SYSCTL_CONF"

    cat > "$CUSTOM_SYSCTL_CONF" <<EOF
# =================================================================
# KVM 10Gbps TCP 极致优化配置
# =================================================================

# --- KVM 软中断与批量处理优化 (关键) ---
# 增加一次软中断处理的数据包数量，减少上下文切换开销
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
# 增加积压队列，防止虚拟机处理不过来时丢包
net.core.netdev_max_backlog = 300000

# --- 拥塞控制 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 内存缓冲区 (128MB for 10G BDP) ---
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 262144 134217728
net.ipv4.tcp_wmem = 4096 262144 134217728
net.ipv4.tcp_window_scaling = 1

# --- KVM 环境下的发送优化 ---
# 开启自动软木塞，允许合并小包，显著提升虚拟化环境吞吐量
net.ipv4.tcp_autocorking = 1
# 稍微放宽低延迟限制，避免在虚拟化环境中因 CPU 抖动导致吞吐下降
# 64KB 是 KVM 10G 环境下的甜点值
net.ipv4.tcp_notsent_lowat = 65536

# --- 连接与安全 ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_local_port_range = 10000 65535

# --- 禁止保存 Metrics ---
# 虚拟环境路由可能变动，不缓存之前的 TCP 指标
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.ip_forward = 0
EOF

    modprobe tcp_bbr 2>/dev/null
    sysctl -p "$CUSTOM_SYSCTL_CONF" >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1

    echo -e "${GREEN}KVM 10Gbps 优化配置已应用!${PLAIN}"
    echo -e "Netdev Budget: ${GREEN}600 (高并发优化)${PLAIN}"
    echo -e "TCP 缓冲区: ${GREEN}128 MB${PLAIN}"
}

restore_config() {
    echo -e "${BLUE}正在恢复配置...${PLAIN}"
    rm -f "$CUSTOM_SYSCTL_CONF"
    NIC_NAME=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
    if [ -n "$NIC_NAME" ]; then
        ip link set dev "$NIC_NAME" txqueuelen 1000 >/dev/null 2>&1
    fi
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}配置已恢复。${PLAIN}"
}

show_menu() {
    clear
    echo -e "================================================="
    echo -e "    ${GREEN}Linux KVM 10Gbps 极致 TCP 优化脚本${PLAIN}    "
    echo -e "    ${YELLOW}针对 Virtio 驱动与软中断优化${PLAIN}"
    echo -e "================================================="
    echo -e " ${GREEN}1.${PLAIN} 应用 [KVM + 10Gbps] 优化"
    echo -e " ${GREEN}2.${PLAIN} 恢复默认配置"
    echo -e " ${GREEN}3.${PLAIN} 退出"
    echo -e "================================================="
    read -p " 请输入: " num
    case "$num" in
        1) check_kernel; apply_kvm_optimization ;;
        2) restore_config ;;
        3) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
