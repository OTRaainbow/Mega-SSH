#!/bin/bash

# ==============================================================================
# ShadowTLS Manager (v3)
# Advanced "Wrapper" that mimics legitimate TLS handshakes (e.g., to Microsoft)
# Listen: 9443 -> Handshake: www.microsoft.com -> Forward: 2222 (SSH)
# ==============================================================================

PORT_SHADOWTLS=9443
PORT_SSH_INTERNAL=2222
HANDSHAKE_DOMAIN="www.microsoft.com:443"
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

print_step "7.2" "Initializing ShadowTLS (v3)..."
# 1. Download Registry
print_info "Fetching latest ShadowTLS version..."
LATEST_TAG=$(curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest | grep -oP '"tag_name": "\K[^"]+')
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v0.2.25" # Fallback if API fails
    print_warn "Failed to fetch tag, using fallback: $LATEST_TAG"
fi

DOWNLOAD_URL="https://github.com/ihciah/shadow-tls/releases/download/${LATEST_TAG}/shadow-tls-x86_64-unknown-linux-musl"

print_info "Downloading ShadowTLS ${LATEST_TAG}..."
curl -L -o /usr/local/bin/shadow-tls "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    print_error "Failed to download ShadowTLS binary."
    exit 1
fi
chmod +x /usr/local/bin/shadow-tls

# 2. Create Service
print_info "Configuring Service (Port $PORT_SHADOWTLS)..."
cat > /etc/systemd/system/shadow-tls.service <<EOF
[Unit]
Description=ShadowTLS Wrapper
After=network.target

[Service]
# Mode: Server
# Listen: $PORT_SHADOWTLS
# Server to mimicking: $HANDSHAKE_DOMAIN
# Target (our SSH): 127.0.0.1:$PORT_SSH_INTERNAL
# Password: Let's use a random or fixed password. For SSH wrapper, the password is used by the client wrapper.
# We'll use the same PASSWORD variable style if needed, or a fixed one for the tunnel.
# ShadowTLS V3 syntax: shadow-tls --fastopen server --listen 0.0.0.0:9443 --server 127.0.0.1:2222 --tls www.microsoft.com:443 --password mypassword
ExecStart=/usr/local/bin/shadow-tls --fastopen server --listen 0.0.0.0:${PORT_SHADOWTLS} --server 127.0.0.1:${PORT_SSH_INTERNAL} --tls ${HANDSHAKE_DOMAIN} --password megassh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable & Start
systemctl daemon-reload
systemctl enable --now shadow-tls

print_success "ShadowTLS Active on Port $PORT_SHADOWTLS."
print_info "Mimicking: $HANDSHAKE_DOMAIN"
print_info "Password:  megassh"
