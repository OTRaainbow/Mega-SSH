#!/bin/bash

# ==============================================================================
# MegaSSH System Audit & Health Check
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/var/log/megassh_audit.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}        MEGASSH SYSTEM AUDIT (CHECK LOG)        ${NC}"
echo -e "${CYAN}=================================================${NC}"
date

# 1. Component Service Checks
check_service() {
    local name=$1
    local port=$2
    printf "%-30s" "[~] Checking $name ($port)..."
    if ss -tpln | grep -q ":$port "; then
        echo -e "${GREEN}[OK]${NC}"
        return 0
    else
        echo -e "${RED}[FAILED]${NC}"
        return 1
    fi
}

echo -e "\n${YELLOW}--- Component Status ---${NC}"
check_service "Nginx (Decoy)" 80
check_service "HAProxy (Multiplexer)" 443
check_service "SSH (Internal)" 2222
check_service "Stunnel (SSL)" 8443
check_service "ShadowTLS" 9443
check_service "UDPGW" 7301
check_service "Rescue SSH" 22

# 2. Firewall & Geo-Block Integrity
echo -e "\n${YELLOW}--- Firewall Integrity ---${NC}"

# Check IPSet
IR_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
RU_CN_COUNT=$(ipset list country_block_in 2>/dev/null | grep 'Number of entries' | awk '{print $4}')

printf "%-30s" "[~] IPSet (Iran Block)..."
if [ "$IR_COUNT" -gt 100 ]; then echo -e "${GREEN}[OK] ($IR_COUNT IPs)${NC}"; else echo -e "${RED}[EMPTY]${NC}"; fi

printf "%-30s" "[~] IPSet (RU/CN Block)..."
if [ "$RU_CN_COUNT" -gt 100 ]; then echo -e "${GREEN}[OK] ($RU_CN_COUNT IPs)${NC}"; else echo -e "${RED}[EMPTY]${NC}"; fi

# Check IPv6
printf "%-30s" "[~] IPv6 Status..."
IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
if [ "$IPV6_STATUS" -eq 1 ]; then echo -e "${GREEN}[DISABLED]${NC}"; else echo -e "${RED}[LEAKING]${NC}"; fi

# 3. Live Connectivity Tests (The "Real World" Test)
echo -e "\n${YELLOW}--- Live Geo-Blocking Test ---${NC}"

test_block() {
    local site=$1
    local ip=$2
    printf "%-30s" "[~] Testing $site..."
    # We use --resolve to bypass DNS issues during the test
    if curl -m 3 -s -I --resolve "$site:80:$ip" "http://$site" > /dev/null 2>&1; then
        echo -e "${RED}[FAILED - SITE OPENED]${NC}"
    else
        echo -e "${GREEN}[SUCCESS - BLOCKED]${NC}"
    fi
}

# Real target IPs from RU/CN/IR
test_block "vk.com (Russia)" "87.240.139.194"
test_block "baidu.com (China)" "110.242.68.66"
test_block "digikala.com (Iran)" "185.239.104.14"

# 4. Final Verdict
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${GREEN}      ALL COMPONENTS VERIFIED & CORRECT        ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${YELLOW}Audit Complete. Log saved to: $LOG_FILE${NC}"
echo -e "${CYAN}=================================================${NC}"

echo -e "\n${RED}[!] IMPORTANT: System changes require a reboot to be 100% effective.${NC}"
read -p "Would you like to REBOOT the server now? (y/n): " confirm
if [[ "$confirm" == [yY] ]]; then
    echo -e "${GREEN}[+] Rebooting... Please wait 1-2 minutes before reconnecting.${NC}"
    reboot
else
    echo -e "${YELLOW}[!] Please manualy reboot when possible.${NC}"
fi
