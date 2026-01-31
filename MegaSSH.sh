#!/bin/bash

# ==============================================================================
# MegaSSH Implementation - Direct Mode (Consolidated & Secured)
# OS: Ubuntu 24.04 (Noble) Optimized
# Features: HAProxy Decoy, ChaCha20, UDPGW, BBR, Geofencing, Stunnel
# ==============================================================================

# --- UI & Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII Banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  __  __                  SSSSS   SSSSS  HH   HH "
    echo " |  \/  | ___  __ _  __ _SS      SS      HH   HH "
    echo " | |\/| |/ _ \/ _\` |/ _\` |SSSSS   SSSSS  HHH HHH "
    echo " | |  | |  __/ (_| | (_| |    SS      SS HH   HH "
    echo " |_|  |_|\___|\__, |\__,_|SSSSS   SSSSS  HH   HH "
    echo "              |___/                              "
    echo "         High-Security VPN Installer             "
    echo -e "${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}  Target OS: Ubuntu 24.04 | Features: 7-Point Security${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
}

# Spinner Function for long tasks
run_with_spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Helper Functions & Logging
LOG_FILE="/root/megassh_install.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

print_step() {
    echo -e "${CYAN}[Step $1] ${NC}$2"
}

print_success() {
    echo -e "${GREEN}[✔] $1${NC}"
}

print_error() {
    echo -e "${RED}[✘] $1${NC}"
}

# --- Initialization ---
print_banner
echo "Installation started at $(date)" >> $LOG_FILE

# Variables
PORT_SSH_INTERNAL=2222
PORT_HAPROXY=443
PORT_UDPGW=7301
PORT_NGINX=8080
PASSWORD="@MonGleKhos2024"

# --- GITHUB DEPLOYMENT CONFIG ---
# YOUR GITHUB CONFIGURATION:
REPO_BASE="https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main"
# --------------------------------

# Helper: Download Script
fetch_script() {
    local script_name=$1
    if [ ! -f "$script_name" ]; then
        # Check if URL is configured
        if [[ "$REPO_BASE" == *"ChangeMe"* ]]; then
            echo -e "${RED}[!] Error: REPO_BASE is not configured!${NC}"
            echo -e "${YELLOW}    1. Open MegaSSH.sh${NC}"
            echo -e "${YELLOW}    2. Change 'ChangeMe/MegaSSH' to your GitHub User/Repo${NC}"
            echo -e "${YELLOW}    3. OR place '$script_name' in this directory manually.${NC}"
            echo "Error: REPO_BASE unconfigured while fetching $script_name" >> $LOG_FILE
            exit 1
        fi

        local target_url="${REPO_BASE}/${script_name}"
        echo -e "${YELLOW}[~] Fetching $script_name from: $target_url${NC}"
        
        wget -q -O "$script_name" "$target_url"
        local ret=$?
        
        if [ $ret -ne 0 ]; then
            print_error "Failed to download $script_name."
            echo -e "${RED}    Details:${NC}"
            echo -e "    - URL: $target_url"
            echo -e "    - Wget Exit Code: $ret"
            echo "Failed to fetch $target_url (Exit: $ret)" >> $LOG_FILE
            exit 1
        fi
        echo -e "${GREEN}    Successfully downloaded $script_name${NC}"
    else
        echo -e "${GREEN}[✔] Found local file: $script_name${NC}"
    fi
    chmod +x "$script_name"
}

# Set non-interactive for apt
export DEBIAN_FRONTEND=noninteractive

# 1. Update & Install Dependencies
print_step "1/10" "Updating System & Installing Dependencies..."
(apt update && apt upgrade -y && apt install -y curl socat wget git cmake make gcc build-essential nginx haproxy ipset iptables-persistent ufw unzip tar cron) >> $LOG_FILE 2>&1 &
run_with_spinner $!
print_success "Dependencies Installed"

# Set Root Password
echo -e "$PASSWORD\n$PASSWORD" | passwd root >> $LOG_FILE 2>&1
print_success "Root Password Set"

# 2. System Optimizations (External)
print_step "2/10" "Applying Kernel Optimizations (BBRv3)..."
fetch_script "speed-optimizer.sh"
./speed-optimizer.sh > /dev/null 2>&1
print_success "Kernel Optimized (speed-optimizer.sh)"

