#!/bin/bash

# ==============================================================================
# UDPGW Installer (BadVPN)
# Optimized for Ubuntu 24.04
# ==============================================================================

PORT_UDPGW=7301

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

print_step "3.1" "Starting UDPGW (BadVPN) Installation..."
# Install Build Dependencies
apt update
apt install -y git cmake make gcc build-essential

# Build BadVPN if not present
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
    print_warn "Compiling BadVPN-UDPGW (This may take a minute)..."
    mkdir -p /root/badvpn_build
    cd /root/badvpn_build
    
    # Clone specific tag or master
    git clone https://github.com/ambrop72/badvpn.git .
    
    # Compile
    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .
    make
    
    # Install
    cp udpgw/badvpn-udpgw /usr/local/bin/
    chmod +x /usr/local/bin/badvpn-udpgw
    
    # Cleanup
    cd /root
    rm -rf /root/badvpn_build
    print_success "BadVPN Compiled Successfully."
else
    print_success "BadVPN is already installed."
fi

# Create Systemd Service
print_info "Creating UDPGW Service on Port ${PORT_UDPGW}..."
cat > /etc/systemd/system/udpgw.service <<EOF
[Unit]
Description=BadVPN UDPGW
After=network.target

[Service]
# Optimized UDPGW Flags for High Volume
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT_UDPGW} --max-clients 2000 --max-connections-for-client 10 --loglevel 0
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable & Start
systemctl daemon-reload
systemctl enable --now udpgw

print_success "UDPGW Service Started."
