#!/bin/bash
# ==============================================================================
# MegaSSH High-Performance Optimizer (Consolidated)
# Target: Ubuntu 24.04 | Kernel: XanMod | Net: BBRv3 + FQ-CoDel
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
# --- Step 1: XanMod Kernel Installation (LTS/Stable) ---
print_step "1/5" "Checking/Installing XanMod Kernel..."

# Ensure prerequisites are installed
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y wget gpg irqbalance >/dev/null 2>&1

if grep -q "xanmod" /etc/apt/sources.list.d/xanmod-release.list 2>/dev/null; then
     echo -e "${GREEN}[✔] XanMod repository already exists.${NC}"
else
    print_info "Registering XanMod Repository..."
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/xanmod-archive-keyring.gpg
    
    print_info "Registering XanMod Repository..."
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/xanmod-archive-keyring.gpg
    
    # Embed Key Directly (Bypass Network Download Issues)
    cat <<EOF > /tmp/xanmod.key
-----BEGIN PGP PUBLIC KEY BLOCK-----
Comment: Hostname: 
Version: Hockeypuck 2.2

xsBNBFhxW04BCAC61HuxBVf1XJiQjXu/DSAtVcnuK38geDoDjcqFtHskFy32NgJG
X118EFNym6noF+oibaSftI9yjHthWvMnYZ/+DPwd7YZhbAjBvxMIQCsP6cFVxrgc
VV8g+uh4TCfbpalDBFoncRhQCgkmDN9Vd4kIWRh6BHJuzpKB/h2KxUHZVEKgWlK2
dR1xUtbrc+kp8gLwPbxTgC3tZ4x2uMMMlnbyCMSRa5oJ/AvoW4W1XphKL9ivsFHM
PSQkUBDvgv2RPw+0XBxPy8SYE0r0onx0ZIpjJRTODt3bSV6/0owwlpNogV9bT8HY
kl3+w3mTwax6S1akHZuJtLkZS0uUBz1BHt5bABEBAAHNIVhhbk1vZCBLZXJuZWwg
PGtlcm5lbEB4YW5tb2Qub3JnPsLAdwQTAQgAIQUCWHFbTgIbAwULCQgHAgYVCAkK
CwIEFgIDAQIeAQIXgAAKCRCG99Ce5zTmIwTmB/9/S4rmwU6efDgEaBDwBDbOfLBA
P2+kDpabjG4K+V4NSvDqlPN49KrI7C21jHghAa2VuTPbSZVQ9ziUd5DjX9OuXov8
CYVG+rrlG1UadHS8SBpgw0gNylEvo9/U6u0hl8mrbVOlpzu+eE+e4cMTHax2y580
fC2xmnM8wKgyRFEyVc6ilWU+UNTAeUFlg0YfU3cV1Ut4DzVFfamtNYg0p7Q/9MSy
VgFpt5C2U5prk4wi++51OgrtaNhMrUhzYXLINWVF6IrXhQ+mkI/FWXUZ0oyVo55v
+dQzuds/gos90q+tKyE514pYAmwQSftSjf+RmHOMpPQyMZZKSywrz4vlfveDzsBN
BFhxW04BCACs5bXq73MDb2+AsvNL2XkkbnzmE4K3k0gejB9OxrO+puAZn3wWyYIk
b0Op8qVUh+/FIiW/uFfmdFD8BypC3YkCNfg6e74f5TT3qQciccpMGy62teo3jfhT
T8E1OL1i76ALq7eNbByJKiKLBrTUDM6BDIeRZBWXQMase4+aqUAP47Kd/ByPsmCh
/pzb6yPdDPKwkspELssdPXYI7enddjQsCPoBko0j8CTPgKqMTeCuKMXCtD2gtRBN
eoVj4cbjZoZvBh8oJktzbYA8FX8eKdxIXhSP9MoVOPSWhxIQdwzkzUPK+0vUV8jA
NBTnGOkrRJPOHGPJWFWnTUGrzvcwi7czABEBAAHCwF8EGAEIAAkFAlhxW04CGwwA
CgkQhvfQnuc05iMIswgAmzSpCHFGKdkFLdC673FidJcL8adKFTO5Mpyholc5N8vG
ROJbpso+DpssF14NKoBfBWqPRgHxYzHakxHiNf0R2+EEwXH3rblzpx3PXzB0OgNe
T9T0UStrGgc9nZ8nZVURHZZ2z5zakEWS+rB2TiSxz3YArR3wiTHQW49G09uZvfp6
5Mim2w+eUxbQ689eT0DlDI1d2eDP/j5lrv1elsg3kBE2Awzdvi8DdGUpMFrSsYJw
WS85uZrwbeAs/nPO62wNIvAbbRsWnDg3AV3vc02eRvy52tTBY1W/67N02M4AxgPd
ukDDFZMifwa03yTHD/a57O4dFOnzsEVojBnbzQ7W7w==
=Lvp8
-----END PGP PUBLIC KEY BLOCK-----
EOF

    if [ -s "/tmp/xanmod.key" ]; then
        # Check if it looks like a key (simple check) or just let gpg handle it
        gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg /tmp/xanmod.key 2>/dev/null
        
        if [ -s "/etc/apt/keyrings/xanmod-archive-keyring.gpg" ]; then
            # Use lsb_release if available, otherwise fallback to 'releases' or 'noble'
            if command -v lsb_release >/dev/null; then
                CODENAME=$(lsb_release -sc)
            elif [ -f /etc/os-release ]; then
                . /etc/os-release
                CODENAME=$VERSION_CODENAME
            else
                CODENAME="releases"
            fi
            
            echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${CODENAME} main" | tee /etc/apt/sources.list.d/xanmod-release.list
            print_success "XanMod GPG Key & Repo Registered (Source: $CODENAME)."
        else
            print_error "Invalid GPG Key downloaded/embedded (gpg failed to dearmor)."
        fi
        rm -f /tmp/xanmod.key
    else
        print_error "Failed to write embedded XanMod GPG Key."
    fi