# 3. UDPGW Installation (External)
print_step "3/10" "Building UDPGW (BadVPN)..."
fetch_script "UDPGW.sh"
./UDPGW.sh > /dev/null 2>&1 &
run_with_spinner $!
print_success "UDPGW Service Started (Port $PORT_UDPGW)"

# 4. SSH Security Configuration (Hybrid Multiplexing)
print_step "4/10" "Hardening SSH (Split-Stream: Ports 2222-2225)..."

# UBUNTU 24.04 FIX: Disable Socket Activation (Kills Port 22)
print_step "4a" "Disabling ssh.socket (Fixing Port 22 Leak)..."
systemctl stop ssh.socket
systemctl disable ssh.socket
systemctl mask ssh.socket

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
# Settings
# Remove existing ports and add split-stream ports (0.0.0.0 for Direct Access)
sed -i "/^Port/d" /etc/ssh/sshd_config
sed -i "/^ListenAddress/d" /etc/ssh/sshd_config
# Note: No ListenAddress = 0.0.0.0 (Open to World)
echo "Port 2222" >> /etc/ssh/sshd_config
echo "Port 2223" >> /etc/ssh/sshd_config
echo "Port 2224" >> /etc/ssh/sshd_config
echo "Port 2225" >> /etc/ssh/sshd_config

sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
# Security Hardening (High Volume Optimization)
if ! grep -q "^DebianBanner" /etc/ssh/sshd_config; then
    echo "DebianBanner no" >> /etc/ssh/sshd_config
fi
if ! grep -q "^MaxSessions" /etc/ssh/sshd_config; then
    echo "MaxSessions 100" >> /etc/ssh/sshd_config
fi
# Active Probing Defense
if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
    echo "MaxStartups 10:30:60" >> /etc/ssh/sshd_config
fi
if ! grep -q "^PerSourceMaxStartups" /etc/ssh/sshd_config; then
    echo "PerSourceMaxStartups 1" >> /etc/ssh/sshd_config
fi
# Disk I/O Minimization
if ! grep -q "^LogLevel" /etc/ssh/sshd_config; then
    echo "LogLevel QUIET" >> /etc/ssh/sshd_config
fi
# Cipher & Protocol Tuning
if ! grep -q "^Ciphers" /etc/ssh/sshd_config; then
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com" >> /etc/ssh/sshd_config
fi
if ! grep -q "^KexAlgorithms" /etc/ssh/sshd_config; then
    echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org" >> /etc/ssh/sshd_config
fi
if ! grep -q "^MACs" /etc/ssh/sshd_config; then
    echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com" >> /etc/ssh/sshd_config
fi
# Enable Standard Service (Since Socket is dead)
systemctl unmask ssh
systemctl enable ssh
systemctl restart ssh
print_success "SSH Hardened & Split (Ports 2222-2225)"

