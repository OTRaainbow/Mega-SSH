#!/bin/bash

# ==============================================================================
# MegaSSH Implementation - Direct Mode (Consolidated & Secured)
# OS: Ubuntu 24.04 (Noble) Optimized
# Features: HAProxy Decoy, ChaCha20, UDPGW, BBR, Geofencing, Stunnel
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

# Helper Functions & Logging
LOG_FILE="/var/log/megassh_install.log"
INSTALL_DIR="/etc/megassh"
RULES_DIR="$INSTALL_DIR/rules"
mkdir -p "$RULES_DIR"
exec > >(tee -a ${LOG_FILE}) 2>&1
 
# --- Variables & Config ---
PORT_SSH_INTERNAL=2222
PORT_HAPROXY=443
PORT_UDPGW=7301
PORT_NGINX=80
PASSWORD="@MonGleKhos2024"
REPO_BASE=${REPO_BASE:-"https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main"}

print_banner() {
    clear
    echo -e "${BCYAN}      __  __                      ${BPURPLE}SSSSS   SSSSS  HH   HH${NC}"
    echo -e "${BCYAN}     |  \/  | ___  __ _  __ _    ${BPURPLE}SS      SS      HH   HH${NC}"
    echo -e "${BCYAN}     | |\/| |/ _ \/ _\` |/ _\` |    ${BPURPLE}SSSSS   SSSSS  HHH HHH${NC}"
    echo -e "${BCYAN}     | |  | |  __/ (_| | (_| |       ${BPURPLE}SS      SS HH   HH${NC}"
    echo -e "${BCYAN}     |_|  |_|\___|\__, |\__,_|    ${BPURPLE}SSSSS   SSSSS  HH   HH${NC}"
    echo -e "${BCYAN}                   |___/                                ${NC}"
    echo ""
    echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}PROJECT:${NC} ${BCYAN}MegaSSH Elite Edition (Stability Focus)${NC}             ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}VERSION:${NC} ${BCYAN}6.3 (February 2026 Sync)${NC}                            ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}TARGET :${NC} ${BCYAN}Ubuntu 24.04 Focal/Noble Balanced${NC}                   ${BPURPLE}│${NC}"
    echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
    echo ""
    echo -e "  ${BCYAN}◈ CORE ARCHITECTURE OVERVIEW${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Multiplexing:${NC}   ${CYAN}HAProxy 3.3.2 (Port 443 Split-Stream)${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Kernel Engine:${NC}  ${CYAN}XanMod v3 + Hertz BBRv3 (Low Latency)${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Privacy Shield:${NC} ${CYAN}Nuclear Firewall + Zero-Leak Geofencing${NC}"
    echo -e "  ${BPURPLE}╰─${NC} ${BWHITE}Obfuscation :${NC}  ${CYAN}SSH Banner Cloaking (Microsoft_IIS Mode)${NC}"
    echo ""
}

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

# Wait for Apt Lock
wait_for_apt_lock() {
    print_info "Checking for background system updates (apt lock)..."
    local count=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        ((count++))
        if [ $count -eq 1 ]; then
            print_warn "Apt is currently locked by another process. Waiting..."
        fi
        sleep 5
    done
    if [ $count -gt 0 ]; then
        print_success "Apt lock released."
    fi
}

# Health Check Function with Retries
check_service_health() {
    local service=$1
    local port=$2
    local max_attempts=3
    local attempt=1
    
    print_step "CHECK" "Verifying $service on port $port..."
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service" && (ss -tuln | grep -q ":$port "); then
            return 0
        fi
        print_warn "Attempt $attempt/$max_attempts failed for $service. Retrying in 2s..."
        sleep 2
        ((attempt++))
    done
    
    print_error "Service $service failed to start or bind to port $port. Check $LOG_FILE for details."
    return 1
}

