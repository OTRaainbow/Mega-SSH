#!/bin/bash

# ==============================================================================
# Nuclear Firewall 5.0 (FINAL SYNC)
# Highest possible priority (Priority 2) to override all tunnel drivers.
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

echo -e "${BBLUE}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BBLUE}║${NC} ${BRED}        NUCLEAR FIREWALL 5.0 - ABSOLUTE PRIORITY PROTECTION           ${BBLUE}║${NC}"
echo -e "${BBLUE}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"

# 1. Setup IPSets
print_step "1/7" "Initializing IPSets..."
ipset create country_block_in hash:net maxelem 1000000 -exist
ipset create country_block_out hash:net maxelem 1000000 -exist

# Temporary sets for atomic aggregation
ipset create tmp_block_in hash:net maxelem 1000000 -exist
ipset create tmp_block_out hash:net maxelem 1000000 -exist
ipset flush tmp_block_in
ipset flush tmp_block_out

# 1.5 Manual Blocklist (High-Priority Leaks)
print_info "Adding manual blocks for known CDNs (ArvanCloud)..."
# isna.ir and related ArvanCloud ranges
ipset add tmp_block_out 94.182.182.0/24 -exist 2>/dev/null
ipset add tmp_block_out 185.143.232.0/22 -exist 2>/dev/null
ipset add tmp_block_out 185.143.235.0/24 -exist 2>/dev/null
ipset add tmp_block_out 2.188.0.0/16 -exist 2>/dev/null # Iran wide block backup

load_to_tmp() {
    local cc=$1; local file=$2; local target_tmp=$3
    if [ ! -s "$file" ]; then print_warn "Warning: $file is empty or missing!"; return 1; fi
    if head -n 5 "$file" | grep -q "<!DOCTYPE html>"; then print_error "Error: $file is HTML!"; return 1; fi

    print_info "Loading $cc data into $target_tmp..."
    (
        grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_tmp" 'NF {print "add " set " " $1}'
    ) | ipset restore -exist 2>/dev/null
}

# 2. NUCLEAR FLUSH & IPv6 KILL
print_step "2/7" "Nuclear Flush & IPv6 Killer (Zero-Leak Enforcement)..."

# A. Disable IPv6 via Sysctl
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1

# B. Hard-block IPv6 via ip6tables
if command -v ip6tables >/dev/null; then
    ip6tables -P INPUT DROP
    ip6tables -P OUTPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -F
    ip6tables -X
fi

# C. Flush IPv4 Tables
if command -v ufw >/dev/null; then ufw disable >/dev/null 2>&1; fi
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# --- Aggregate Country Blocks ---
print_step "2.1" "Aggregating Geofence Data..."
# Block RU and CN (Both Inbound and Outbound)
RULES_DIR="/etc/megassh/rules"
for cc in ru cn; do
    # Try all possible path combinations
    FILE="${RULES_DIR}/${cc}.netset"
    [ ! -f "$FILE" ] && FILE="/root/ip2location_country_${cc}.netset"
    [ ! -f "$FILE" ] && FILE="ip2location_country_${cc}.netset"
    
    load_to_tmp "$cc" "$FILE" "tmp_block_in"
    load_to_tmp "$cc" "$FILE" "tmp_block_out"
done

# Block Iran (IR) - OUTBOUND ONLY
FILE_IR="${RULES_DIR}/ir.netset"
[ ! -f "$FILE_IR" ] && FILE_IR="/root/ip2location_country_ir.netset"
[ ! -f "$FILE_IR" ] && FILE_IR="ip2location_country_ir.netset"
load_to_tmp "ir" "$FILE_IR" "tmp_block_out"

# Atomic Swap
print_info "Finalizing Nuclear Shield (Atomic Swap)..."
IN_SIZE=$(ipset list tmp_block_in | grep 'Number of entries' | awk '{print $4}')
OUT_SIZE=$(ipset list tmp_block_out | grep 'Number of entries' | awk '{print $4}')

if [ "$IN_SIZE" -gt 0 ]; then ipset swap tmp_block_in country_block_in; fi
if [ "$OUT_SIZE" -gt 0 ]; then ipset swap tmp_block_out country_block_out; fi

ipset destroy tmp_block_in 2>/dev/null
ipset destroy tmp_block_out 2>/dev/null

IN_COUNT=$(ipset list country_block_in | grep 'Number of entries' | awk '{print $4}')
OUT_COUNT=$(ipset list country_block_out | grep 'Number of entries' | awk '{print $4}')
print_success "Shield Active: $IN_COUNT Inbound / $OUT_COUNT Outbound IPs blocked."

