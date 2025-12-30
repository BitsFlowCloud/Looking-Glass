#!/bin/bash

# 1. 检查是否为 Root 用户
if [ "$(id -u)" != "0" ]; then
    echo "❌ 错误: 必须使用 Root 权限运行此脚本。"
    echo "请使用 'sudo -i' 切换用户后重试。"
    exit 1
fi

# 2. 定义备份文件名（带时间戳）
CURRENT_TIME=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/etc/sysctl.conf.bak.$CURRENT_TIME"

# 3. 执行备份
if [ -f /etc/sysctl.conf ]; then
    echo "💾 正在备份原配置文件..."
    cp /etc/sysctl.conf "$BACKUP_FILE"
    echo "✅ 备份已保存至: $BACKUP_FILE"
else
    echo "⚠️ 未找到 /etc/sysctl.conf，将创建新文件。"
fi

# 4. 完全覆写 /etc/sysctl.conf
# 注意：使用 '>' 是覆盖模式，不是追加模式
echo "🚀 正在写入高性能优化配置..."
cat > /etc/sysctl.conf << EOF
# =================================================================
# High Performance TCP Tuning for Minimal Retransmission & Max Speed
# Generated at: $(date)
# =================================================================

# --- 核心拥塞控制与队列 (BBR + FQ) ---
# 必须先开启 fq 才能开启 bbr
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 降低重传与延迟的关键优化 (Bufferbloat Killer) ---
# 限制发送缓冲区中未发送数据的大小，防止缓冲区膨胀导致的延迟和无效重传
# 这是降低延迟和重传率的最关键参数之一
net.ipv4.tcp_notsent_lowat = 16384

# --- ECN (显式拥塞通知) ---
# 允许路由通知拥塞而非直接丢包。
# 注意：如果网络极其老旧可能导致断连，fallback 保证了兼容性
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1

# --- SACK & 快速恢复 ---
# 开启选择性应答，只重传丢失的数据段，极大降低重传带来的吞吐损耗
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
# 启用早期重传 (Early Retransmit)，对小流优化效果明显
net.ipv4.tcp_early_retrans = 3

# --- 缓冲区调优 (10Gbps Ready) ---
# 这里的数值经过计算，约为 48MB-64MB，足够应对高 BDP (带宽时延积) 链路
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# --- 网络稳定性与MTU ---
# 自动探测 MTU，防止巨型包造成的黑洞丢包
net.ipv4.tcp_mtu_probing = 1
# 减少 FIN_WAIT2 等待时间，防止僵尸连接耗尽资源
net.ipv4.tcp_fin_timeout = 30

# --- 能够处理高并发连接 ---
net.ipv4.ip_local_port_range = 10000 65000
net.netfilter.nf_conntrack_max = 1000000
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# --- 安全与防坑设置 ---
# 🚫 严禁开启 tcp_tw_recycle (导致 NAT 用户断网)
net.ipv4.tcp_tw_recycle = 0
# ✅ 允许重用 TIME_WAIT socket
net.ipv4.tcp_tw_reuse = 1
# ✅ 开启时间戳 (高性能必要)
net.ipv4.tcp_timestamps = 1
# ✅ 开启 ARP 过滤，防止多网卡环境下的 ARP 混乱
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
EOF

# 5. 应用更改
echo "🔄 正在应用新配置..."
sysctl -p > /dev/null 2>&1

# 6. 验证 BBR 是否开启
echo "🔍 验证结果:"
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
QDISC_STATUS=$(sysctl net.core.default_qdisc | awk '{print $3}')

if [[ "$BBR_STATUS" == "bbr" && "$QDISC_STATUS" == "fq" ]]; then
    echo "✅ 成功! TCP 拥塞控制已设置为: BBR"
    echo "✅ 成功! 队列调度算法已设置为: FQ"
    echo "🎉 优化完成。原配置已备份至 $BACKUP_FILE"
else
    echo "⚠️ 警告: BBR 似乎未生效，请检查你的内核是否支持 BBR (需 Kernel 4.9+)。"
    echo "当前状态: $BBR_STATUS / $QDISC_STATUS"
fi