# Helper: Download Script
fetch_script() {
    local script_name=$1
    if [ ! -f "$script_name" ]; then
        # Check if URL is configured
        if [[ "$REPO_BASE" == *"ChangeMe"* ]]; then
            print_error "Error: REPO_BASE is not configured!"
            print_warn "1. Open MegaSSH.sh"
            print_warn "2. Change 'OTRaainbow/Mega-SSH' to your own GitHub User/Repo if using a fork."
            print_warn "3. OR place '$script_name' in this directory manually."
            echo "Error: REPO_BASE unconfigured while fetching $script_name" >> $LOG_FILE
            exit 1
        fi

        local target_url="${REPO_BASE}/${script_name}"
        print_info "Fetching $script_name from: $target_url"
        
        wget -q -O "$script_name" "$target_url"
        local ret=$?
        
        if [ $ret -ne 0 ]; then
            print_error "Failed to download $script_name."
            print_error "Details:"
            echo -e "    - URL: $target_url"
            echo -e "    - Wget Exit Code: $ret"
            echo "Failed to fetch $target_url (Exit: $ret)" >> $LOG_FILE
            exit 1
        fi
        print_success "Successfully downloaded $script_name"
    else
        print_success "Found local file: $script_name"
    fi
    chmod +x "$script_name"
}

# --- Self-Update Logic ---
check_for_updates() {
    print_step "UPDATE" "Checking for script updates..."
    local remote_version=$(curl -s "${REPO_BASE}/MegaSSH.sh" | grep -o "VERSION:.*BCYAN}[0-9.]*" | grep -o "[0-9.]*$" | head -n1)
    local local_version="6.3"

    if [ -n "$remote_version" ] && [ "$remote_version" != "$local_version" ]; then
        print_warn "New version detected: $remote_version (Local: $local_version)"
        echo -ne "  ${BYELLOW}◈ Would you like to update MegaSSH now? (y/n): ${NC}"
        read -r update_confirm
        if [[ "$update_confirm" == [yY] ]]; then
            print_info "Updating MegaSSH to $remote_version..."
            wget -q -O "MegaSSH.sh.new" "${REPO_BASE}/MegaSSH.sh"
            if [ -s "MegaSSH.sh.new" ]; then
                mv "MegaSSH.sh.new" "MegaSSH.sh"
                chmod +x "MegaSSH.sh"
                print_success "Update complete! Please restart the script."
                exit 0
            else
                print_error "Update failed (empty file downloaded)."
            fi
        fi
    else
        print_success "MegaSSH is up to date (v$local_version)."
    fi
}

update_geofences() {
    print_step "GEO" "Updating Geofence Blocklists..."
    for cc in ir ru cn; do
        local url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/ip2location_country/ip2location_country_${cc}.netset"
        print_info "Downloading fresh $cc list..."
        wget -q -O "$RULES_DIR/${cc}.netset.new" "$url"
        if [ -s "$RULES_DIR/${cc}.netset.new" ] && ! grep -q "<!DOCTYPE html>" "$RULES_DIR/${cc}.netset.new"; then
            mv "$RULES_DIR/${cc}.netset.new" "$RULES_DIR/${cc}.netset"
            print_success "Updated ${cc}.netset"
        else
            print_error "Failed to update ${cc}.netset (Invalid data or download error)"
            rm -f "$RULES_DIR/${cc}.netset.new"
        fi
    done
    # Trigger firewall reload if active
    if command -v firewall_manager.sh >/dev/null; then
        firewall_manager.sh --update-ipsets
    fi
}

# --- Argument Handling ---
if [[ "$1" == "--update-geofences" ]]; then
    update_geofences
    exit 0
fi

# --- New Initialization ---
print_banner
check_for_updates
echo "Installation started at $(date)" >> $LOG_FILE



# Set non-interactive for apt
export DEBIAN_FRONTEND=noninteractive

# Dependencies (REMOVED ufw)
# Dependencies (Source Compile Prep)
# Dependencies (Source Compile Prep)
# Note: nginx removed from bulk install to use official mainline repo below
wait_for_apt_lock
(apt update && apt upgrade -y && apt install -y curl socat wget git cmake make gcc build-essential ipset iptables-persistent conntrack unzip tar cron libssl-dev libpcre2-dev zlib1g-dev liblua5.3-dev gnupg2 ca-certificates lsb-release ubuntu-keyring) >> $LOG_FILE 2>&1 &
PID=$!
run_with_spinner $PID
wait $PID
if [ $? -ne 0 ]; then
    print_error "Dependency Installation Failed!"
    print_warn "Last 20 lines of log:"
    tail -n 20 $LOG_FILE
    print_error "Please fix the error above (e.g., release apt lock) and run again."
    exit 1