# 2.5 LOAD CUSTOM USER RULES
if [ -f "user.rules" ]; then
    print_step "2.5" "Loading custom user.rules..."
    for chain in ufw-user-input ufw-user-output ufw-user-forward ufw-before-logging-input ufw-before-logging-output ufw-before-logging-forward ufw-user-logging-input ufw-user-logging-output ufw-user-logging-forward ufw-after-logging-input ufw-after-logging-output ufw-after-logging-forward ufw-logging-deny ufw-logging-allow ufw-user-limit ufw-user-limit-accept; do
        iptables -N $chain 2>/dev/null
    done

    iptables -I INPUT 1 -j ufw-user-input
    iptables -I OUTPUT 1 -j ufw-user-output
    iptables -I FORWARD 1 -j ufw-user-forward

    grep '^-A' user.rules | while read -r rule; do
        iptables $rule 2>/dev/null
    done
    print_success "user.rules loaded into iptables."
else
    print_warn "user.rules not found, skipping."
fi

# 3. ABSOLUTE PRIORITY POLICY ROUTING (Priority 2)
print_step "3/7" "Applying Priority 2 Blackhole..."
ip route flush table 200 2>/dev/null
ip route add blackhole default table 200 2>/dev/null

while ip rule show | grep -q "fwmark 0x99"; do
    ip rule del fwmark 0x99 2>/dev/null
done

ip rule add fwmark 0x99 table 200 priority 2

# ==============================================================================
# NUCLEAR ENFORCEMENT - RAW TABLE (L3/L4 PRE-CONNTRACK)
# ==============================================================================
print_step "4/7" "Applying RAW Table Blocking (Directional Precision)..."

# 1. Clear Raw Table (Ignore errors if table is empty)
iptables -t raw -F 2>/dev/null
iptables -t raw -X 2>/dev/null

# 2. ALLOW INBOUND (Admin Connect)
iptables -t raw -A PREROUTING -p tcp -m multiport --dports 22,2222,443 -j ACCEPT

# 3. ALLOW OUTBOUND RESPONSE (Admin Reply)
iptables -t raw -A OUTPUT -p tcp -m multiport --sports 22,2222,443 -j ACCEPT

# 4. BLOCK OUTBOUND (Leak Prevention)
# Check if ipset exists and has entries before applying to avoid match error
if ipset list country_block_out >/dev/null 2>&1; then
    iptables -t raw -A OUTPUT -m set --match-set country_block_out dst -j DROP
fi

# 5. BLOCK INBOUND (General Security)
if ipset list country_block_in >/dev/null 2>&1; then
    iptables -t raw -A PREROUTING -m set --match-set country_block_in src -j DROP
fi

# 5. DNS HIJACK PREVENTION & BLACKHOLE ROUTING
# Clear old mangle rules
iptables -t mangle -F

# A. ONLY allow response traffic for YOUR connection (prevents lockout)
# This prevents Replies from being marked for the blackhole.
iptables -t mangle -A OUTPUT -p tcp -m multiport --sports 22,443 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# B. MARK all other outbound traffic to blocked countries
# This forces the packet into the 'Table 200' Blackhole.
iptables -t mangle -A OUTPUT -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -A PREROUTING -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 6. BASE CONNECTIVITY & SECURITY
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Stealth Reset for INVALID packets (DPI Evasion)
iptables -A INPUT -p tcp -m conntrack --ctstate INVALID -j REJECT --reject-with tcp-reset
iptables -A INPUT -p udp -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# MSS Clamping & TTL Obfuscation (DPI Evasion)
# Apply to both OUTPUT (local) and POSTROUTING (forwarded/local)
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 64
iptables -t mangle -A OUTPUT -j TTL --ttl-set 64

# Open ONLY Ports 22 and 443
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# ICMP Wrapper (Pinging allowed but restricted)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT

iptables -P INPUT DROP

# 6.5 Flush State & Route Cache (CRITICAL - No Ghost Connections)
print_step "6.5" "Cleaning Connection States & Route Cache..."
command -v conntrack >/dev/null && conntrack -F
ip route flush cache

# 7. Persistence
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
ipset save > /etc/iptables/ipsets.save 2>/dev/null

if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save > /dev/null 2>&1
fi

print_info "Policy Rule Pri 2: $(ip rule show | grep 0x99)"
print_success "NUCLEAR FIREWALL 5.1 ACTIVE (BIDIRECTIONAL BLACKOUT)."

