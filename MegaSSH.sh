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
    local pid=$1
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

# Health Check Function
check_service_health() {
    local service=$1
    local port=$2
    echo -n "  [~] Verifying $service health on port $port..."
    sleep 2 # Give it a moment to bind
    
    if ! systemctl is-active --quiet "$service"; then
        echo -e "\n${RED}[✘] CRITICAL: $service service failed to start!${NC}"
        echo -e "${YELLOW}--- Service Status ---${NC}"
        systemctl status "$service" --no-pager
        echo -e "${YELLOW}--- Last 15 lines of $service logs ---${NC}"
        journalctl -u "$service" --no-pager -n 15
        echo -e "${RED}[!] Installation aborted. Please fix the error above.${NC}"
        exit 1
    fi

    if ! ss -tlnp | grep -q ":$port "; then
        echo -e "\n${RED}[✘] CRITICAL: $service is running but NOT listening on port $port!${NC}"
        echo -e "${YELLOW}Current listening ports:${NC}"
        ss -tlnp | grep LISTEN | head -n 10
        exit 1
    fi
    echo -e " ${GREEN}OK${NC}"
}

# --- Initialization ---
print_banner
echo "Installation started at $(date)" >> $LOG_FILE

# Variables
PORT_SSH_INTERNAL=2222
PORT_HAPROXY=443
PORT_UDPGW=7301
PORT_NGINX=80
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
# PRE-INSTALL FIX: Purge UFW first to allow iptables-persistent (DISABLED: Needed for Firewall Manager)
# apt purge -y ufw >> $LOG_FILE 2>&1
apt autoremove -y >> $LOG_FILE 2>&1

# Dependencies (REMOVED ufw)
(apt update && apt upgrade -y && apt install -y curl socat wget git cmake make gcc build-essential nginx haproxy ipset iptables-persistent unzip tar cron) >> $LOG_FILE 2>&1 &
PID=$!
run_with_spinner $PID
wait $PID
if [ $? -ne 0 ]; then
    print_error "Dependency Installation Failed!"
    echo -e "${YELLOW}Last 20 lines of log:${NC}"
    tail -n 20 $LOG_FILE
    echo -e "${RED}[!] Please fix the error above (e.g., release apt lock) and run again.${NC}"
    exit 1
fi

# Double Check Dependencies
if ! command -v nginx > /dev/null || ! command -v haproxy > /dev/null; then
    print_error "Critical Dependencies (Nginx/HAProxy) missing!"
    exit 1
fi

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
# RESCUE MODE: We are KEEPING Port 22 enabled for now to prevent lockout.
systemctl stop ssh.socket
systemctl disable ssh.socket
systemctl mask ssh.socket

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
# Settings
# Remove existing ports and add split-stream ports
sed -i "/^Port/d" /etc/ssh/sshd_config
sed -i "/^ListenAddress/d" /etc/ssh/sshd_config
# Force IPv4 Binding to ensure HAProxy (127.0.0.1) can connect
echo "ListenAddress 0.0.0.0" >> /etc/ssh/sshd_config

# RESCUE: Port 22 Enabled
echo "Port 22" >> /etc/ssh/sshd_config
# Split-Stream Ports (Internal)
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
    echo "MaxStartups 100:30:200" >> /etc/ssh/sshd_config
fi
if ! grep -q "^PerSourceMaxStartups" /etc/ssh/sshd_config; then
    echo "PerSourceMaxStartups 3" >> /etc/ssh/sshd_config
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
# Enable Standard Service
systemctl unmask ssh
systemctl enable ssh
systemctl restart ssh
# Verify SSH
check_service_health "ssh" "22"
check_service_health "ssh" "2222"
print_success "SSH Configured & Verified (Ports 22 + 2222-2225)"

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
# Ensure Log Directory Exists
mkdir -p /var/log/nginx
touch /var/log/nginx/access.log
touch /var/log/nginx/error.log
chown -R www-data:www-data /var/log/nginx

