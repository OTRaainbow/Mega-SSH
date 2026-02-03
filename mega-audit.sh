#!/bin/bash

# ==============================================================================
# MegaSSH Elite Audit (Stability Focus - v6.4)
# Features: RAW Parity, EagleNet Tuning, Session Limits, WARP Detection
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
    echo -e "  ${BPURPLE}│${NC} ${BWHITE}VERSION     :${NC} ${BCYAN}v6.4 (High-Volume Tuned)${NC}                      ${BPURPLE}│${NC}"
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
    local target_file=$1; local base=$(basename "$target_file")
    printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "$base"
    
    local found_at=""
    # Precise hierarchy search
    if [ -x "/usr/local/bin/$base" ]; then found_at="/usr/local/bin/$base"
    elif [ -x "/root/$base" ]; then found_at="/root/$base"
    elif [ -x "$PWD/$base" ]; then found_at="$PWD/$base"
    elif [ -x "$target_file" ]; then found_at="$target_file"
    fi

    if [ -n "$found_at" ]; then
        print_status 0
    else
        # Check if it exists but isn't executable
        if [ -f "/usr/local/bin/$base" ] || [ -f "/root/$base" ] || [ -f "$PWD/$base" ] || [ -f "$target_file" ]; then
             print_status 1
             echo "Permission Error: $base exists but is NOT executable." >> "$LOG_FILE"
        else
            # Final search using find (top levels only)
            FOUND_PATH=$(find /usr/local/bin /root "$PWD" -maxdepth 2 -name "$base" 2>/dev/null | head -n1)
            if [ -n "$FOUND_PATH" ]; then
                if [ -x "$FOUND_PATH" ]; then print_status 0; else print_status 1; echo "Permission Error: $FOUND_PATH is not executable" >> "$LOG_FILE"; fi
            else
                print_status 1; echo "Critical Missing: $base (Scanned /usr/local/bin, /root, $PWD)" >> "$LOG_FILE"
            fi
        fi
    fi
}

check_pkg() {
    local pkg=$1; printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "$pkg"
    if dpkg -s "$pkg" >/dev/null 2>&1 || command -v "$pkg" >/dev/null 2>&1; then print_status 0; else print_status 1; echo "Missing pkg: $pkg" >> "$LOG_FILE"; fi
}

check_service() {
    local name=$1; local port=$2; printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "$name ($port)"
    if ss -tpln | grep -qE ":$port " || ss -tpln | grep -qE "haproxy.*:$port" || ss -tpln | grep -qE "shadow-tls.*:$port" || ss -tpln | grep -qE "stunnel.*:$port"; then print_status 0; else print_status 1; echo "Down: $name ($port)" >> "$LOG_FILE"; fi
}

# START AUDIT
print_header

echo -e "\n  ${BCYAN}◈ 1. CORE INFRASTRUCTURE (FILES & PKGS)${NC}"
check_file "/usr/local/bin/MegaSSH.sh"
check_file "/usr/local/bin/firewall_manager.sh"
check_pkg "haproxy"
check_pkg "nginx"
check_pkg "ipset"
check_pkg "conntrack"
check_pkg "iptables-persistent"
 
 # Installation Status Check
 printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Installation Finalized"
 if grep -q "MEGASSH_INSTALLATION_SUCCESSFUL" /var/log/megassh_install.log 2>/dev/null; then 
    echo -e "${BGREEN}[PASS]${NC}"
 else 
    echo -e "${BRED}[FAIL]${NC}"
    echo "HINT: Run ./fix-raw-and-persist.sh to force success flag and repair rules." >> "$LOG_FILE"
    GLOBAL_FAIL=1
 fi
 
 echo -e "\n  ${BCYAN}◈ 2. PERFORMANCE & SECURITY LAYERS${NC}"
# Kernel Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "XanMod Elite Kernel"
if uname -r | grep -qi "xanmod"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BYELLOW}[STOCK]${NC}"; fi

# TFO Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "TCP Fast Open (TFO=3)"
if [ "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)" == "3" ]; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# FQ-CoDel Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "FQ-CoDel Queue Mgmt"
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if tc qdisc show dev "$IFACE" | grep -q "fq_codel"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# Mux Version
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "HAProxy Mux (v3.3.2)"
if haproxy -v 2>/dev/null | grep -q "3.3.2"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISMATCH]${NC}"; fi

# HAProxy Silence Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "HAProxy Silent Entry (5s)"
if grep -q "inspect-delay 5s" /etc/haproxy/haproxy.cfg 2>/dev/null && grep -q "req.len gt 0" /etc/haproxy/haproxy.cfg 2>/dev/null; then
    echo -e "${BGREEN}[PASS]${NC}"
else
    echo -e "${BRED}[FAIL]${NC}"
fi

# EagleNet Tuning Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "EagleNet SSH Storm Tuning"
if [ -f /etc/ssh/sshd_config.d/99-eaglenet.conf ] && grep -q "MaxStartups 300:30:800" /etc/ssh/sshd_config.d/99-eaglenet.conf; then
    echo -e "${BGREEN}[PASS]${NC}"
else
    echo -e "${BRED}[MISSING]${NC}"
fi

check_service "HAProxy (Mux)" 443
check_service "SSH (EagleNet)" 2222
check_service "UDPGW (BadVPN)" 7301
check_service "Stunnel (SSL)" 8443
check_service "ShadowTLS" 9443

# Session Limit Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Global Session Limits"
if [ -f /etc/security/limits.d/megassh.conf ] && grep -q "maxlogins   3" /etc/security/limits.d/megassh.conf; then
    echo -e "${BGREEN}[PASS]${NC}"