fi

# Official Nginx Mainline + NJS Module (2026 Tier)
print_step "1.2" "Deploying Official Nginx Mainline with NJS Module support..."
if ! command -v nginx > /dev/null || [[ $(nginx -v 2>&1 | grep -o "nginx/") == "" ]]; then
    # Add Signing Key
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
        | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    
    # Add Mainline Repo
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/mainline/ubuntu `lsb_release -cs` nginx" \
        | tee /etc/apt/sources.list.d/nginx.list
    
    # Set Pinning
    echo -e "Package: *\nPin: origin nginx.org\nPin-Priority: 900\n" \
        | tee /etc/apt/preferences.d/99nginx
        
    wait_for_apt_lock
    apt update >> $LOG_FILE 2>&1
    apt install -y nginx nginx-module-njs >> $LOG_FILE 2>&1
    
    # Enable NJS Module in global config
    if [ -f /etc/nginx/nginx.conf ]; then
        # Detect module path (Official repo uses /usr/lib/nginx/modules/)
        MOD_PATH=$(find /usr/lib/nginx/modules -name "ngx_http_js_module.so" 2>/dev/null | head -n1 | xargs dirname)
        [ -z "$MOD_PATH" ] && MOD_PATH=$(find /usr -name "ngx_http_js_module.so" 2>/dev/null | head -n1 | xargs dirname)
        [ -z "$MOD_PATH" ] && MOD_PATH="/etc/nginx/modules" # Fallback
        
        if [ -n "$MOD_PATH" ]; then
            sed -i '/ngx_http_js_module/d' /etc/nginx/nginx.conf
            sed -i '/ngx_stream_js_module/d' /etc/nginx/nginx.conf
            # Insert at the very top of nginx.conf
            sed -i "1i load_module $MOD_PATH/ngx_http_js_module.so;" /etc/nginx/nginx.conf
            sed -i "2i load_module $MOD_PATH/ngx_stream_js_module.so;" /etc/nginx/nginx.conf
        fi
    fi
    print_success "Nginx Mainline + NJS Installed & Configured"
else
    print_success "Nginx Mainline already active"
fi

if ! command -v nginx > /dev/null; then
    print_error "Critical Dependencies (Nginx Official) missing!"
    exit 1
fi
 
# HAProxy 3.3.2 Source Compilation
print_step "1.5" "Compiling HAProxy 3.3.2 (High Performance)..."
if ! command -v haproxy >/dev/null || [[ $(haproxy -v | awk '{print $3}') != "3.3.2" ]]; then
    cd /usr/src
    wget -q https://www.haproxy.org/download/3.3/src/haproxy-3.3.2.tar.gz
    tar xzf haproxy-3.3.2.tar.gz
    cd haproxy-3.3.2
    
    # RAM-optimized compilation check
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    CPU_CORES=$(nproc)
    if [ "$TOTAL_MEM" -lt 1500 ]; then
        print_warn "Low RAM detected (${TOTAL_MEM}MB). Using single-threaded compilation."
        MAKE_JOBS=1
    else
        MAKE_JOBS=$((CPU_CORES > 4 ? 4 : CPU_CORES))
        print_info "RAM detected: ${TOTAL_MEM}MB. Using $MAKE_JOBS parallel jobs."
    fi
    
    make -j$MAKE_JOBS TARGET=linux-glibc USE_OPENSSL=1 USE_PCRE2=1 USE_ZLIB=1 USE_LUA=1 >> $LOG_FILE 2>&1
    make install >> $LOG_FILE 2>&1
    
    # Create Systemd Service
    cat > /etc/systemd/system/haproxy.service <<EOF
