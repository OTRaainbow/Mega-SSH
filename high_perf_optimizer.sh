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

# Visual Feedback Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[+] Starting High-Performance Optimization (Consolidated)...${NC}"

# Dynamic Interface Detection (Route to default gateway)
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$IFACE" ]; then
    echo -e "${RED}[✘] Could not detect primary network interface! Aborting.${NC}"
    exit 1
fi
echo -e "${YELLOW}[~] Detected Primary Interface: ${IFACE}${NC}"

# --- Step 1: XanMod Kernel Installation (LTS/Stable) ---
echo -e "${YELLOW}[~] Step 1: Checking/Installing XanMod Kernel...${NC}"
if grep -q "xanmod" /etc/apt/sources.list.d/xanmod-release.list 2>/dev/null; then
     echo -e "${GREEN}[✔] XanMod repository already exists.${NC}"
else
    echo -e "${YELLOW}[~] Registering XanMod Repository...${NC}"
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
fi

echo -e "${YELLOW}[~] Updating apt and installing linux-xanmod-x64v3...${NC}"
# Use non-interactive mode to avoid prompts
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-x64v3 irqbalance
if [ $? -ne 0 ]; then
    echo -e "${RED}[!] XanMod Kernel installation failed. Check internet connection or repo status.${NC}"
    # Continue anyway to apply other optimizations
else
    echo -e "${GREEN}[✔] XanMod Kernel installed/updated.${NC}"
fi

# --- Step 1.1: IRQ Balancing ---
echo -e "${YELLOW}[~] Step 1.1: Enabling IRQ Balancing...${NC}"
systemctl enable --now irqbalance

# --- Step 1.2: RAM Disk Logging (Zero Disk I/O) ---
echo -e "${YELLOW}[~] Step 1.2: Mounting /var/log as RAM Disk (256M)...${NC}"
if ! grep -q "tmpfs /var/log" /etc/fstab; then
    # Ensure /var/log is not already a mount point to avoid nested mounts or errors
    if ! mountpoint -q /var/log; then
        echo "tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=256m 0 0" >> /etc/fstab
        mount /var/log || echo -e "${RED}[!] Failed to mount /var/log as tmpfs${NC}"
        echo -e "${GREEN}[✔] /var/log mounted as tmpfs.${NC}"
    fi
else
    echo -e "${GREEN}[✔] /var/log already configured as tmpfs.${NC}"
fi

# --- Step 2: CAKE Queue Discipline ---
echo -e "${YELLOW}[~] Step 2: Applying CAKE qdisc to ${IFACE}...${NC}"
# Clear existing qdiscs to be safe
tc qdisc del dev "$IFACE" root 2>/dev/null
if tc qdisc add dev "$IFACE" root cake; then
    echo -e "${GREEN}[✔] CAKE qdisc applied successfully.${NC}"
else
    echo -e "${RED}[✘] Failed to apply CAKE qdisc (Kernel module missing?).${NC}"
fi

# --- Step 3: High-Standard Kernel Tuning (sysctl) ---
echo -e "${YELLOW}[~] Step 3: Applying Advanced Kernel Tuning...${NC}"
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
echo -e "${GREEN}[✔] Kernel parameters applied.${NC}"

# --- Step 4: Hardware Optimization (RSS & RPS) ---
echo -e "${YELLOW}[~] Step 4: Enabling RPS on ${IFACE} (All Queues)...${NC}"
# Set RPS to use all CPUs (Mask 'f' assumes 4 cores, simpler than calculating bitmask for now, or use ffffffff for max coverage)
for file in /sys/class/net/"$IFACE"/queues/rx-*/rps_cpus; do
    if [ -f "$file" ]; then
        echo "f" > "$file" && echo -e "    ${GREEN}✔ Enabled RPS on $(basename $(dirname $file))${NC}"
    fi
done

# --- Step 5: DPI Evasion (MSS Clamping) ---
echo -e "${YELLOW}[~] Step 5: Applying DPI Evasion (MSS Clamping: 1200)...${NC}"
# Idempotency: Check if rule exists first
if iptables -t mangle -C POSTROUTING -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200 2>/dev/null; then
     echo -e "${GREEN}[✔] MSS Clamp rule already exists.${NC}"
else
    iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
    echo -e "${GREEN}[✔] MSS Clamp rule applied to POSTROUTING.${NC}"
fi

# Save iptables to ensure persistence
mkdir -p /etc/iptables
if command -v iptables-save >/dev/null; then
    iptables-save > /etc/iptables/rules.v4
fi

echo -e "\n${GREEN}=================================================${NC}"
echo -e "${GREEN}   OPTIMIZATION COMPLETE SUCCESFULLY             ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "${YELLOW}[!] IMPORTANT: A reboot is recommended to load the XanMod Kernel.${NC}"