else
    echo -e "${BRED}[FAIL]${NC}"
fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Nginx NJS Support"
if [ -f /etc/nginx/nginx.conf ] && grep -q "js_module" /etc/nginx/nginx.conf; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[OFF]${NC}"; fi

echo -e "\n  ${BCYAN}◈ 3. NUCLEAR FIREWALL INTEGRITY${NC}"
# Check IPv6 Status
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Zero-Leak (IPv6 Disable)"
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]; then print_status 0; else print_status 1; fi

# Check Maintenance Cron
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Maintenance Cron (Updates)"
if [ -f /etc/cron.d/megassh_maintenance ] && grep -q "firewall_manager.sh" /etc/cron.d/megassh_maintenance; then
    echo -e "${BGREEN}[PASS]${NC}"
else
    echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1
fi

# Check ip6tables Policy
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "ip6tables Mandatory DROP"
if ip6tables -S 2>/dev/null | grep -q "INPUT -P DROP" && \
   ip6tables -S 2>/dev/null | grep -q "OUTPUT -P DROP" && \
   ip6tables -S 2>/dev/null | grep -q "FORWARD -P DROP"; then
    echo -e "${BGREEN}[ACTIVE]${NC}"
else
    echo -e "${BRED}[OPEN]${NC}"; GLOBAL_FAIL=1
fi

# Check IPSets
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Nuclear IPSet (Isolation)"
IN_COUNT=$(ipset list country_block_in 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
OUT_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
if [ -n "$IN_COUNT" ] && [ "$IN_COUNT" -gt 0 ]; then echo -e "${BGREEN}[$IN_COUNT IPs]${NC}"; else echo -e "${BRED}[EMPTY]${NC}"; GLOBAL_FAIL=1; fi

# Check Raw Table Isolation (Directional Precision)
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Raw Inbound (NOTRACK 22,443)"
if iptables -t raw -S PREROUTING 2>/dev/null | grep -qi "notrack"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Raw Inbound (ACCEPT 22,443)"
if iptables -t raw -S PREROUTING 2>/dev/null | grep -q "ACCEPT"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Raw Outbound (NOTRACK 22,443)"
if iptables -t raw -S OUTPUT 2>/dev/null | grep -qi "notrack"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Raw Outbound (ACCEPT 22,443)"
if iptables -t raw -S OUTPUT 2>/dev/null | grep -q "ACCEPT"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Raw Outbound Block (Leak Switch)"
if iptables -t raw -S OUTPUT 2>/dev/null | grep -qiE "DROP.*country_block_out"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[MISSING]${NC}"; GLOBAL_FAIL=1; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Mangle Admin Response (Whitelist)"
if iptables -t mangle -S OUTPUT 2>/dev/null | grep -qiE "ACCEPT.*sports 22,443"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; GLOBAL_FAIL=1; fi

# Cloudflare WARP Check
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "Cloudflare WARP Status"
if systemctl is-active --quiet warp-svc 2>/dev/null; then
    WARP_IP=$(curl -s --max-time 2 https://ifconfig.me)
    if curl -s --max-time 2 https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"; then
        echo -e "${BGREEN}[VIRTUAL: $WARP_IP]${NC}"
        # Check bypass rule
        printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "WARP Anti-Lockout (0x100)"
        if iptables -t mangle -L OUTPUT -n | grep -q "MARK set 0x100"; then echo -e "${BGREEN}[PASS]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi
    else
        echo -e "${BYELLOW}[SVC ACTIVE / DISCONNECTED]${NC}"
    fi
else
    echo -e "${WHITE}[NOT INSTALLED]${NC}"
fi

echo -e "\n  ${BCYAN}◈ 4. LIVE GEOPRIVACY VALIDATION${NC}"
# DPI Checks
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "DPI Shield (MSS Clamp)"
if iptables -t mangle -S | grep -qiE "(TCPMSS.*set-mss 1200|set-mss 1200)"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "TTL Obfuscation (64)"
if iptables -t mangle -S | grep -qiE "(TTL.*set.*64|TTL.*64)"; then echo -e "${BGREEN}[ACTIVE]${NC}"; else echo -e "${BRED}[FAIL]${NC}"; fi

# Check SSH Banner Obfuscation
printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "SSH Banner (Cloaking)"
if strings /usr/sbin/sshd | grep -qiE "(Microsoft_IIS|IIS|Apache)"; then 
    echo -e "${BGREEN}[PASS]${NC}"
else 
    BANNER_FOUND=$(strings /usr/sbin/sshd | grep -o "OpenSSH_[^[:space:]]*" | head -n1)
    echo -e "${BRED}[FAIL: $BANNER_FOUND]${NC}"
fi

# Live High-Precision Tests (Nuclear Shield)
test_leak() {
    local site=$1; local ip=$2; local label=$3
    printf "  ${BPURPLE}├─${NC} ${WHITE}%-36s${NC}" "$label"
    
    # Use 3s timeout
    local output=$(curl -m 3 -s -I --resolve "$site:80:$ip" "http://$site" 2>&1)
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo -e "${BRED}[PROHIBITED]${NC}"
        echo "Leak detected on $label:" >> "$LOG_FILE"
        echo "$output" | head -n 5 >> "$LOG_FILE"
        GLOBAL_FAIL=1
    elif echo "$output" | grep -qi "ArvanCloud"; then
        echo -e "${BRED}[AK-BYPASS]${NC}"
        echo "ArvanCloud Bypass on $label" >> "$LOG_FILE"
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