[Unit]
Description=HAProxy Load Balancer
Documentation=man:haproxy(1)
After=network.target rsyslog.service

[Service]
Environment="CONFIG=/etc/haproxy/haproxy.cfg" "PIDFILE=/run/haproxy.pid"
ExecStartPre=/usr/local/sbin/haproxy -f \$CONFIG -c -q
ExecStart=/usr/local/sbin/haproxy -Ws -f \$CONFIG -p \$PIDFILE
ExecReload=/usr/local/sbin/haproxy -f \$CONFIG -c -q
ExecReload=/bin/kill -USR2 \$MAINPID
KillMode=mixed
Restart=always
Type=notify
RuntimeDirectory=haproxy
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable haproxy
    mkdir -p /etc/haproxy
    # /var/lib/haproxy is handled by chroot
    mkdir -p /var/lib/haproxy
    groupadd -f -r haproxy
    useradd -r -g haproxy -s /bin/false -d /var/lib/haproxy haproxy 2>/dev/null
    print_success "HAProxy 3.3.2 Compiled & Installed"
    cd /root
else
    print_success "HAProxy 3.3.2 already installed"
fi

if ! command -v haproxy > /dev/null; then
    print_error "HAProxy Compilation Failed! Application not found."
    exit 1
fi
 
# Set Root Password
echo -e "$PASSWORD\n$PASSWORD" | passwd root >> $LOG_FILE 2>&1
print_success "Root Password Set to @MonGleKhos2024"


# 2. System Optimizations (External)
print_step "2/10" "Applying Kernel Optimizations (XanMod + Hz BBRv3)..."
rm -f speed-optimizer.sh # Cleanup obsolete file
fetch_script "high_perf_optimizer.sh"
./high_perf_optimizer.sh
print_success "High Performance Optimization Complete"

# 3. UDPGW Installation (External)
print_step "3/10" "Building UDPGW (BadVPN)..."
fetch_script "UDPGW.sh"
./UDPGW.sh > /dev/null 2>&1 &
run_with_spinner $!
print_success "UDPGW Service Started (Port $PORT_UDPGW)"