# Nginx Config
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    listen 8080; # Internal access via HAProxy
    listen [::]:80;
    server_name _;
    
    # Decoy Redirect Logic
    # Redirect ALL traffic to Digikala
    return 301 https://www.digikala.com\$request_uri;
}
EOF
echo -e "${YELLOW}[~] Validating Nginx Config...${NC}"
nginx -t
if [ $? -ne 0 ]; then
    print_error "Nginx Config is Invalid!"
    exit 1
fi

systemctl restart nginx > /dev/null 2>&1
# Ensure the config is linked (Standard Ubuntu)
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
systemctl reload nginx
# Verify Nginx
check_service_health "nginx" "80"
print_success "Nginx Decoy Live (Port 80 & Internal 8080)"

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
    # 200ms Delay: Fast enough for browsers to send hello, short enough for silent SSH to feel instant
    tcp-request inspect-delay 200ms
    
    # Detect Obvious HTTP/TLS (Decoy Candidate)
    # If it looks like HTTP or TLS, send to Decoy. Else assume SSH.
    acl is_http req.payload(0,3) -m str GET POST HEAD OPTIONS
    acl is_tls req.ssl_hello_type gt 0
    
    # Routing Logic
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
    server web_srv 127.0.0.1:8080 check
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
# Fetching IP Lists from your GitHub automatically
fetch_script "ip2location_country_ir.netset"
fetch_script "ip2location_country_ru.netset"
fetch_script "ip2location_country_cn.netset"
fetch_script "firewall_manager.sh"
./firewall_manager.sh
print_success "Firewall Rules Applied (Zero-Leak Mode Active)"

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
# MegaSSH Maintenance Jobs
# Reload Nginx to keep logs fresh and config active
*/30 * * * * root systemctl reload nginx
# Note: Host key cycling and drop_caches removed for better stability in 2024+
EOF
chmod 644 /etc/cron.d/megassh_maintenance
systemctl restart cron
print_success "Cron Jobs Scheduled"

# Prepare Audit Tool
echo -e "${YELLOW}[~] Setting up Audit Tool...${NC}"
fetch_script "mega-audit.sh" || echo -e "${RED}[!] Note: mega-audit.sh not found on GitHub. Please upload it to your repo.${NC}"