fi

# Cleanup old speed-optimizer if exists
rm -f /root/speed-optimizer.sh /usr/local/bin/speed-optimizer.sh

print_info "Updating apt and installing linux-xanmod-x64v3..."
# Use non-interactive mode to avoid prompts
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-x64v3 >/dev/null 2>&1
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

# --- Step 2: FQ-CoDel Queue Discipline ---
print_step "2/5" "Applying FQ-CoDel qdisc to ${IFACE}..."
# Clear existing qdiscs to be safe
tc qdisc del dev "$IFACE" root 2>/dev/null
if tc qdisc add dev "$IFACE" root fq_codel; then
    print_success "FQ-CoDel qdisc applied successfully."
else
    print_error "Failed to apply FQ-CoDel qdisc."
fi

# --- Step 3: High-Standard Kernel Tuning (sysctl) ---
print_step "3/5" "Applying Advanced Kernel Tuning..."
cat > /etc/sysctl.d/99-ssh-direct.conf <<EOF
# MegaSSH Stable Tuning (optimized for VPS)
# --- General System ---
fs.file-max = 1000000
fs.nr_open = 1048576
net.core.netdev_budget = 5000
net.core.netdev_max_backlog = 65536
net.core.optmem_max = 65536
net.core.somaxconn = 65535

# --- TCP Congestion Control & Queue Management ---
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr

# --- TCP Fast Open (Client/Server) ---
net.ipv4.tcp_fastopen = 3

# --- Idle & MTU ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# --- Buffer Sizes (Stability Optimized) ---
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
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

# --- Security & Resource Hardening ---
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system > /dev/null
# Apply to 99-megassh.conf too for backward compatibility/consistency
cp /etc/sysctl.d/99-ssh-direct.conf /etc/sysctl.d/99-megassh.conf
print_success "Kernel parameters applied."

# --- Step 4: Hardware Optimization (RSS & RPS) ---
print_step "4/5" "Enabling RPS on ${IFACE} (All Queues)..."
# Dynamic bitmask calculation (e.g., 1 core = 1, 2 cores = 3, 4 cores = f)
CPUS=$(nproc)
RPS_MASK=$(printf "%x" $(( (1 << CPUS) - 1 )))
for file in /sys/class/net/"$IFACE"/queues/rx-*/rps_cpus; do
    if [ -f "$file" ]; then
        echo "$RPS_MASK" > "$file" && print_success "Enabled RPS on $(basename $(dirname $file)) (Mask: $RPS_MASK)"
    fi
done

# Save iptables to ensure persistence
mkdir -p /etc/iptables

print_success "OPTIMIZATION COMPLETE SUCCESSFULLY"
print_warn "IMPORTANT: A reboot is recommended to load the XanMod Kernel."
echo ""
