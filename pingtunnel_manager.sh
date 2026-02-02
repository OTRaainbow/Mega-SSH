#!/bin/bash

# ==============================================================================
# Pingtunnel Manager (Community Edition - ICMP Tunnel Server)
# Source: https://github.com/hoseinlolready/Pingtunnel_manager.git
# Optimized for Ubuntu 24.04 & SSH Direct Port 443
# ==============================================================================

# --- Professional UI & Colors ---
BBLUE='\033[1;34m'
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
BWHITE='\033[1;37m'
NC='\033[0m'

print_step() { echo -e "${BBLUE}[ STEP ]${NC} ${BWHITE}$1${NC}"; }
print_info() { echo -e "${BBLUE}[ INFO ]${NC} $1"; }
print_success() { echo -e "${BGREEN}[  OK  ]${NC} $1"; }
print_error() { echo -e "${BRED}[ FAIL ]${NC} $1"; }
print_warn() { echo -e "${BYELLOW}[ WARN ]${NC} $1"; }

# Variables
TARGET_PORT=443 # Prioritize 443 for SSH Direct logic
PINGTUNNEL_KEY="123456" # User's preferred key

# 1. Clone Community Manager
print_step "Cloning Pingtunnel Manager Repository..."
if [ -d "/root/Pingtunnel_manager" ]; then
    rm -rf /root/Pingtunnel_manager
fi
git clone https://github.com/hoseinlolready/Pingtunnel_manager.git /root/Pingtunnel_manager >/dev/null 2>&1
if [ $? -ne 0 ]; then
    print_error "Failed to clone repository. Continuing with standalone binary installation..."
else
    print_success "Repository cloned successfully."
fi

# 2. Standalone Binary Installation (Ensuring binary is in place)
# We handle the binary ourselves to ensure non-interactive stability
print_step "Downloading and Installing Pingtunnel Binary..."
mkdir -p /usr/local/bin
cd /tmp
wget -q https://github.com/esrrhs/pingtunnel/releases/latest/download/pingtunnel_linux_amd64.zip
unzip -o pingtunnel_linux_amd64.zip > /dev/null
mv pingtunnel /usr/local/bin/pingtunnel_server
chmod +x /usr/local/bin/pingtunnel_server
rm pingtunnel_linux_amd64.zip
print_success "Pingtunnel binary installed."

# 3. Kernel Optimization
print_step "Configuring Kernel ICMP Settings..."
echo "net.ipv4.icmp_echo_ignore_all=1" > /etc/sysctl.d/98-pingtunnel.conf
sysctl -p /etc/sysctl.d/98-pingtunnel.conf > /dev/null
print_success "Kernel set to ignore echo (Pingtunnel takes control)."

# 4. Create Systemd Service (Targeting Port 443)
print_step "Creating Pingtunnel Service (Target: ${TARGET_PORT})..."
cat > /etc/systemd/system/pingtunnel.service <<EOF
[Unit]
Description=Pingtunnel (Community - ICMP Tunnel Server)
After=network.target

[Service]
Type=simple
User=root
# -type server: Runs in server mode
# -key: Security key
# -nolog: Performance optimization (decreases disk latency)
# -t 127.0.0.1:443: Forwarding to HAProxy Multiplexer
ExecStart=/usr/local/bin/pingtunnel_server -type server -key ${PINGTUNNEL_KEY} -t 127.0.0.1:${TARGET_PORT} -nolog 1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pingtunnel
print_success "Pingtunnel service targeting port ${TARGET_PORT} started."

# 5. Final Verification
if systemctl is-active --quiet pingtunnel; then
    print_success "Pingtunnel is ACTIVE."
else
    print_error "Pingtunnel FAILED to start. Check 'journalctl -u pingtunnel'."
fi
