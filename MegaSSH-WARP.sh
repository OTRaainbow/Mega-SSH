#!/bin/bash

# ==============================================================================
# MegaSSH Implementation - WARP Mode
# OS: Ubuntu 24.04 (Noble) Optimized
# Features: Base Security + Cloudflare WARP Outbound
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

print_banner() {
    clear
    echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN}  __  __                  SSSSS   SSSSS  HH   HH                         ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN} |  \/  | ___  __ _  __ _SS      SS      HH   HH                         ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN} | |\/| |/ _ \/ _\` |/ _\` |SSSSS   SSSSS  HHH HHH                         ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN} | |  | |  __/ (_| | (_| |    SS      SS HH   HH                         ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN} |_|  |_|\___|\__, |\__,_|SSSSS   SSSSS  HH   HH                         ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN}              |___/                                                      ${BBLUE}║${NC}"
    echo -e "${BBLUE}║                                                                             ║${NC}"
    echo -e "${BBLUE}║${NC} ${BWHITE}             WARP ADD-ON MODULE (Cloudflare Tunnel)                          ${BBLUE}║${NC}"
    echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
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

# --- Execution ---
print_banner

# --- GITHUB DEPLOYMENT CONFIG ---
# YOUR GITHUB CONFIGURATION:
REPO_BASE="https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main"
# --------------------------------

# 1. Run Base Setup first
print_step "1/4" "Fetch & Run MegaSSH Core..."
if [ ! -f "MegaSSH.sh" ]; then
    print_info "Fetching MegaSSH.sh..."
    wget -q -O "MegaSSH.sh" "${REPO_BASE}/MegaSSH.sh"
fi

if [ ! -f "MegaSSH.sh" ]; then
    print_error "Failed to download MegaSSH.sh!"
    exit 1
fi

print_warn "Running MegaSSH.sh (Core Installer)..."
chmod +x MegaSSH.sh
./MegaSSH.sh
if [ $? -ne 0 ]; then
    print_error "MegaSSH.sh execution failed! Aborting."
    exit 1
fi

# Re-print banner after MegaSSH clears screen
print_banner
print_success "Base Setup Complete"

# 2. Install Cloudflare WARP
print_step "2/4" "Installing Cloudflare WARP..."
rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
VERSION_CODENAME=$(lsb_release -cs)
[ "$VERSION_CODENAME" == "" ] && VERSION_CODENAME="noble"
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $VERSION_CODENAME main" | tee /etc/apt/sources.list.d/cloudflare-client.list
apt update && apt install -y cloudflare-warp

# Ensure Service is Running
print_step "2.1" "Checking WARP Service..."
# Force Cleanup of Stale Sockets/Processes
systemctl stop warp-svc > /dev/null 2>&1
killall warp-svc > /dev/null 2>&1
rm -rf /run/cloudflare-warp > /dev/null 2>&1

systemctl enable warp-svc
systemctl restart warp-svc
sleep 5
if ! systemctl is-active --quiet warp-svc; then
    print_error "WARP Service (warp-svc) failed to start!"
    systemctl status warp-svc --no-pager
    exit 1
fi
print_success "WARP Service Active"

# 3. Register and Configure
print_step "3/4" "Registering WARP Account..."
# Reset state if re-running
warp-cli --accept-tos disconnect > /dev/null 2>&1
warp-cli --accept-tos registration delete > /dev/null 2>&1

# Register with verbose output
if ! warp-cli --accept-tos registration new; then
    print_error "Registration Failed! Retrying with clean state..."
    rm -rf /var/lib/cloudflare-warp/*
    systemctl restart warp-svc
    sleep 3
    warp-cli --accept-tos registration new
fi
print_success "Account Registered"

print_step "4/4" "Configuring WARP Mode (Global Routing)..."
warp-cli --accept-tos mode warp

# -------------------------------------------------------------
# ANTI-LOCKOUT: Exclude IPs to preserve SSH access
# -------------------------------------------------------------
print_step "Applying Anti-Lockout Rules..."

# -------------------------------------------------------------
# ROBUST ROUTING: FwMark Bypass (Fixes Iran/VPN Blocks)
# -------------------------------------------------------------
print_step "Applying Enhanced Routing (FwMark)..."

# 1. Clean up old rules
ip rule del fwmark 0x100 lookup main 2>/dev/null

# 2. Add Routing Rule
# Traffic marked with 0x100 uses specific table (main) -> Bypasses WARP
ip rule add fwmark 0x100 lookup main prio 900

# 3. Mark Outgoing Traffic from Service Ports
# We explicitly mark packets originating from our VPN/SSH ports so they behave "Normally"
PORTS_TCP="22 443 2222 2223 2224 2225 7301 8443 9443"
PORTS_UDP="7301"

print_info "Marking Service Ports (Bypassing WARP for Inbound/Outbound consistency)..."

# TCP Ports
for PORT in $PORTS_TCP; do
   iptables -t mangle -D OUTPUT -p tcp --sport $PORT -j MARK --set-mark 0x100 2>/dev/null
   iptables -t mangle -A OUTPUT -p tcp --sport $PORT -j MARK --set-mark 0x100
done

# UDP Ports
for PORT in $PORTS_UDP; do
   iptables -t mangle -D OUTPUT -p udp --sport $PORT -j MARK --set-mark 0x100 2>/dev/null
   iptables -t mangle -A OUTPUT -p udp --sport $PORT -j MARK --set-mark 0x100
done

# 4. Detect Current SSH Client IP (Backup access)
CLIENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
if [ -n "$CLIENT_IP" ]; then
    print_info "Excluding Your IP:   ${CLIENT_IP}"
    warp-cli --accept-tos tunnel ip add "$CLIENT_IP" > /dev/null 2>&1
fi

print_warn "Connecting to WARP (This may take a moment)..."
warp-cli --accept-tos connect

# Wait for connection
MAX_RETRIES=10
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
    STATUS=$(warp-cli --accept-tos status | grep "Status")
    if [[ "$STATUS" == *"Connected"* ]]; then
        break
    fi
    echo -n "."
    sleep 2
    COUNT=$((COUNT+1))
done
echo ""

# Verification
print_step "Verifying WARP Connection..."
WARP_IP=$(curl -s --max-time 5 https://ifconfig.me)
IS_WARP=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep "warp=on")

STATUS=$(warp-cli --accept-tos status | grep "Status")
print_success "WARP Active: $STATUS"

echo ""
echo ""
echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BBLUE}║${NC} ${BGREEN}                   WARP INTEGRATION COMPLETED SUCCESSFULLY                   ${BBLUE}║${NC}"
echo -e "${BBLUE}╠═════════════════════════════════════════════════════════════════════════════╣${NC}"
if [ -n "$IS_WARP" ]; then
    printf "${BBLUE}║${NC}   • ${BGREEN}WARP Status:${NC}   ACTIVE (System-wide)                                   ${BBLUE}║${NC}\n"
    printf "${BBLUE}║${NC}   • ${BCYAN}Public IP:${NC}     %-33s        ${BBLUE}║${NC}\n" "$WARP_IP (Protected)"
else
    printf "${BBLUE}║${NC}   • ${BRED}WARP Status:${NC}   CONNECTION FAILED                                      ${BBLUE}║${NC}\n"
    printf "${BBLUE}║${NC}   • ${BYELLOW}Debug:${NC}         Check 'journalctl -u warp-svc'                         ${BBLUE}║${NC}\n"
fi
echo -e "${BBLUE}║${NC}   • ${BCYAN}Usage:${NC}         All server traffic is now routed through Cloudflare.   ${BBLUE}║${NC}"
echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