# 5. Nginx Decoy Site (Digikala)
print_step "5/10" "Deploying Decoy Site (Digikala)..."
systemctl stop nginx
rm -rf /usr/share/nginx/html/*
cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>فروشگاه اینترنتی دیجی‌کالا</title>
    <style>
        body { font-family: 'IranYekan', Tahoma, sans-serif; background-color: #f0f0f1; text-align: center; padding-top: 100px; margin: 0; }
        .container { background: white; width: 90%; max-width: 600px; margin: 0 auto; padding: 40px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); }
        .logo { color: #ef394e; font-size: 40px; font-weight: bold; margin-bottom: 20px; }
        h1 { color: #424750; font-size: 18px; margin-bottom: 10px; }
        p { color: #81858b; font-size: 14px; }
        .loader { border: 4px solid #f3f3f3; border-top: 4px solid #ef394e; border-radius: 50%; width: 30px; height: 30px; animation: spin 1s linear infinite; margin: 20px auto; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">digikala</div>
        <h1>در حال بارگذاری...</h1>
        <p>لطفاً شکیبا باشید، در حال اتصال به سرورهای دیجی‌کالا هستیم.</p>
        <div class="loader"></div>
    </div>
</body>
</html>
EOF
# Nginx Config
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 127.0.0.1:${PORT_NGINX};
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
        add_header Host "digikala.com";
        add_header Server "Digikala-Cdn";
        add_header X-Powered-By "PHP/8.1";
    }
    # Disk I/O Optimization
    access_log off;
    error_log /dev/null crit;
}
EOF
systemctl restart nginx > /dev/null 2>&1
print_success "Nginx Decoy Live (Digikala - Port $PORT_NGINX)"

# 6. HAProxy Multiplexing (SSH Priority)
print_step "6/10" "Configuring HAProxy Split-Stream (Port 443 -> SSH Default)..."
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
frontend stats
    mode http
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
frontend multiplexer_443
    bind *:${PORT_HAPROXY}
    mode tcp
    tcp-request inspect-delay 5s
    # Detect Obvious HTTP/TLS (Decoy Candidate)
    acl is_http req.payload(0,3) -m str GET POST HEAD OPTIONS
    acl is_tls req.ssl_hello_type gt 0
    
    # Routing Logic: If it looks like HTTP or TLS, send to Decoy. Else assume SSH.
    use_backend web_decoy_backend if is_http
    use_backend web_decoy_backend if is_tls
    default_backend ssh_backend

backend ssh_backend
    mode tcp
    balance roundrobin
    server ssh_srv_1 127.0.0.1:2222 check
    server ssh_srv_2 127.0.0.1:2223 check
    server ssh_srv_3 127.0.0.1:2224 check
    server ssh_srv_4 127.0.0.1:2225 check
backend web_decoy_backend
    mode tcp
    server web_srv 127.0.0.1:${PORT_NGINX} check
EOF
sed -i 's/send-proxy-v2//g' /etc/haproxy/haproxy.cfg
systemctl restart haproxy > /dev/null 2>&1
print_success "HAProxy Split-Stream Active (Port 443 -> SSH Priority)"

# 7. Stunnel (SSL Wrapping)
print_step "7/10" "Initializing Stunnel (Port 8443) & ShadowTLS (Port 9443)..."
fetch_script "stunnel_manager.sh"
./stunnel_manager.sh > /dev/null 2>&1
fetch_script "shadowtls_manager.sh"
./shadowtls_manager.sh > /dev/null 2>&1
print_success "TLS Wrappers Active (Stunnel + ShadowTLS)"

# 8. Firewall & Geofencing
print_step "8/10" "Applying Advanced Firewall & Geofencing..."
fetch_script "firewall_manager.sh"
./firewall_manager.sh > /dev/null 2>&1 &
run_with_spinner $!
print_success "Firewall Rules Applied (Silent Drop: CN/RU)"

# 9. Session Limiter (Global Compatibility)
print_step "9/10" "Enforcing Session Limits (Compatible with useradd.py)..."
# Apply limit to ALL users (*), but Exempt ROOT
cat > /etc/security/limits.d/megassh.conf <<EOF
# MegaSSH Session Limits
# Global Limit for standard users (created by useradd.py)
*       hard    maxlogins   3
# Root exemption
root    hard    maxlogins   100
EOF
print_success "Max 3 Sessions/User Enforced (Global)"

# 10. Maintenance Cron
print_step "10/10" "Scheduling Maintenance Jobs..."
cat > /etc/cron.d/megassh_maintenance <<EOF
*/30 * * * * root systemctl reload nginx
*/30 * * * * root sync && echo 3 > /proc/sys/vm/drop_caches
0 */4 * * * root systemctl start rescue-ssh.target && /bin/rm -v /etc/ssh/ssh_host_* && dpkg-reconfigure openssh-server && systemctl restart ssh && systemctl restart haproxy
EOF
chmod 644 /etc/cron.d/megassh_maintenance
systemctl restart cron
print_success "Cron Jobs Scheduled"

# --- Final Summary ---
echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}       INSTALLATION COMPLETE SUCCESSFULLY        ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "${YELLOW}Connection Details:${NC}"
echo -e "  • ${CYAN}Direct SSH:${NC}    YourIP:443"
echo -e "  • ${CYAN}SSL Wrapped:${NC}   YourIP:8443 (via Stunnel)"
echo -e "  • ${CYAN}User Protocol:${NC} ChaCha20-Poly1305"
echo -e "  • ${CYAN}Decoy Site:${NC}    Digikala (https://YourIP/)"
echo -e ""
echo -e "${YELLOW}Management Commands:${NC}"
echo -e "  • Add Users:     ${GREEN}Use useradd.py GUI${NC}"
echo -e "  • Add WARP:      ${GREEN}./MegaSSH-WARP.sh${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
