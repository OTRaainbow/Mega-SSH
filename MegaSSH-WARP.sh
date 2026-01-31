#!/bin/bash

# ==============================================================================
# MegaSSH Implementation - WARP Mode
# OS: Ubuntu 24.04 (Noble) Optimized
# Features: Base Security + Cloudflare WARP Outbound
# ==============================================================================

# --- UI & Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  __  __                  SSSSS   SSSSS  HH   HH "
    echo " |  \/  | ___  __ _  __ _SS      SS      HH   HH "
    echo " | |\/| |/ _ \/ _\` |/ _\` |SSSSS   SSSSS  HHH HHH "
    echo " | |  | |  __/ (_| | (_| |    SS      SS HH   HH "
    echo " |_|  |_|\___|\__, |\__,_|SSSSS   SSSSS  HH   HH "
    echo "              |___/                              "
    echo "             WARP ADD-ON MODULE                  "
    echo -e "${NC}"
    echo -e "${BLUE}=================================================${NC}"
}

print_step() { echo -e "${CYAN}[Step $1] ${NC}$2"; }
print_success() { echo -e "${GREEN}[✔] $1${NC}"; }
print_error() { echo -e "${RED}[✘] $1${NC}"; }

# --- Execution ---
print_banner

# --- GITHUB DEPLOYMENT CONFIG ---
# YOUR GITHUB CONFIGURATION:
REPO_BASE="https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main"
# --------------------------------

# 1. Run Base Setup first
print_step "1/4" "Fetch & Run MegaSSH Core..."
if [ ! -f "MegaSSH.sh" ]; then
    echo -e "${YELLOW}[~] Fetching MegaSSH.sh...${NC}"
    wget -q -O "MegaSSH.sh" "${REPO_BASE}/MegaSSH.sh"
fi

if [ ! -f "MegaSSH.sh" ]; then
    print_error "Failed to download MegaSSH.sh!"
    exit 1
fi

echo -e "\033[1;33m[~] Running MegaSSH.sh (Core Installer)...\033[0m"
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
print_step "Checking WARP Service..."
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
echo -e "${YELLOW}[~] Connecting to WARP (This may take a moment)...${NC}"
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
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}       WARP INTEGRATION COMPLETE                 ${NC}"
echo -e "${BLUE}=================================================${NC}"
if [ -n "$IS_WARP" ]; then
    echo -e "  • ${GREEN}WARP Status:${NC}   ACTIVE (System-wide)"
    echo -e "  • ${CYAN}Public IP:${NC}     $WARP_IP (Protected)"
else
    echo -e "  • ${RED}WARP Status:${NC}   CONNECTION FAILED"
    echo -e "  • ${YELLOW}Debug:${NC}         Check 'journalctl -u warp-svc'"
fi
echo -e "  • ${CYAN}Usage:${NC}       All server traffic is now routed through Cloudflare."
echo ""