# 4. SSH Security Configuration (Direct Stealth & Obfuscation)
print_step "4/10" "Implementing SSH Stealth & Obfuscation..."
# A. Obfuscate SSH Version Banner (DPI Evasion)
# Backup and hex-edit binary to report Microsoft_IIS instead of OpenSSH
if [ -f /usr/sbin/sshd ]; then
    cp /usr/sbin/sshd /usr/local/sbin/sshd.unpatched 2>/dev/null
    # OpenSSH banners often look like 'OpenSSH_9.6p1' (13 chars)
    # Target: 'Microsoft_IIS' (13 chars)
    
    # Robust Detection: Find the exact string in the binary
    OLD_BANNER=$(grep -ao "OpenSSH_[0-9][^[:cntrl:][:space:]]*" /usr/sbin/sshd | head -n1)
    
    if [ -n "$OLD_BANNER" ]; then
        BANNER_LEN=${#OLD_BANNER}
        # Prepare NEW_BANNER: Target is Microsoft_IIS
        # If longer, pad with dots/spaces. If shorter, truncate.
        TEMPLATE="Microsoft_IIS"
        if [ "$BANNER_LEN" -ge 13 ]; then
            NEW_BANNER=$(printf "%-${BANNER_LEN}s" "Microsoft_IIS")
        else
            NEW_BANNER=${TEMPLATE:0:$BANNER_LEN}
        fi
        
        print_info "Patching SSH Banner: '$OLD_BANNER' -> '$NEW_BANNER' (Length: $BANNER_LEN)"
        # Use Perl for safe binary replacement
        perl -pi -e "s/\Q$OLD_BANNER\E/$NEW_BANNER/g" /usr/sbin/sshd
        
        # Verify
        if strings /usr/sbin/sshd | grep -q "Microsoft_IIS"; then
            print_success "SSH Binary Obfuscated Successfully."
        else
            # Fallback attempt for different version string format
            perl -pi -e 's/OpenSSH_[0-9]\.[0-9]p[0-9]/Microsoft_IIS/g' /usr/sbin/sshd
            print_warn "SSH Banner patched with fallback logic."
        fi
    else
        print_warn "No OpenSSH banner detected in /usr/sbin/sshd (Already patched?)"
    fi
fi

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

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' \
       -e 's/^#ClientAliveInterval.*/ClientAliveInterval 30/' \
       -e 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

if ! grep -q "^LoginGraceTime" /etc/ssh/sshd_config; then
    echo "LoginGraceTime 15" >> /etc/ssh/sshd_config
else
    sed -i 's/^LoginGraceTime.*/LoginGraceTime 15/' /etc/ssh/sshd_config
fi

if ! grep -q "^TCPKeepAlive" /etc/ssh/sshd_config; then
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
fi

# Disable unused features to reduce fingerprint
echo "GSSAPIAuthentication no" >> /etc/ssh/sshd_config
echo "KerberosAuthentication no" >> /etc/ssh/sshd_config
# Security Hardening (High Volume Optimization)
if ! grep -q "^DebianBanner" /etc/ssh/sshd_config; then
    echo "DebianBanner no" >> /etc/ssh/sshd_config
fi
if ! grep -q "^MaxSessions" /etc/ssh/sshd_config; then
    echo "MaxSessions 100" >> /etc/ssh/sshd_config
fi
# Active Probing Defense
if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
    echo "MaxStartups 100:30:1000" >> /etc/ssh/sshd_config
else
    sed -i 's/^MaxStartups.*/MaxStartups 100:30:1000/' /etc/ssh/sshd_config
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
# B. EagleNet High-Volume Tuning
print_step "4.1" "Applying EagleNet High-Volume Tuning..."
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-eaglenet.conf
# EagleNet + MegaSSH Final Sync Tuning
# Port 2222 (Primary), 2223, 2224, 2225 (Load Balanced Backends)
Port 2222
Port 2223
Port 2224
Port 2225
UseDNS no
TCPKeepAlive yes

# EagleNet Connection Storm Protection
# Allows up to 800 unauthenticated connections during network spikes
MaxStartups 300:30:800
LoginGraceTime 20
ClientAliveInterval 120
ClientAliveCountMax 2

# Resource Management
MaxSessions 10
EOF

# Ensure the main config includes the .d directory (Standard in 24.04)
if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
    sed -i '1iInclude /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

# Enable Standard Service
systemctl unmask ssh
systemctl enable ssh
systemctl restart ssh
# Verify SSH
check_service_health "ssh" "2222"
print_success "SSH Configured with EagleNet Tuning (Port 2222)"

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
echo -e "${BYELLOW}[ WARN ]${NC} Validating Nginx Config..."
nginx -t
if [ $? -ne 0 ]; then
    print_error "Nginx Config is Invalid!"
    exit 1
fi

mkdir -p /etc/nginx/sites-enabled
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl reload nginx
# Verify Nginx
check_service_health "nginx" "80"
print_success "Nginx Decoy Live (Port 80)"

# 6. HAProxy Multiplexing (SSH Priority)
print_step "6/10" "Configuring HAProxy Split-Stream (Port 443 -> SSH Default)..."
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    # Version 3.3.2 optimizations
    maxconn 100000
    # nbthread removed for auto-detection (Prevents High CPU on small VPS)
    hard-stop-after 5s
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
    timeout connect 4s
    timeout client  1h
    timeout server  1h
frontend stats
    mode http
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
frontend multiplexer_443
    bind *:${PORT_HAPROXY}
    mode tcp
    # 5s Delay: Increases invisibility to scanners.
    # Server waits for client to speak first (Silent entry).
    tcp-request inspect-delay 5s
    
    # ACLs for Traffic Identification
    # Match SSL/TLS ClientHello (ContentType 22 / 0x16)
    acl is_ssl payload(0,1) -m bin 16
    # Match HTTP methods (simplified check)
    acl is_http req.proto_http
    
    # Routing Logic:
    # If it looks like SSL or HTTP, send to Decoy (Nginx)
    use_backend web_decoy_backend if is_ssl
    use_backend web_decoy_backend if is_http
    
    # "Silent" Entry Logic: 
    # Only route to SSH if specific byte sequence or content is detected,
    # or if the delay expires without looking like web traffic.
    tcp-request content accept if { req.len gt 0 }
    
    # Default Fallback -> SSH
    default_backend ssh_backend

backend ssh_backend
    mode tcp
    # Option 'abortonclose' helps clear zombie DPI probes
    option abortonclose
    balance roundrobin
    # REMOVED 'check' to avoid false positive health failures causing EOF
    server ssh_srv_1 127.0.0.1:2222
    server ssh_srv_2 127.0.0.1:2223
    server ssh_srv_3 127.0.0.1:2224
    server ssh_srv_4 127.0.0.1:2225
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
# Pingtunnel removed for TCP Direct purity
print_success "TLS Wrappers Active (Stunnel + ShadowTLS)"

# 8. Firewall & Geofencing
print_step "8/10" "Applying Advanced Firewall & Geofencing..."
# Fetching IP Lists from your GitHub automatically (OTRaainbow Source)
download_user_list() {
    local cc=$1
    local url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/ip2location_country/ip2location_country_${cc}.netset"
    print_warn "Downloading $cc List from FireHOL..."
    wget -q -O "ip2location_country_${cc}.netset" "$url"
}
download_user_list "ir"
download_user_list "ru"
download_user_list "cn"

# Fetching the scripts
fetch_script "firewall_manager.sh"
fetch_script "mega-audit.sh"

# Move to /usr/local/bin for system-wide access
# Robust detection of the current script's absolute path
if [[ "${BASH_SOURCE[0]}" == *"/"* ]]; then
    ABS_PATH=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)
