#!/bin/bash

# ==============================================================================
# MegaSSH System Audit & Health Check (v6.0 - Ironclad)
# Features: Strict File/Package Checks, Extended Geo-Blocking Tests
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

LOG_FILE="/var/log/megassh_audit.log"
echo "Audit started at $(date)" > "$LOG_FILE"

print_header() {
    clear
    echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BBLUE}║${NC} ${BCYAN}                   MEGASSH SYSTEM AUDIT (CHECK LOG)                          ${BBLUE}║${NC}"
    echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
    date
}

print_status() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAILED]${NC}"
        # We assume critical failures should be noted, but maybe not exit immediately 
        # to allow seeing all failures. However, user asked for "no success message" if these fail.
        GLOBAL_FAIL=1
    fi
}

GLOBAL_FAIL=0

print_header

# --- 1. Strict File Integrity Check ---
echo -e "\n${BYELLOW}--- 1. Critical File Integrity ---${NC}"
check_file() {
    local file=$1
    printf "%-40s" "[~] Checking $file..."
    if [ -f "$file" ]; then
        print_status 0
    else
        print_status 1
        echo "Missing File: $file" >> "$LOG_FILE"
    fi
}

# Core Scripts (assumed path relative to install or in /root/ if not specified, 
# but usually these are in the current dir during install. We'll check current dir.)
check_file "MegaSSH.sh"
check_file "high_perf_optimizer.sh"
check_file "firewall_manager.sh"
check_file "strict_block.sh"
check_file "MegaSSH-WARP.sh"
check_file "useradd.py"
check_file "UDPGW.sh"
# Helper managers often fetched
check_file "stunnel_manager.sh"
check_file "shadowtls_manager.sh"

# --- 2. Package & Dependency Check ---
echo -e "\n${BYELLOW}--- 2. Package Installation Status ---${NC}"
check_pkg() {
    local pkg=$1
    printf "%-40s" "[~] Checking Package: $pkg..."
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        print_status 0
    else
        print_status 1
        echo "Missing Package: $pkg" >> "$LOG_FILE"
    fi
}

check_pkg "nginx"
check_pkg "haproxy"
check_pkg "iptables-persistent"
check_pkg "ipset"
check_pkg "socat"
check_pkg "curl"
check_pkg "python3"
check_pkg "irqbalance"
# check_pkg "linux-xanmod-x64v3" # Can't strict check pkg name easily if version changes, skip for now or check uname

# --- 3. Component Service Checks ---
echo -e "\n${BYELLOW}--- 3. Service Status & Ports ---${NC}"
check_service() {
    local name=$1
    local port=$2
    printf "%-40s" "[~] Checking $name ($port)..."
    if ss -tpln | grep -q ":$port "; then
        print_status 0
    else
        print_status 1
        echo "Service Down: $name ($port)" >> "$LOG_FILE"
    fi
}

check_service "Nginx (Decoy)" 80
check_service "HAProxy (Multiplexer)" 443
check_service "SSH (Internal)" 2222
check_service "Stunnel (SSL)" 8443
check_service "ShadowTLS" 9443
check_service "UDPGW" 7301
check_service "Rescue SSH" 22

# --- 4. Firewall & Geo-Block Integrity ---
echo -e "\n${BYELLOW}--- 4. Firewall Integrity ---${NC}"

# Check IPSet
IR_COUNT=$(ipset list country_block_out 2>/dev/null | grep 'Number of entries' | awk '{print $4}')
RU_CN_COUNT=$(ipset list country_block_in 2>/dev/null | grep 'Number of entries' | awk '{print $4}')

