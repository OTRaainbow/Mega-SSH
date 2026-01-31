#!/bin/bash

# ==============================================================================
# Nuclear Firewall 5.0 (FINAL SYNC)
# Highest possible priority (Priority 2) to override all tunnel drivers.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}    NUCLEAR FIREWALL 5.0 - ABSOLUTE PRIORITY     ${NC}"
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

# 2. NUCLEAR FLUSH
echo -e "${YELLOW}[~] Nuclear Flush (Cleaning all tables)...${NC}"
if command -v ufw >/dev/null; then ufw disable >/dev/null 2>&1; fi
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# 2.5 LOAD CUSTOM USER RULES (ufw-user-*)
if [ -f "user.rules" ]; then
    echo -e "${YELLOW}[~] Loading custom user.rules...${NC}"
    # 1. Create necessary ufw chains if they don't exist
    for chain in ufw-user-input ufw-user-output ufw-user-forward ufw-before-logging-input ufw-before-logging-output ufw-before-logging-forward ufw-user-logging-input ufw-user-logging-output ufw-user-logging-forward ufw-after-logging-input ufw-after-logging-output ufw-after-logging-forward ufw-logging-deny ufw-logging-allow ufw-user-limit ufw-user-limit-accept; do
        iptables -N $chain 2>/dev/null
    done

    # 2. Hook user chains into main chains (at the top)
    iptables -I INPUT 1 -j ufw-user-input
    iptables -I OUTPUT 1 -j ufw-user-output
    iptables -I FORWARD 1 -j ufw-user-forward

    # 3. Load the rules from user.rules (skipping the *filter and COMMIT lines for manual injection)
    # We use a loop to apply each line to avoid overwriting existing rules or failing on non-filter lines.
    grep '^-A' user.rules | while read -r rule; do
        iptables $rule 2>/dev/null
    done
    echo -e "${GREEN}[✔] user.rules loaded into iptables.${NC}"
else
    echo -e "${YELLOW}[!] user.rules not found, skipping.${NC}"
fi

# 3. ABSOLUTE PRIORITY POLICY ROUTING (Priority 2)
echo -e "${YELLOW}[~] Applying Priority 2 Blackhole...${NC}"
ip route flush table 200 2>/dev/null
ip route add blackhole default table 200 2>/dev/null

# Clean up ALL previous rules to avoid priority conflicts
while ip rule show | grep -q "fwmark 0x99"; do
    ip rule del fwmark 0x99 2>/dev/null
done

# Priority 2 is the absolute ceiling for user-defined rules.
ip rule add fwmark 0x99 table 200 priority 2

# 4. MULTILAYER ENFORCEMENT
# Mark EVERYTHING in PREROUTING and OUTPUT before it reaches any other table
for chain in PREROUTING INPUT FORWARD OUTPUT POSTROUTING; do
    iptables -t mangle -I $chain 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
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
iptables -P INPUT DROP

# 7. Persistence
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save > /dev/null 2>&1
fi

echo -e "Policy Rule Pri 2: $(ip rule show | grep 0x99)"
echo -e "${GREEN}[✔] NUCLEAR FIREWALL 5.0 ACTIVE.${NC}"