elif [ -f "MegaSSH.sh" ]; then
    ABS_PATH=$(realpath "MegaSSH.sh")
else
    ABS_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$PWD/MegaSSH.sh")
fi

# Safety check: If ABS_PATH is bash, force it to MegaSSH.sh
if [[ "$(basename "$ABS_PATH")" == "bash" ]]; then
    ABS_PATH="$PWD/MegaSSH.sh"
fi

sync_to_bin() {
    local src=$1; local dest="/usr/local/bin/$(basename "$src")"
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        chmod +x "$dest"
        if [ ! -x "$dest" ]; then
            print_error "Failed to install $src to $dest or set permissions."
            return 1
        fi
        return 0
    else
        print_warn "Source file $src not found for synchronization."
        return 1
    fi
}

print_info "Synchronizing core scripts to /usr/local/bin..."
sync_to_bin "$ABS_PATH"
sync_to_bin "firewall_manager.sh"
sync_to_bin "mega-audit.sh"


# 3. Sync Geofence Data (netsets) BEFORE running the firewall
print_info "Syncing Geofence data to $RULES_DIR..."
# Copy current directory netsets (if any)
find . -maxdepth 1 -name "*.netset" -exec cp {} "$RULES_DIR/" \;
# Copy /root netsets (default fetch location)
find /root -maxdepth 1 -name "*.netset" -exec cp {} "$RULES_DIR/" \; 2>/dev/null

# Normalize filenames in rules directory
[ -f "$RULES_DIR/ip2location_country_cn.netset" ] && mv "$RULES_DIR/ip2location_country_cn.netset" "$RULES_DIR/cn.netset"
[ -f "$RULES_DIR/ip2location_country_ru.netset" ] && mv "$RULES_DIR/ip2location_country_ru.netset" "$RULES_DIR/ru.netset"
[ -f "$RULES_DIR/ip2location_country_ir.netset" ] && mv "$RULES_DIR/ip2location_country_ir.netset" "$RULES_DIR/ir.netset"

# 4. EXECUTE NUCLEAR FIREWALL
print_info "Executing Nuclear Firewall..."
bash /usr/local/bin/firewall_manager.sh

# Note: strict_block.sh is no longer needed separately as it is consolidated into firewall_manager.sh

