#!/bin/bash

# ==============================================================================
# Speed Optimizer (BBR + Sysctl)
# Optimized for Ubuntu 24.04 (Kernel 6.x)
# ==============================================================================

# --- Professional UI & Colors ---
# Bold
BBLACK='\033[1;30m'       # Black
BRED='\033[1;31m'         # Red
BGREEN='\033[1;32m'       # Green
BYELLOW='\033[1;33m'      # Yellow
BBLUE='\033[1;34m'        # Blue
BPURPLE='\033[1;35m'      # Purple
BCYAN='\033[1;36m'        # Cyan
BWHITE='\033[1;37m'       # White

# Regular
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_step() {
    local step_num=$1
    local step_msg=$2
    echo -e "${BBLUE}[ STEP ${step_num} ]${NC} ${BWHITE}${step_msg}${NC}"
}

print_info() {
    echo -e "${BBLUE}[ INFO ]${NC} $1"
}

print_success() {
    echo -e "${BGREEN}[  OK  ]${NC} $1"
}

print_error() {
    echo -e "${BRED}[ FAIL ]${NC} $1"
}

print_warn() {
    echo -e "${BYELLOW}[ WARN ]${NC} $1"
}

print_step "1/4" "Applying Network Speed Optimizations..."

# 1. Enable BBR
# Ubuntu 24.04 Kernel 6.x has BBR built-in.
print_info "Enabling TCP BBR..."
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

# 2. Advanced Sysctl Tuning
# Based on Google BBR recommendations and High-Perf servers
# --- IRQ Affinity (Interrupt Balancing) ---
print_step "2/4" "Balancing IRQs (Multi-Core Optimization)..."
apt install -y irqbalance
systemctl enable --now irqbalance

# --- RAM Disk Logging (Zero Disk I/O) ---
# Mounts /var/log as RAM to eliminate disk wait
print_step "3/4" "Mounting /var/log as RAM Disk..."
if ! grep -q "tmpfs /var/log" /etc/fstab; then
    # Ensure /var/log is not already a mount point to avoid nested mounts or errors
    if ! mountpoint -q /var/log; then
        echo "tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=256m 0 0" >> /etc/fstab
        mount /var/log || print_error "Failed to mount /var/log as tmpfs"
    fi
fi

print_step "4/4" "Tuning Kernel Parameters (via /etc/sysctl.d/99-megassh.conf)..."
cat > /etc/sysctl.d/99-megassh.conf <<EOF
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
net.ipv4.tcp_reordering = 3

# --- Ultra-Scale TCP Hardening ("Pro" Numbers) ---
# Prevents "Out of socket memory" during massive disconnects
net.ipv4.tcp_max_orphans = 262144
# Quickly closes dead sockets to free RAM
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_probes = 3

# Queue Discipline (Fair Queueing for BBR optimization)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Disable IPv6 (Optional but recommended for speed logic if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

# Apply Changes
sysctl --system

print_success "Network Optimization Complete."
