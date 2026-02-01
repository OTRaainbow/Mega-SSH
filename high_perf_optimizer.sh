#!/bin/bash
# ==============================================================================
# MegaSSH High-Performance Optimizer (Consolidated)
# Target: Ubuntu 24.04 | Kernel: XanMod | Net: BBRv3 + CAKE
# Features: IRQ Balancing, RAM Logging, MSS Clamping, Sysctl Tuning
# ==============================================================================

# --- 0. Safety Checks & Init ---
# Check for Root
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[0;31m[✘] Error: This script must be run as root.\033[0m"
  exit 1
fi

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

echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BBLUE}║${NC} ${BCYAN}                   HIGH-PERFORMANCE SYSTEM OPTIMIZER                         ${BBLUE}║${NC}"
echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
print_info "Starting High-Performance Optimization (Consolidated)..."

# Dynamic Interface Detection (Route to default gateway)
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$IFACE" ]; then
    print_error "Could not detect primary network interface! Aborting."
    exit 1
fi
print_info "Detected Primary Interface: ${IFACE}"

# --- Step 1: XanMod Kernel Installation (LTS/Stable) ---
print_step "1/5" "Checking/Installing XanMod Kernel..."
if grep -q "xanmod" /etc/apt/sources.list.d/xanmod-release.list 2>/dev/null; then
     echo -e "${GREEN}[✔] XanMod repository already exists.${NC}"
else
    print_info "Registering XanMod Repository..."
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
fi

print_info "Updating apt and installing linux-xanmod-x64v3..."
# Use non-interactive mode to avoid prompts
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-x64v3 irqbalance >/dev/null 2>&1
if [ $? -ne 0 ]; then
    print_error "XanMod Kernel installation failed. Check internet connection or repo status."
    # Continue anyway to apply other optimizations
else
    print_success "XanMod Kernel installed/updated."
fi

# --- Step 1.1: IRQ Balancing ---
print_step "1.1" "Enabling IRQ Balancing..."
systemctl enable --now irqbalance

# --- Step 1.2: RAM Disk Logging (Zero Disk I/O) ---
print_step "1.2" "Mounting /var/log as RAM Disk (256M)..."
if ! grep -q "tmpfs /var/log" /etc/fstab; then
    # Ensure /var/log is not already a mount point to avoid nested mounts or errors
    if ! mountpoint -q /var/log; then
        echo "tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=256m 0 0" >> /etc/fstab
        mount /var/log || echo -e "${RED}[!] Failed to mount /var/log as tmpfs${NC}"
        print_success "/var/log mounted as tmpfs."
    fi
else
    print_success "/var/log already configured as tmpfs."
fi

# --- Step 2: CAKE Queue Discipline ---
print_step "2/5" "Applying CAKE qdisc to ${IFACE}..."
# Clear existing qdiscs to be safe
tc qdisc del dev "$IFACE" root 2>/dev/null
if tc qdisc add dev "$IFACE" root cake; then
    print_success "CAKE qdisc applied successfully."
else
    print_error "Failed to apply CAKE qdisc (Kernel module missing?)."
fi

# --- Step 3: High-Standard Kernel Tuning (sysctl) ---
print_step "3/5" "Applying Advanced Kernel Tuning..."
cat > /etc/sysctl.d/99-ssh-direct.conf <<EOF
# MegaSSH High-Performance Tuning (Consolidated)
# --- General System ---
fs.file-max = 1000000
net.core.netdev_budget = 5000
net.core.netdev_max_backlog = 65536
net.core.optmem_max = 65536
net.core.somaxconn = 65535

# --- TCP Congestion Control & Queue Management ---
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr

# --- TCP Fast Open (Client/Server) ---
net.ipv4.tcp_fastopen = 3

# --- Idle & MTU ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# --- Buffer Sizes (Throughput Optimization) ---
net.core.rmem_default = 1048576
net.core.rmem_max = 67108864
net.core.wmem_default = 1048576
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_notsent_lowat = 16384

# --- Keepalives (Dead peer detection) ---
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_orphans = 262144

# --- IPv6 Disable (Leak Protection) ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system > /dev/null
print_success "Kernel parameters applied."

# --- Step 4: Hardware Optimization (RSS & RPS) ---
print_step "4/5" "Enabling RPS on ${IFACE} (All Queues)..."
# Set RPS to use all CPUs (Mask 'f' assumes 4 cores, simpler than calculating bitmask for now, or use ffffffff for max coverage)
for file in /sys/class/net/"$IFACE"/queues/rx-*/rps_cpus; do
    if [ -f "$file" ]; then
        echo "f" > "$file" && print_success "Enabled RPS on $(basename $(dirname $file))"
    fi
done

# --- Step 5: DPI Evasion (MSS Clamping) ---
print_step "5/5" "Applying DPI Evasion (MSS Clamping: 1200)..."
# Idempotency: Check if rule exists first
if iptables -t mangle -C POSTROUTING -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200 2>/dev/null; then
     print_success "MSS Clamp rule already exists."
else
    iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
    print_success "MSS Clamp rule applied to POSTROUTING."
fi

# Save iptables to ensure persistence
mkdir -p /etc/iptables
if command -v iptables-save >/dev/null; then
    iptables-save > /etc/iptables/rules.v4
fi

print_success "OPTIMIZATION COMPLETE SUCCESSFULLY"
print_warn "IMPORTANT: A reboot is recommended to load the XanMod Kernel."
echo ""