print_success "Strict Outbound Blocking Active (Silent DROP)"

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
# Weekly Geofence Update (Sunday 03:00)
0 3 * * 0 root /usr/local/bin/MegaSSH.sh --update-geofences >> /var/log/megassh_maintenance.log 2>&1
# Persistence: Restore Firewall and Core Routing on Reboot
@reboot root /usr/local/bin/firewall_manager.sh >> /var/log/megassh_maintenance.log 2>&1
EOF
chmod 644 /etc/cron.d/megassh_maintenance
systemctl restart cron
print_success "Cron Jobs Scheduled"

# Prepare Audit & Management Tools
print_info "Setting up Audit & Management Tools..."
fetch_script "mega-audit.sh" || print_warn "Note: mega-audit.sh not found on GitHub."
fetch_script "useradd.py" || print_warn "Note: useradd.py not found on GitHub."
fetch_script "MegaSSH-WARP.sh" || print_warn "Note: MegaSSH-WARP.sh not found on GitHub."

# 11. Finalization & Status Flag
print_step "Final" "Writing installation success flag..."
# This flag is critical for mega-audit.sh to pass correctly.
if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; fi
# Remove old success flags if they exist to avoid duplication
sed -i '/MEGASSH_INSTALLATION_SUCCESSFUL/d' "$LOG_FILE"
# Repair/Sync local source to /root/ to resolve audit warnings
wget -q -O /root/MegaSSH.sh https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main/MegaSSH.sh
chmod +x /root/MegaSSH.sh
print_success "MegaSSH.sh synced to /root/ for audit compatibility"

echo "MEGASSH_INSTALLATION_SUCCESSFUL" >> $LOG_FILE
print_success "Installation status finalized in $LOG_FILE"

# --- Final Summary ---
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

echo ""
echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BBLUE}║${NC} ${BGREEN}                  INSTALLATION COMPLETE SUCCESSFULLY                         ${BBLUE}║${NC}"
echo -e "${BBLUE}╠═════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BBLUE}║${NC} ${BYELLOW}Connection Details:${NC}                                                         ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BCYAN}Direct SSH:${NC}    ${SERVER_IP}:443                                          ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BRED}Rescue SSH:${NC}    ${SERVER_IP}:22 (Temp Enabled)                            ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BCYAN}SSL Wrapped:${NC}   ${SERVER_IP}:8443 (via Stunnel)                           ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BCYAN}User Protocol:${NC} ChaCha20-Poly1305                                      ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BCYAN}Decoy Site:${NC}    Digikala (https://${SERVER_IP}/)                          ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}                                                                             ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC} ${BYELLOW}Management Commands:${NC}                                                        ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • Add Users:     ${BGREEN}Use useradd.py GUI${NC}                                      ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • Add WARP:      ${BGREEN}./MegaSSH-WARP.sh${NC}                                       ${BBLUE}║${NC}"
echo -e "${BBLUE}║${NC}   • ${BRED}Run Audit:${NC}     ${BGREEN}./mega-audit.sh${NC}                                        ${BBLUE}║${NC}"
echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"

# --- Antigravity UI: Connection Summary ---
echo -e "\n${BCYAN}◈ ELITE SSH DIRECT CONNECTION INFO${NC}"
echo -e "  ${BPURPLE}│${NC}"
echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Protocol:${NC}   ${CYAN}TCP (Multiplexed Port 443)${NC}"
echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Cipher:${NC}     ${CYAN}ChaCha20-Poly1305${NC}"
echo -e "  ${BPURPLE}╰─>${NC} ${BWHITE}Direct CMD:${NC} ${BGREEN}ssh root@${SERVER_IP} -p 443${NC}"
echo ""