printf "%-40s" "[~] IPSet (Outbound Block)..."
if [ -n "$IR_COUNT" ] && [ "$IR_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[OK] ($IR_COUNT IPs)${NC}"
else
    echo -e "${RED}[FAILED/EMPTY]${NC}"
    GLOBAL_FAIL=1
fi

printf "%-40s" "[~] IPSet (Inbound Block)..."
if [ -n "$RU_CN_COUNT" ] && [ "$RU_CN_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[OK] ($RU_CN_COUNT IPs)${NC}"
else
    echo -e "${RED}[FAILED/EMPTY]${NC}"
    GLOBAL_FAIL=1
fi

# Check Strict Block IPTables Rules
printf "%-40s" "[~] Strict DROP Rules (OUTPUT)..."
if iptables -L OUTPUT -n | grep -q "DROP.*country_block_out"; then
    echo -e "${GREEN}[ACTIVE]${NC}"
else
    echo -e "${RED}[MISSING]${NC}"
    GLOBAL_FAIL=1
fi

# Check IPv6
printf "%-40s" "[~] IPv6 Status..."
IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
if [ "$IPV6_STATUS" == "1" ]; then
    echo -e "${GREEN}[DISABLED]${NC}"
else
    echo -e "${RED}[LEAKING]${NC}"
    GLOBAL_FAIL=1
fi

# --- 5. Extended Live Geo-Blocking Tests ---
echo -e "\n${BYELLOW}--- 5. Extended Geo-Blocking Test (Ping/Curl) ---${NC}"
echo -e "${BCYAN}Testing strict outbound blocking (Should FAIL to connect)${NC}"

test_block() {
    local site=$1
    local name=$2
    printf "%-40s" "[~] Testing $name ($site)..."
    
    # Timeout 3s. Expect FAILURE.
    curl -m 3 -s -I "http://$site" > /dev/null 2>&1
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo -e "${RED}[FAILED - CONNECTED]${NC}"
        GLOBAL_FAIL=1
        echo "GeoBlock Failed: $site was accessible" >> "$LOG_FILE"
    else
        echo -e "${GREEN}[BLOCKED] (Success)${NC}"
    fi
}

test_open() {
    local site=$1
    local name=$2
    printf "%-40s" "[~] Testing $name ($site)..."
    
    # Timeout 3s. Expect SUCCESS.
    curl -m 3 -s -I "http://$site" > /dev/null 2>&1
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo -e "${GREEN}[OPEN] (Success)${NC}"
    else
        echo -e "${RED}[FAILED - BLOCKED] (Code: $ret)${NC}"
        GLOBAL_FAIL=1
        echo "Access Failed: $site was unreachable" >> "$LOG_FILE"
    fi
}

echo -e "\n${BBLUE}>> Verify BLOCKED Sites (RU/CN)${NC}"
echo -e "${BCYAN}Target: Russia (Should be BLOCKED)${NC}"
test_block "vk.com" "VKontakte"
test_block "mail.ru" "Mail.ru"
test_block "yandex.ru" "Yandex"
test_block "ok.ru" "Odnoklassniki"
test_block "gosuslugi.ru" "Gosuslugi"

echo -e "\n${BCYAN}Target: China (Should be BLOCKED)${NC}"
test_block "baidu.com" "Baidu"
test_block "qq.com" "QQ"
test_block "taobao.com" "Taobao"
test_block "weibo.com" "Weibo"
test_block "360.cn" "360 Security"

echo -e "\n${BBLUE}>> Verify OPEN Sites (Iran)${NC}"
echo -e "${BCYAN}Target: Iran (Should be OPEN)${NC}"
test_open "digikala.com" "Digikala"
test_open "varzesh3.com" "Varzesh3"
test_open "aparat.com" "Aparat"
test_open "shaparak.ir" "Shaparak"
test_open "divar.ir" "Divar"

# --- 6. Final Verdict ---
echo -e "\n${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$GLOBAL_FAIL" -eq 1 ]; then
    echo -e "${BBLUE}║${NC} ${BRED}          AUDIT FAILED - CRITICAL ISSUES DETECTED                            ${BBLUE}║${NC}"
    echo -e "${BBLUE}║${NC} ${BRED}          Check $LOG_FILE for details.                                       ${BBLUE}║${NC}"
    echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
    exit 1
else
    echo -e "${BBLUE}║${NC} ${BGREEN}          ALL SYSTEMS GREEN - INSTALLATION VERIFIED                          ${BBLUE}║${NC}"
    echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
    exit 0
fi
