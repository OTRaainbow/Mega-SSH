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
# REPLACE WITH YOUR GITHUB RAW URL:
REPO_BASE="https://raw.githubusercontent.com/ChangeMe/MegaSSH/main"
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
(
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    VERSION_CODENAME=$(lsb_release -cs)
    [ "$VERSION_CODENAME" == "" ] && VERSION_CODENAME="noble"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $VERSION_CODENAME main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt update && apt install -y cloudflare-warp
) > /dev/null 2>&1
print_success "WARP Installed"

# 3. Register and Configure
print_step "3/4" "Registering WARP Account..."
warp-cli --accept-tos register > /dev/null 2>&1
print_success "Account Registered"

print_step "4/4" "Configuring Proxy Mode (Port 40000)..."
warp-cli --accept-tos set-mode proxy > /dev/null 2>&1
warp-cli --accept-tos set-proxy-port 40000 > /dev/null 2>&1
warp-cli --accept-tos connect > /dev/null 2>&1
sleep 5
STATUS=$(warp-cli --accept-tos status | grep "Status")
print_success "WARP Active: $STATUS"

echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}       WARP INTEGRATION COMPLETE                 ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "  • ${CYAN}SOCKS5 Proxy:${NC}  127.0.0.1:40000"
echo -e "  • ${CYAN}Usage:${NC} Configure outbound tools to use this proxy."
echo ""