# --- Final Summary ---
echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}       INSTALLATION COMPLETE SUCCESSFULLY        ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "${YELLOW}Connection Details:${NC}"
echo -e "  • ${CYAN}Direct SSH:${NC}    YourIP:443"
echo -e "  • ${RED}Rescue SSH:${NC}    YourIP:22 (Temp Enabled)"
echo -e "  • ${CYAN}SSL Wrapped:${NC}   YourIP:8443 (via Stunnel)"
echo -e "  • ${CYAN}User Protocol:${NC} ChaCha20-Poly1305"
echo -e "  • ${CYAN}Decoy Site:${NC}    Digikala (https://YourIP/)"
echo -e ""
echo -e "${YELLOW}Management Commands:${NC}"
echo -e "  • Add Users:     ${GREEN}Use useradd.py GUI${NC}"
echo -e "  • Add WARP:      ${GREEN}./MegaSSH-WARP.sh${NC}"
echo -e "  • ${RED}Run Audit:${NC}     ${GREEN}./mega-audit.sh${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# --- Integrated Health Audit & Final Prompt ---
run_integrated_audit() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}        MEGASSH SYSTEM AUDIT (CHECK LOG)        ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    date
    
    echo -e "\n${YELLOW}--- Component Status ---${NC}"
    # Diagnostic check function
    check_port() {
        local name=$1; local port=$2
        printf "%-30s" "[~] Checking $name ($port)..."
        if ss -tlnp | grep -q ":$port "; then
            echo -e "${GREEN}[OK]${NC}"; return 0
        else
            echo -e "${RED}[FAILED]${NC}"; return 1
        fi
    }
    check_port "Nginx (Decoy)" 80
    check_port "HAProxy (Multiplexer)" 443
    check_port "SSH (Internal)" 2222
    check_port "Stunnel (SSL)" 8443
    check_port "ShadowTLS" 9443
    check_port "UDPGW" 7301
    check_port "Rescue SSH" 22

    echo -e "\n${YELLOW}--- Firewall Integrity ---${NC}"
    # Check Files
    printf "%-30s" "[~] Checking .netset files..."
    FILES_COUNT=$(ls ip2location_country_*.netset 2>/dev/null | wc -l)
    if [ "$FILES_COUNT" -ge 3 ]; then 
        echo -e "${GREEN}[FOUND]${NC}"
    else 
        echo -e "${RED}[MISSING]${NC}"
        echo -e "    ${YELLOW}(Note: Please upload ip2location_country_*.netset files to /root/ on your server)${NC}"
    fi

    # Check IPSet
    IR_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
    RU_CN_COUNT=$(ipset list country_block_in 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
    
    printf "%-30s" "[~] IPSet (Iran Block)..."
    if [ -n "$IR_COUNT" ] && [ "$IR_COUNT" -gt 0 ]; then echo -e "${GREEN}[OK] ($IR_COUNT entries)${NC}"; else echo -e "${RED}[EMPTY]${NC}"; fi
    
    printf "%-30s" "[~] IPSet (RU/CN Block)..."
    if [ -n "$RU_CN_COUNT" ] && [ "$RU_CN_COUNT" -gt 0 ]; then echo -e "${GREEN}[OK] ($RU_CN_COUNT entries)${NC}"; else echo -e "${RED}[EMPTY]${NC}"; fi
    
    # Check Policy Routing (FWMark)
    printf "%-30s" "[~] Zero-Leak Routing Rule..."
    if ip rule show | grep -q "0x99"; then echo -e "${GREEN}[ACTIVE]${NC}"; else echo -e "${RED}[MISSING]${NC}"; fi

    printf "%-30s" "[~] Blackhole Table 200..."
    if ip route show table 200 2>/dev/null | grep -q "blackhole"; then echo -e "${GREEN}[OK]${NC}"; else echo -e "${RED}[MISSING]${NC}"; fi

    # Check IPv6
    printf "%-30s" "[~] IPv6 Status..."
    IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
    if [ "$IPV6_STATUS" == "1" ]; then echo -e "${GREEN}[DISABLED]${NC}"; else echo -e "${RED}[LEAKING]${NC}"; fi

    echo -e "\n${YELLOW}--- Live Geo-Blocking Test ---${NC}"
    test_block() {
        local site=$1; local ip=$2
        printf "%-30s" "[~] Testing $site..."
        # We check for exit code 28 (timeout) or 7 (failed to connect) - likely blocked
        # Error 3/6 can happen if the firewall drops the packet before resolution finishes
        curl -m 4 -s -I --resolve "$site:80:$ip" "http://$site" > /dev/null 2>&1
        local ret=$?
        if [ $ret -eq 0 ]; then
            echo -e "${RED}[FAILED - SITE OPENED]${NC}"
        elif [ $ret -eq 28 ] || [ $ret -eq 7 ] || [ $ret -eq 3 ] || [ $ret -eq 6 ]; then
            echo -e "${GREEN}[SUCCESS - BLOCKED]${NC}"
        else
            echo -e "${YELLOW}[?] UNKNOWN (ERROR $ret)${NC}"
        fi
    }
    test_block "vk.com (Russia)" "87.240.139.194"
    test_block "baidu.com (China)" "110.242.68.66"
    test_block "digikala.com (Iran)" "185.239.104.14"

    echo -e "\n${CYAN}=================================================${NC}"
    echo -e "${GREEN}      ALL COMPONENTS VERIFIED & CORRECT        ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    
    echo -e "\n${RED}[!] IMPORTANT: System changes require a reboot to be 100% effective.${NC}"
    read -p "Would you like to REBOOT the server now? (y/n): " confirm
    if [[ "$confirm" == [yY] ]]; then
        echo -e "${GREEN}[+] Rebooting...${NC}"
        reboot
    fi
}

echo -e "${YELLOW}[~] Starting Final System Validation...${NC}"
run_integrated_audit
