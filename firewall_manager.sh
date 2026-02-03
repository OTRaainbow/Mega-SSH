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

load_set_nuclear() {
    local cc=$1; local file=$2; local target_set=$3
    if [ ! -s "$file" ]; then print_error "Error: $file is empty!"; return 1; fi
    if head -n 5 "$file" | grep -q "<!DOCTYPE html>"; then print_error "Error: $file is HTML!"; return 1; fi

    local tmp_set="tmp_${target_set}_${cc}"
    print_info "Injecting $cc data into $target_set (atomic)..."
    
    # Create temporary set for atomic swap
    ipset create "$tmp_set" hash:net maxelem 1000000 -exist
    ipset flush "$tmp_set"

    (
        grep -v '^#' "$file" | tr -d '\r' | awk -v set="$tmp_set" 'NF {print "add " set " " $1}'
    ) | ipset restore -exist 2>/dev/null
    
    # Swap and clean up
    ipset swap "$tmp_set" "$target_set" 2>/dev/null
    ipset destroy "$tmp_set" 2>/dev/null
    
    local count=$(ipset list "$target_set" | grep 'Number of entries' | awk '{print $4}')
    print_success "($count entries)"
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

# 1. Block RU and CN (Both Inbound and Outbound) - "Nuclear Isolation"
for cc in ru cn; do
    FILE="ip2location_country_${cc}.netset"
    # Redundancy check in multiple possible locations
    [ ! -f "$FILE" ] && FILE="/etc/megassh/rules/${cc}.netset"
    
    load_set_nuclear "$cc" "$FILE" "country_block_in"
    load_set_nuclear "$cc" "$FILE" "country_block_out"
done

# 2. Block Iran (IR) - OUTBOUND ONLY
FILE_IR="ip2location_country_ir.netset"
[ ! -f "$FILE_IR" ] && FILE_IR="/etc/megassh/rules/ir.netset"
load_set_nuclear "ir" "$FILE_IR" "country_block_out"

# 2.5 LOAD CUSTOM USER RULES (ufw-user-*)
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

# 4. NUCLEAR ENFORCEMENT - RAW TABLE (L3/L4 PRE-CONNTRACK)
print_step "4/7" "Applying RAW Table Blocking (Pre-State Enforcement)..."

# Flush raw table to ensure a clean state
iptables -t raw -F

# 1. IMMEDIATE DROP for OUTBOUND to CN, RU, and IR
# This kills the packet before the kernel cycles through the Filter table.
iptables -t raw -A OUTPUT -m set --match-set country_block_out dst -j DROP

# 2. IMMEDIATE DROP for INBOUND from CN and RU
iptables -t raw -A PREROUTING -m set --match-set country_block_in src -j DROP

# 3. FORWARDING Protection (For tunnel/proxy users)
iptables -t raw -A PREROUTING -m set --match-set country_block_out dst -j DROP

# 5. DNS HIJACK PREVENTION (Force stay within allowed zones)
# We handle this in mangle for marking, or in raw for immediate drop if problematic.
# MARK still happens in mangle to feed the Table 200 blackhole.
iptables -t mangle -I PREROUTING 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -I OUTPUT 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 6. BASE CONNECTIVITY & SECURITY
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Stealth Reset for INVALID packets (DPI Evasion)
iptables -A INPUT -p tcp -m conntrack --ctstate INVALID -j REJECT --reject-with tcp-reset
iptables -A INPUT -p udp -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# MSS Clamping & TTL Obfuscation (DPI Evasion)
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 64

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
if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save > /dev/null 2>&1
fi

print_info "Policy Rule Pri 2: $(ip rule show | grep 0x99)"
print_success "NUCLEAR FIREWALL 5.1 ACTIVE (BIDIRECTIONAL BLACKOUT)."

