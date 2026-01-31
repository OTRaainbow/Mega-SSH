#!/bin/bash

# ==============================================================================
# Zero-Leak Firewall (Policy Routing & Blackhole Mode)
# Bypasses tunnel encapsulation by blocking at the routing layer.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[+] Starting Zero-Leak Firewall Harden...${NC}"

# 1. Setup IPSets (The Database)
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
            grep -v '^#' "$FILE" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
        ) | ipset restore -exist
    fi
}

# Auto-Download & Load (.netset files must be in /root/)
for cc in ir ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ -f "$FILE" ]; then
        load_set "$cc" "$FILE" "country_block_out"
        if [ "$cc" != "ir" ]; then
            load_set "$cc" "$FILE" "country_block_in"
        fi
    fi
done

# 2. CLEAR PREVIOUS AGGRESSIVE RULES
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# 3. IMPLEMENT ZERO-LEAK ROUTING (THE "HAMMER")
echo -e "${YELLOW}[~] Configuring Policy Routing Blackhole...${NC}"

# A. Create a Blackhole Routing Table (Table 100)
# This table says "Destination Prohibited" to anything in it.
ip route flush table 100 2>/dev/null
ip route add unreachable default table 100

# B. Add Policy Rule
# Any packet marked with 0x99 MUST use Table 100 (and thus be prohibited)
ip rule del fwmark 0x99 2>/dev/null
ip rule add fwmark 0x99 table 100 priority 100

# C. Mark the Packets (Mangle Table)
# We mark in PREROUTING (for clients) and OUTPUT (for server apps)
# This happens BEFORE WARP/NPV can encapsulate the packet.
iptables -t mangle -I PREROUTING 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -I OUTPUT 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 4. TRADITIONAL FILTER DROPS (BACKUP LAYER)
iptables -I FORWARD 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-port-unreachable
iptables -I OUTPUT 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-port-unreachable
iptables -t raw -I PREROUTING 1 -m set --match-set country_block_in src -j DROP

# 5. DNS HIJACK PREVENTION
# Block DNS lookups if the target IP is in the blocklist
iptables -I OUTPUT 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP
iptables -I FORWARD 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP

# 6. Base Interface Safety
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 9443 -j ACCEPT
iptables -A INPUT -p udp --dport 7301 -j ACCEPT
iptables -P INPUT DROP

# 7. Persistence
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}[✔] ZERO-LEAK POLICY ROUTING ACTIVE.${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Total IPSet Entries: $(ipset list | grep 'Number of entries' | awk '{sum+=$4} END {print sum}')"
echo -e "Policy Rule: $(ip rule show | grep 0x99)"
echo -e "Table 100:   $(ip route show table 100)"
echo -e "${CYAN}--------------------------------------------------${NC}"
