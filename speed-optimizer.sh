#!/bin/bash

# ==============================================================================
# Speed Optimizer (BBR + Sysctl)
# Optimized for Ubuntu 24.04 (Kernel 6.x)
# ==============================================================================

echo -e "\033[1;36m[+] Applying Network Speed Optimizations...\033[0m"

# 1. Enable BBR
# Ubuntu 24.04 Kernel 6.x has BBR built-in.
echo -e "\033[1;33m[~] Enabling TCP BBR...\033[0m"
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

# 2. Advanced Sysctl Tuning
# Based on Google BBR recommendations and High-Perf servers
# --- IRQ Affinity (Interrupt Balancing) ---
echo -e "\033[1;33m[~] Balancing IRQs (Multi-Core Optimization)...\033[0m"
apt install -y irqbalance
systemctl enable --now irqbalance

# --- RAM Disk Logging (Zero Disk I/O) ---
# Mounts /var/log as RAM to eliminate disk wait
echo -e "\033[1;33m[~] Mounting /var/log as RAM Disk...\033[0m"
if ! grep -q "tmpfs /var/log" /etc/fstab; then
    echo "tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=128m 0 0" >> /etc/fstab
    mount -o remount /var/log || mount -t tmpfs -o size=128m tmpfs /var/log
fi
echo -e "\033[1;33m[~] Tuning Kernel Parameters...\033[0m"
cat >> /etc/sysctl.conf <<EOF

# --- Speed Optimizer Settings (High Volume Pooling) ---
fs.file-max = 1000000
net.core.netdev_budget = 5000
net.core.netdev_max_backlog = 65536
net.core.optmem_max = 65536
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.somaxconn = 65535
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216

net.ipv4.ip_forward = 1
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
# Global Congestion & Buffer Optimization
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_window_scaling = 1

# --- Ultra-Scale TCP Hardening ("Pro" Numbers) ---
# Prevents "Out of socket memory" during massive disconnects
net.ipv4.tcp_max_orphans = 262144
# Quickly closes dead sockets to free RAM
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_probes = 3
# Ring buffer backlog for traffic spikes
net.core.netdev_max_backlog = 65535
# Queue Discipline (Fair Queueing for BBRv3 Optimization)
net.core.default_qdisc = fq

# Disable IPv6 (Optional but recommended for speed logic if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
# --------------------------------
EOF

# Apply Changes
sysctl -p

echo -e "\033[1;32m[+] Network Optimization Complete.\033[0m"