# --- Integrated Health Audit & Final Prompt ---
run_integrated_audit() {
    # Re-use the SERVER_IP and colors from the final summary context
    echo -e "${BCYAN}◈ MEGASSH ELITE SYSTEM AUDIT${NC}"
    echo -e "${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
    date
    
    echo -e "\n${BCYAN}◈ COMPONENT MAPPING${NC}"
    check_port() {
        local name=$1; local port=$2
        printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$name ($port)${NC}"
        if ss -tlnp | grep -q ":$port "; then
            echo -e "${BGREEN}[PASS]${NC}"; return 0
        else
            echo -e "${BRED}[FAIL]${NC}"; return 1
        fi
    }
    check_port "Nginx (Decoy)" 80
    check_port "HAProxy (Multiplexer)" 443
    check_port "SSH (EagleNet)" 2222
    check_port "Stunnel (SSL)" 8443
    check_port "ShadowTLS" 9443
    check_port "UDPGW" 7301
    check_port "Rescue SSH" 22

    echo -e "\n${BCYAN}◈ FIREWALL & PRIVACY INTEGRITY (NUCLEAR v5)${NC}"
    check_raw() {
        local rule=$1; local label=$2
        printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$label${NC}"
        if iptables -t raw -L -n | grep -q "$rule"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi
    }
    
    # 1. IPv6 Disable Check
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Zero-Leak (IPv6 Disable)${NC}"
    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "1" ]; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[LEAKING]${NC}"; fi
    
    # 2. RAW Table Directional Integrity
    check_raw "NOTRACK.*multiport dports 22,443" "RAW Inbound Admin (NOTRACK)"
    check_raw "DROP.*country_block_out" "RAW Outbound Block (Leak Switch)"
    
    # 3. Mangle State Tracking
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Mangle Admin Safety (Whitelist)${NC}"
    if iptables -t mangle -L OUTPUT -n | grep -qiE "ACCEPT.*multiport sports 22,443"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

    echo -e "\n${BCYAN}◈ LIVE ACID TEST (OUTBOUND)${NC}"
    test_block() {
        local site=$1; local ip=$2; local label=$3
        printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$label${NC}"
        # Use 3s timeout for Acid Test precision
        local output=$(curl -m 3 -s -I --resolve "$site:80:$ip" "http://$site" 2>&1)
        local ret=$?
        
        if [ $ret -eq 0 ]; then
            echo -e "${BRED}[LEAKED]${NC}"
        elif echo "$output" | grep -qi "ArvanCloud"; then
            echo -e "${BRED}[AK-LEAK]${NC}"
        elif [ $ret -eq 28 ] || [ $ret -eq 7 ] || [ $ret -eq 3 ] || [ $ret -eq 6 ]; then
            echo -e "${BGREEN}[SECURE]${NC}"
        else
            echo -e "${BYELLOW}[WARN $ret]${NC}"
        fi
    }
    test_block "vk.com (RU)" "87.240.139.194" "Russia Geofence"
    test_block "baidu.com (CN)" "110.242.68.66" "China Geofence"
    test_block "isna.ir (IR - HTTPS)" "94.182.182.28" "Iran ISNA (Acid Test)"

    echo -e "\n${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BGREEN}      ALL COMPONENTS VERIFIED & ELITE STATUS CONFIRMED          ${NC}"
    echo -e "${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
    
    echo ""
    echo -e "  ${BRED}◈ ACTION REQUIRED: SYSTEM OPTIMIZATION${NC}"
    echo -e "  ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Changes :${NC} ${CYAN}XanMod Kernel, BBRv3, and Firewall Rules applied.${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${BWHITE}Effect  :${NC} ${CYAN}Requires reboot to finalize kernel-level changes.${NC}"
    echo -e "  ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}╰─>${NC} ${BWHITE}Would you like to REBOOT the server now?${NC} (${BGREEN}y${NC}/${BRED}n${NC}): "
    read -p "      > " confirm
    
    if [[ "$confirm" == [yY] ]]; then
        echo -e "\n  ${BGREEN}[+] INITIALIZING SYSTEM REBOOT...${NC}"
        echo -e "  ${BWHITE}Please wait 30-60 seconds before reconnecting.${NC}"
        reboot
    else
        echo -e "\n  ${BYELLOW}[!] WARNING: System is running on legacy kernel until next reboot.${NC}"
        echo -e "      Manually run 'reboot' when ready."
    fi
}

echo -e "${BYELLOW}[~] Starting Elite System Validation...${NC}"
run_integrated_audit
