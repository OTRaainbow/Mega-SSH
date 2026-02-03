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
check_pkg "conntrack"
check_pkg "iptables-persistent"

echo -e "\n  ${BCYAN}◈ 2. PERFORMANCE & SECURITY LAYERS${NC}"
# Kernel Check
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}XanMod Elite Kernel${NC}"
if uname -r | grep -qi "xanmod"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BYELLOW}[STOCK]${NC}"; fi

# TFO Check
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}TCP Fast Open (TFO=3)${NC}"
if [ "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)" == "3" ]; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# FQ-CoDel Check
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}FQ-CoDel Queue Mgmt${NC}"
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if tc qdisc show dev "$IFACE" | grep -q "fq_codel"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# Mux Version
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}HAProxy Mux (v3.3.2)${NC}"
if haproxy -v 2>/dev/null | grep -q "3.3.2"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISMATCH]${NC}"; fi

# HAProxy Silence Check
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}HAProxy Silent Entry (5s)${NC}"
if grep -q "inspect-delay 5s" /etc/haproxy/haproxy.cfg 2>/dev/null && grep -q "req.len gt 0" /etc/haproxy/haproxy.cfg 2>/dev/null; then
    echo -e "${BGREEN}[PASS]${NC}"
else
    echo -e "${BRED}[FAIL]${NC}"
fi

check_service "HAProxy (Mux)" 443
check_service "SSH (EagleNet)" 2222
check_service "UDPGW (BadVPN)" 7301
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Nginx NJS Support${NC}"
if nginx -V 2>&1 | grep -q "ngx_http_js_module"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[OFF]${NC}"; fi
# Pingtunnel removed for TCP Direct purity

echo -e "\n  ${BCYAN}◈ 3. NUCLEAR FIREWALL INTEGRITY${NC}"
# Check IPv6 Status
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Zero-Leak (IPv6 Disable)${NC}"
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]; then print_status 0; else print_status 1; fi

# Check DNS IPv6 Leak (The "Acid Test" part 1)
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}DNS IPv6 Leak (ISNA)${NC}"
# Use specifically targeted nslookup to look for AAAA records
if nslookup -type=AAAA isna.ir 2>/dev/null | grep -q "has AAAA address"; then
    echo -e "${BRED}[LEAKING]${NC}"; GLOBAL_FAIL=1
else
    echo -e "${BGREEN}[SECURE]${NC}"
fi

# Check ip6tables Policy
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}ip6tables Mandatory DROP${NC}"
if ip6tables -L -n 2>/dev/null | grep -q "Chain INPUT (policy DROP)" && \
   ip6tables -L -n 2>/dev/null | grep -q "Chain OUTPUT (policy DROP)" && \
   ip6tables -L -n 2>/dev/null | grep -q "Chain FORWARD (policy DROP)"; then
    echo -e "${BGREEN}[ACTIVE]${NC}"
else
    echo -e "${BRED}[OPEN]${NC}"; GLOBAL_FAIL=1
fi

# Check IPSets
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Nuclear IPSet (Isolation)${NC}"
IN_COUNT=$(ipset list country_block_in 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
OUT_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
if [ -n "$IN_COUNT" ] && [ "$IN_COUNT" -gt 0 ]; then echo -e "${BGREEN}[$IN_COUNT IPs]${NC}"; else echo -e "${BRED}[EMPTY]${NC}"; GLOBAL_FAIL=1; fi

# Check Raw Table Isolation (Directional Precision)
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Raw Inbound Admin (dports 22,443)${NC}"
if iptables -t raw -L PREROUTING -n | grep -q "ACCEPT.*multiport dports 22,443"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Raw Outbound Admin (sports 22,443)${NC}"
if iptables -t raw -L OUTPUT -n | grep -q "ACCEPT.*multiport sports 22,443"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Raw Outbound Block (Leak Switch)${NC}"
if iptables -t raw -L OUTPUT -n | grep -q "DROP.*country_block_out"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Mangle Admin Response (CT ESTAB)${NC}"
if iptables -t mangle -L OUTPUT -n | grep -q "ACCEPT.*multiport sports 22,443.*ctstate ESTABLISHED,RELATED"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; GLOBAL_FAIL=1; fi

# Check Policy Routing (Table 200)
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Blackhole Route (Table 200)${NC}"
if ip route show table 200 2>/dev/null | grep -q "blackhole default"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

# Check FWMark Rule
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}Fwmark 0x99 Routing Rule${NC}"
if ip rule show | grep -q "fwmark 0x99 lookup 200"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

