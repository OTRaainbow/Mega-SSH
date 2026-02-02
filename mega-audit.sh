#!/bin/bash

# ==============================================================================
# MegaSSH Elite Audit (Stability Focus - v6.2)
# Features: ICMP Transparent Tunnel Check, Elite UI, Board Rendering
# ================= project: https://github.com/OTRaainbow/Mega-SSH ============

# --- Antigravity UI & Colors ---
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BCYAN='\033[1;36m'
BPURPLE='\033[1;35m'
BWHITE='\033[1;37m'
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/megassh_audit.log"
echo "Audit started at $(date)" > "$LOG_FILE"
GLOBAL_FAIL=0
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

print_header() {
    clear
    echo -e "${BCYAN}      __  __                      ${BPURPLE}SSSSS   SSSSS  HH   HH${NC}"
    echo -e "${BCYAN}     |  \/  | ___  __ _  __ _    ${BPURPLE}SS      SS      HH   HH${NC}"
    echo -e "${BCYAN}     | |\/| |/ _ \/ _\` |/ _\` |    ${BPURPLE}SSSSS   SSSSS  HHH HHH${NC}"
    echo -e "${BCYAN}     | |  | |  __/ (_| | (_| |       ${BPURPLE}SS      SS HH   HH${NC}"
    echo -e "${BCYAN}     |_|  |_|\___|\__, |\__,_|    ${BPURPLE}SSSSS   SSSSS  HH   HH${NC}"
    echo -e "${BCYAN}                   |___/                                ${NC}"
    echo ""
    echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}AUDIT SYSTEM:${NC} ${BCYAN}MegaSSH Elite Core Integrity Check${NC}           ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}LAST SYNC   :${NC} ${BCYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}                    ${BPURPLE}│${NC}"
    echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
}

print_status() {
    if [ "$1" -eq 0 ]; then
        echo -e "${BGREEN}[PASS]${NC}"
    else
        echo -e "${BRED}[FAIL]${NC}"
        GLOBAL_FAIL=1
    fi
}

check_file() {
    local file=$1; printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$file${NC}"
    if [ -f "$file" ]; then print_status 0; else print_status 1; echo "Missing: $file" >> "$LOG_FILE"; fi
}

check_pkg() {
    local pkg=$1; printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$pkg${NC}"
    if dpkg -s "$pkg" >/dev/null 2>&1; then print_status 0; else print_status 1; echo "Missing pkg: $pkg" >> "$LOG_FILE"; fi
}

check_service() {
    local name=$1; local port=$2; printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$name ($port)${NC}"
    if ss -tpln | grep -q ":$port "; then print_status 0; else print_status 1; echo "Down: $name ($port)" >> "$LOG_FILE"; fi
}

# START AUDIT
print_header

echo -e "\n  ${BCYAN}◈ 1. CORE INFRASTRUCTURE (FILES & PKGS)${NC}"
check_file "MegaSSH.sh"
check_file "firewall_manager.sh"
check_file "pingtunnel_manager.sh"
check_pkg "haproxy"
check_pkg "nginx"
check_pkg "ipset"

echo -e "\n  ${BCYAN}◈ 2. SECURITY LAYERS (SERVICES)${NC}"
check_service "Nginx (Decoy)" 80
check_service "HAProxy (Mux)" 443
check_service "SSH (EagleNet)" 2222
check_service "UDPGW (BadVPN)" 7301
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Pingtunnel Logic${NC}"
if systemctl is-active --quiet pingtunnel; then print_status 0; else print_status 1; fi

echo -e "\n  ${BCYAN}◈ 3. NETWORK OBFUSCATION & PRIVACY${NC}"
# Check IPv6
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Zero-Leak (IPv6 Disable)${NC}"
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]; then print_status 0; else print_status 1; fi

# Check IPSet
IR_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Privacy Shield (GeoEntries)${NC}"
if [ -n "$IR_COUNT" ] && [ "$IR_COUNT" -gt 0 ]; then echo -e "${BGREEN}[$IR_COUNT IPs]${NC}"; else print_status 1; fi

# Live Test
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Russia Geofence Test${NC}"
if curl -m 3 -s -I --resolve "vk.com:80:87.240.139.194" "http://vk.com" > /dev/null 2>&1; then echo -e "${BRED}[LEAKED]${NC}"; GLOBAL_FAIL=1; else echo -e "${BGREEN}[PROTECTED]${NC}"; fi

# FINAL VERDICT
echo -e "\n${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
if [ "$GLOBAL_FAIL" -eq 1 ]; then
    echo -e "  ${BRED}  [!] AUDIT FAILED - SYSTEM IRREGULARITIES DETECTED${NC}"
    echo -e "  ${BRED}  CHECK LOG: /var/log/megassh_audit.log${NC}"
else
    echo -e "  ${BGREEN}  [✓] ALL SYSTEMS NOMINAL - ELITE STATUS CONFIRMED${NC}"
    
    echo -e "\n  ${BCYAN}◈ SSH OVER ICMP (TRANSPARENT TUNNEL) CONFIGURATION${NC}"
    echo -e "    ${BPURPLE}│${NC}"
    echo -e "    ${BPURPLE}├─${NC} ${WHITE}Entrance :${NC} ${CYAN}127.0.0.1:443${NC}"
    echo -e "    ${BPURPLE}├─${NC} ${WHITE}Server IP:${NC} ${CYAN}${SERVER_IP}${NC}"
    echo -e "    ${BPURPLE}│${NC}"
    echo -e "    ${BPURPLE}╰─>${NC} ${WHITE}Client CMD:${NC} ${BGREEN}sudo ./pingtunnel -type client -l :443 -s ${SERVER_IP} -t 127.0.0.1:443 -key 123456${NC}"
fi
echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}\n"
