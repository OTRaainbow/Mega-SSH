#!/bin/bash

# ==============================================================================
# Nuclear Firewall 4.5 (High Priority Fix)
# Bypasses tunnel encapsulation by blocking at the routing layer with Priority 2.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}    NUCLEAR FIREWALL 4.5 - HIGHEST PRIORITY      ${NC}"
echo -e "${CYAN}=================================================${NC}"

# 1. Setup IPSets
echo -e "${YELLOW}[~] Initializing IPSets...${NC}"
ipset create country_block_in hash:net maxelem 524288 -exist
ipset create country_block_out hash:net maxelem 524288 -exist
ipset flush country_block_in
ipset flush country_block_out

load_set_nuclear() {
    local cc=$1; local file=$2; local target_set=$3
    if [ ! -s "$file" ]; then echo -e "${RED}[✘] Error: $file is empty!${NC}"; return 1; fi
    if head -n 5 "$file" | grep -q "<!DOCTYPE html>"; then echo -e "${RED}[✘] Error: $file is HTML!${NC}"; return 1; fi

    echo -n -e "${YELLOW}[~] Injecting $cc data into $target_set...${NC}"
    (
        echo "flush $target_set"
        grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
    ) | ipset restore -exist 2>/dev/null
    
    local count=$(ipset list "$target_set" | grep 'Number of entries' | awk '{print $4}')
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        echo -e " ${GREEN}[OK] ($count entries)${NC}"
    else
        echo -e " ${RED}[FAILED] Fallback...${NC}"
        while read -r ip; do
            [[ "$ip" =~ ^#.* ]] || [[ -z "$ip" ]] && continue
            ipset add "$target_set" "$ip" -exist 2>/dev/null
        done < "$file"
        echo -e "${GREEN}[✔] Loaded via loop.${NC}"
    fi
}

for cc in ir ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ "$cc" == "ir" ]; then
        load_set_nuclear "Iran" "$FILE" "country_block_out"
    else
        load_set_nuclear "$cc" "$FILE" "country_block_in"
        if [ -s "$FILE" ]; then
            grep -v '^#' "$FILE" | tr -d '\r' | awk 'NF {print "add country_block_out " $1}' | ipset restore -exist 2>/dev/null
        fi
    fi
done

# 2. FLUSH EVERYTHING (Including UFW)
echo -e "${YELLOW}[~] Nuclear Flush (Cleaning all tables)...${NC}"
if command -v ufw >/dev/null; then ufw disable >/dev/null 2>&1; fi
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

# 3. HIGHEST PRIORITY POLICY ROUTING (Priority 2)
echo -e "${YELLOW}[~] Applying Priority 2 Blackhole...${NC}"
ip route flush table 200 2>/dev/null
ip route add blackhole default table 200 2>/dev/null

# Priority 2 is almost impossible for any VPN/WARP to override (except local loopback)
ip rule del fwmark 0x99 2>/dev/null
ip rule add fwmark 0x99 table 200 priority 2

# 4. MULTILAYER ENFORCEMENT
# Mark EVERYTHING in PREROUTING and OUTPUT before it reaches any other table
for table in mangle; do
    for chain in PREROUTING OUTPUT FORWARD; do
        iptables -t $table -I $chain 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
    done
done

# Drop incoming RU/CN
iptables -t raw -I PREROUTING 1 -m set --match-set country_block_in src -j DROP

# Immediate Reject for local/forwarded traffic (Admin Prohibited)
iptables -I FORWARD 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-admin-prohibited
iptables -I OUTPUT 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-admin-prohibited

# 5. DNS HIJACK PREVENTION (stateless)
iptables -t mangle -I OUTPUT 1 -p udp --dport 53 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -I FORWARD 1 -p udp --dport 53 -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 6. BASE CONNECTIVITY
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

echo -e "${GREEN}[✔] NUCLEAR FIREWALL 4.5 ACTIVE.${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Policy Rule Priority 2: $(ip rule show | grep 0x99)"
echo -e "Routing Table 200:      $(ip route show table 200)"
echo -e "${CYAN}--------------------------------------------------${NC}"
