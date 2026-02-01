#!/bin/bash

# ==============================================================================
# Stunnel Manager (SSL Wrapping for SSH)
# Adds a layer of TLS encryption to hide SSH traffic
# Listen: 8443 (SSL) -> Forward: 2222 (SSH)
# ==============================================================================

PORT_STUNNEL=8443
PORT_SSH_INTERNAL=2222
CERT_DIR="/etc/stunnel"
CERT_FILE="$CERT_DIR/stunnel.pem"

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

print_step "7.1" "Initializing Stunnel (SSL Wrapper)..."

# 1. Install Stunnel
apt update
apt install -y stunnel4 openssl

# 2. Generate Certificate
if [ ! -f "$CERT_FILE" ]; then
    print_warn "Generating Self-Signed SSL Certificate..."
    mkdir -p "$CERT_DIR"
    openssl req -new -x509 -days 365 -nodes \
        -out "$CERT_FILE" -keyout "$CERT_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=www.rubika.ir" >/dev/null 2>&1
    chmod 600 "$CERT_FILE"
    print_success "Certificate Generated."
else
    print_success "Certificate already exists."
fi

# 3. Configure Stunnel
print_info "Configuring Stunnel Config..."
cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel4/stunnel.pid
cert = $CERT_FILE
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-tls]
accept = $PORT_STUNNEL
connect = 127.0.0.1:$PORT_SSH_INTERNAL
EOF

# 4. Enable and Start
sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
systemctl enable stunnel4
systemctl restart stunnel4

print_success "Stunnel is running on Port $PORT_STUNNEL."
print_info "Connect using an Stunnel client -> YourIP:$PORT_STUNNEL"