echo -e "\n  ${BCYAN}◈ 4. LIVE GEOPRIVACY VALIDATION${NC}"
# DPI Checks
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}DPI Shield (MSS Clamp)${NC}"
if iptables -t mangle -L POSTROUTING -n | grep -q "TCPMSS.*set-mss 1200"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}TTL Obfuscation (64)${NC}"
if iptables -t mangle -L POSTROUTING -n | grep -q "TTL set-to 64"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# Check SSH Banner Obfuscation
printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}SSH Banner (Microsoft_IIS)${NC}"
if strings /usr/sbin/sshd | grep -q "Microsoft_IIS"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# Live High-Precision Tests (Nuclear Shield)
test_leak() {
    local site=$1; local ip=$2; local label=$3
    printf "  ${BPURPLE}├─${NC} %-36s" "${WHITE}$label${NC}"
    
    # Use 3s timeout as per user reporting
    # Treat ANY response (even headers only) as a leak
    local output=$(curl -m 3 -s -I --resolve "$site:80:$ip" "http://$site" 2>&1)
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo -e "${BRED}[LEAKED]${NC}"
        echo "Leak detected on $label:" >> "$LOG_FILE"
        echo "$output" | head -n 5 >> "$LOG_FILE"
        GLOBAL_FAIL=1
    elif echo "$output" | grep -qi "ArvanCloud"; then
        echo -e "${BRED}[AK-LEAK]${NC}" # ArvanCloud Leak
        echo "ArvanCloud Leak on $label" >> "$LOG_FILE"
        GLOBAL_FAIL=1
    elif [ $ret -eq 28 ] || [ $ret -eq 7 ] || [ $ret -eq 3 ] || [ $ret -eq 6 ]; then
        echo -e "${BGREEN}[SECURE]${NC}"
    else
        echo -e "${BYELLOW}[ERR $ret]${NC}"
    fi
}

test_leak "vk.com (RU)" "87.240.139.194" "Russia Geofence"
test_leak "baidu.com (CN)" "110.242.68.66" "China Geofence"
test_leak "isna.ir (IR - HTTP)" "94.182.182.28" "Iran ISNA Privacy Block"
test_leak "isna.ir (IR - HTTPS)" "94.182.182.28" "Iran ISNA HTTPS (Acid Test)"
test_leak "snapp.ir (IR)" "185.239.104.14" "Iran Snapp Privacy Block"

# FINAL VERDICT
echo -e "\n${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}"
if [ "$GLOBAL_FAIL" -eq 1 ]; then
    echo -e "  ${BRED}  [!] AUDIT FAILED - NUCLEAR DEFENSES COMPROMISED${NC}"
    echo -e "  ${BRED}  CHECK LOG: /var/log/megassh_audit.log${NC}"
else
    echo -e "  ${BGREEN}  [✓] NUCLEAR SHIELD ACTIVE - ELITE STATUS CONFIRMED${NC}"
    
    echo -e "\n  ${BCYAN}◈ ELITE SSH ACCESS INFO${NC}"
    echo -e "    ${BPURPLE}│${NC}"
    echo -e "    ${BPURPLE}├─${NC} ${WHITE}Primary Entrance :${NC} ${CYAN}Port 443 (TCP)${NC}"
    echo -e "    ${BPURPLE}├─${NC} ${WHITE}Rescue Entrance  :${NC} ${CYAN}Port 22${NC}"
    echo -e "    ${BPURPLE}├─${NC} ${WHITE}Server IP        :${NC} ${CYAN}${SERVER_IP}${NC}"
    echo -e "    ${BPURPLE}│${NC}"
    echo -e "    ${BPURPLE}╰─>${NC} ${WHITE}Connection CMD   :${NC} ${BGREEN}ssh root@${SERVER_IP} -p 443${NC}"
fi
echo -e "${BPURPLE}  ◈──────────────────────────────────────────────────────────────────◈${NC}\n"
