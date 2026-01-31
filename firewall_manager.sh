#!/bin/bash

# ==============================================================================
# Total Shutdown Firewall (Final Solution)
# Blocks IR/RU/CN at EVERY layer of the network stack.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[+] Starting Total Shutdown Firewall...${NC}"

# 1. Nuke IPv6 (Global)
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

ip6tables -F
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# 2. Setup High-Capacity IPSets
ipset create country_block_in hash:net maxelem 524288 -exist
ipset create country_block_out hash:net maxelem 524288 -exist
ipset flush country_block_in
ipset flush country_block_out

load_set() {
    local country=$1; local file=$2; local target_set=$3
    if [ -f "$file" ]; then
        echo -e "${YELLOW}[~] Loading $file into $target_set...${NC}"
        (
            echo "create $target_set hash:net maxelem 524288 -exist"
            grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
        ) | ipset restore -exist
    fi
}

# Auto-Download & Load
for cc in ir ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ -f "$FILE" ]; then
        if [ "$cc" == "ir" ]; then
            load_set "Iran" "$FILE" "country_block_out"
        else
            load_set "$cc" "$FILE" "country_block_in"
            # Add RU/CN to both
            grep -v '^#' "$FILE" | tr -d '\r' | awk 'NF {print "add country_block_out " $1}' | ipset restore -exist
        fi
    fi
done

# 3. APPLY RULES (NUCLEAR MODE)
# We apply in MANGLE, RAW, and FILTER to ensure NO bypass via WARP/Routing

# Clear All Tables
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# --- MANGLE TABLE (Before/After Routing) ---
# Catch everything before it leaves the network card
iptables -t mangle -I PREROUTING 1 -m set --match-set country_block_in src -j DROP
iptables -t mangle -I POSTROUTING 1 -m set --match-set country_block_out dst -j DROP

# --- RAW TABLE (Fast Drop) ---
iptables -t raw -I PREROUTING 1 -m set --match-set country_block_in src -j DROP
iptables -t raw -I OUTPUT 1 -m set --match-set country_block_out dst -j DROP

# --- FILTER TABLE (Deep Drop) ---
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Inbound
iptables -I INPUT 1 -i lo -j ACCEPT
iptables -I INPUT 2 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -I INPUT 3 -m set --match-set country_block_in src -j DROP

# Outbound (STATELESS - Block Everything)
iptables -I FORWARD 1 -m set --match-set country_block_out dst -j DROP
iptables -I OUTPUT 1 -m set --match-set country_block_out dst -j DROP

# DNS Hardening
iptables -I OUTPUT 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP
iptables -I OUTPUT 1 -p tcp --dport 53 -m set --match-set country_block_out dst -j DROP
iptables -I FORWARD 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP

# 4. Base Access (UFW-style in iptables to be safe)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 9443 -j ACCEPT
iptables -A INPUT -p udp --dport 7301 -j ACCEPT

# 5. Persistence
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}[✔] TOTAL SHUTDOWN ACTIVE.${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Entries in Blocklist: $(ipset list | grep 'Number of entries' | awk '{sum+=$4} END {print sum}')"
echo -e "${CYAN}--------------------------------------------------${NC}"
