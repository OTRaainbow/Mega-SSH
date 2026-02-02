#!/bin/bash

# ==============================================================================
# MegaSSH System Audit (Antigravity Edition - v6.1)
# Features: ICMP Transparent Tunnel Check, Elite UI
# ==============================================================================

# --- Antigravity UI & Colors ---
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BCYAN='\033[1;36m'
BPURPLE='\033[1;35m'
BWHITE='\033[1;37m'
BGREEN='\033[1;32m'
BRED='\033[1;31m'
NC='\033[0m'

LOG_FILE="/var/log/megassh_audit.log"
echo "Audit started at $(date)" > "$LOG_FILE"

print_header() {
    clear
    echo -e "${BCYAN}◈ MEGASSH ELITE SYSTEM AUDIT${NC}"
    echo -e "${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
    date
}

print_status() {
    if [ "$1" -eq 0 ]; then
        echo -e "${BGREEN}[PASS]${NC}"
    else
        echo -e "${BRED}[FAIL]${NC}"
        GLOBAL_FAIL=1
    fi
}

GLOBAL_FAIL=0
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

print_header

# --- 1. Critical File Integrity ---
echo -e "\n${BCYAN}◈ 1. FILE INTEGRITY CHECK${NC}"
check_file() {
    local file=$1
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$file${NC}"
    if [ -f "$file" ]; then
        print_status 0
    else
        print_status 1
        echo "Missing File: $file" >> "$LOG_FILE"
    fi
}

check_file "MegaSSH.sh"
check_file "high_perf_optimizer.sh"
check_file "firewall_manager.sh"
check_file "strict_block.sh"
check_file "pingtunnel_manager.sh"
check_file "useradd.py"

# --- 2. Package Installation Status ---
echo -e "\n${BCYAN}◈ 2. DEPENDENCY VERIFICATION${NC}"
check_pkg() {
    local pkg=$1
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$pkg${NC}"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        print_status 0
    else
        print_status 1
        echo "Missing Package: $pkg" >> "$LOG_FILE"
    fi
}

check_pkg "nginx"
check_pkg "haproxy"
check_pkg "ipset"
check_pkg "iptables-persistent"

# --- 3. Service Status & Ports ---
echo -e "\n${BCYAN}◈ 3. SERVICE MAPPING & PORTS${NC}"
check_service() {
    local name=$1
    local port=$2
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$name ($port)${NC}"
    if ss -tpln | grep -q ":$port "; then
        print_status 0
    else
        print_status 1
        echo "Service Down: $name ($port)" >> "$LOG_FILE"
    fi
}

check_service "Nginx (Decoy)" 80
check_service "HAProxy (Mux)" 443
check_service "SSH (Internal)" 2222
check_service "UDPGW" 7301
check_service "Rescue SSH" 22

# --- 3.5 Pingtunnel Health ---
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Pingtunnel Service${NC}"
if systemctl is-active --quiet pingtunnel; then print_status 0; else print_status 1; fi

# --- 4. Firewall & Geo-Block Integrity ---
echo -e "\n${BCYAN}◈ 4. NUCLEAR FIREWALL INTEGRITY${NC}"

# Check IPSet
IR_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Geofence Entries (Out)${NC}"
if [ -n "$IR_COUNT" ] && [ "$IR_COUNT" -gt 0 ]; then
    echo -e "${BGREEN}[$IR_COUNT IPs]${NC}"
else
    print_status 1
fi

# Check IPv6
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Zero-Leak (IPv6 Disable)${NC}"
IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
if [ "$IPV6_STATUS" == "1" ]; then
    print_status 0
else
    print_status 1
fi

# --- 5. Final Connection Verdict ---
echo -e "\n${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
if [ "$GLOBAL_FAIL" -eq 1 ]; then
    echo -e "${BRED}  [!] AUDIT FAILED - CHECK /var/log/megassh_audit.log${NC}"
else
    echo -e "${BGREEN}  [✓] ALL SYSTEMS NOMINAL - ELITE STATUS CONFIRMED${NC}"
    
    # Antigravity UI Block
    echo ""
    echo -e "${BCYAN}◈ SSH OVER ICMP (TRANSPARENT TUNNEL) CONFIGURATION${NC}"
    echo -e "  ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${WHITE}Local Entrance:${NC}  ${CYAN}127.0.0.1:443${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${WHITE}Transport:${NC}       ${CYAN}ICMP Stealth Tunnel${NC}"
    echo -e "  ${BPURPLE}├─${NC} ${WHITE}Remote Target:${NC}   ${CYAN}${SERVER_IP}:443${NC}"
    echo -e "  ${BPURPLE}│${NC}"
    echo -e "  ${BPURPLE}╰─>${NC} ${WHITE}Local Client CMD:${NC} ${BGREEN}sudo ./pingtunnel -type client -l :443 -s ${SERVER_IP} -t 127.0.0.1:443 -key 123456${NC}"
    echo -e "  ${BPURPLE}╰─>${NC} ${WHITE}Final SSH CMD:${NC}   ${BGREEN}ssh root@127.0.0.1 -p 443${NC}"
fi
echo -e "${BPURPLE}─────────────────────────────────────────────────────────────────────────────${NC}"
echo ""
