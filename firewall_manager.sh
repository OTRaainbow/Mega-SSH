#!/bin/bash

# ==============================================================================
# Nuclear Firewall 4.0 (Final Inescapable Version)
# Bypasses tunnel encapsulation by blocking at the routing layer with Priority 5.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}    NUCLEAR FIREWALL 4.0 - HIGH PRIORITY         ${NC}"
echo -e "${CYAN}=================================================${NC}"

# 1. Setup IPSets (The Database)
echo -e "${YELLOW}[~] Initializing IPSets...${NC}"
ipset create country_block_in hash:net maxelem 524288 -exist
ipset create country_block_out hash:net maxelem 524288 -exist
ipset flush country_block_in
ipset flush country_block_out

load_set_nuclear() {
    local cc=$1; local file=$2; local target_set=$3
    if [ ! -s "$file" ]; then
        echo -e "${RED}[✘] Error: $file is empty or missing!${NC}"
        return 1
    fi
    
    # Check if it's an HTML page (GitHub error)
    if head -n 5 "$file" | grep -q "<!DOCTYPE html>"; then
        echo -e "${RED}[✘] Error: $file is HTML! Download failed (URL Error)${NC}"
        return 1
    fi

    echo -n -e "${YELLOW}[~] Injecting $cc data into $target_set...${NC}"
    
    # Bulk Load with 'ipset restore'
    (
        echo "flush $target_set"
        grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
    ) | ipset restore -exist 2>/dev/null
    
    # Verification
    local count=$(ipset list "$target_set" | grep 'Number of entries' | awk '{print $4}')
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        echo -e " ${GREEN}[OK] ($count entries)${NC}"
    else
        echo -e " ${RED}[FAILED] Fallback to manual load...${NC}"
        # Fallback to slow but guaranteed loop
        while read -r ip; do
            [[ "$ip" =~ ^#.* ]] || [[ -z "$ip" ]] && continue
            ipset add "$target_set" "$ip" -exist 2>/dev/null
        done < "$file"
        count=$(ipset list "$target_set" | grep 'Number of entries' | awk '{print $4}')
        echo -e "${GREEN}[✔] Loaded $count entries via fallback.${NC}"
    fi
}

# Auto-Load
for cc in ir ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ "$cc" == "ir" ]; then
        load_set_nuclear "Iran" "$FILE" "country_block_out"
    else
        load_set_nuclear "$cc" "$FILE" "country_block_in"
        # Mirror RU/CN to outbound block as well
        if [ -s "$FILE" ]; then
            (
                grep -v '^#' "$FILE" | tr -d '\r' | awk 'NF {print "add country_block_out " $1}'
            ) | ipset restore -exist 2>/dev/null
        fi
    fi
done

# 2. CLEAR PREVIOUS RULES
echo -e "${YELLOW}[~] Flushing existing rules...${NC}"
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# 3. HIGH-PRIORITY POLICY ROUTING (THE "NUCLEAR KILL-SWITCH")
echo -e "${YELLOW}[~] Configuring Ultra-High Priority Routing (Priority 5)...${NC}"
# Table 200 is our "Unreachable" zone
ip route flush table 200 2>/dev/null
ip route add blackhole default table 200 2>/dev/null

# Priority 5 overrides almost all VPN/Tunnel drivers (including some WARP configs)
ip rule del fwmark 0x99 2>/dev/null
ip rule add fwmark 0x99 table 200 priority 5

# 4. MULTILAYER ENFORCEMENT
# A. MANGLE: Mark all packets for blocked IPs at the earliest possible stage
# This happens BEFORE the routing table is decided.
for chain in PREROUTING INPUT FORWARD OUTPUT POSTROUTING; do
    iptables -t mangle -A $chain -m set --match-set country_block_out dst -j MARK --set-mark 0x99
done

# B. RAW: Drop incoming traffic from RU/CN (Source block)
iptables -t raw -A PREROUTING -m set --match-set country_block_in src -j DROP

# C. FILTER: Strict Rejection for VPN Clients
# We use REJECT with icmp-admin-prohibited so the browser stops spinning immediately.
iptables -A FORWARD -m set --match-set country_block_out dst -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -m set --match-set country_block_out dst -j REJECT --reject-with icmp-admin-prohibited

# 5. DNS BLACKHOLE
# If a DNS query is going to a blocked range, kill it.
iptables -t mangle -I OUTPUT 1 -p udp --dport 53 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -I OUTPUT 1 -p tcp --dport 53 -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 6. BASE SECURITY (Whitelist)
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
if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save > /dev/null 2>&1
fi

echo -e "${GREEN}[✔] NUCLEAR FIREWALL 4.0 ACTIVE.${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Total IPSet Entries: $(ipset list | grep 'Number of entries' | awk '{sum+=$4} END {print sum}')"
echo -e "Policy Rule Priority 5: $(ip rule show | grep 0x99)"
echo -e "Routing Table 200:      $(ip route show table 200)"
echo -e "${CYAN}--------------------------------------------------${NC}"
