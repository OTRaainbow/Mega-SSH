#!/bin/bash

# ==============================================================================
# Zero-Leak Firewall (Ultra-Sync V3.0.4)
# Bypasses tunnel encapsulation with per-line set loading for maximum reliability.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}    TOTAL SHUTDOWN FIREWALL - VERSION 3.0.4      ${NC}"
echo -e "${CYAN}=================================================${NC}"

# 1. Setup IPSets
ipset create country_block_in hash:net maxelem 524288 -exist
ipset create country_block_out hash:net maxelem 524288 -exist
ipset flush country_block_in
ipset flush country_block_out

# Robust Load Verification
load_set_ultra() {
    local cc=$1; local file=$2; local target_set=$3
    if [ ! -s "$file" ]; then
        echo -e "${RED}[✘] Error: $file is empty or missing!${NC}"
        return 1
    fi
    
    # Check if it's an HTML page (GitHub 404/Redirect error)
    if head -n 5 "$file" | grep -q "<!DOCTYPE html>"; then
        echo -e "${RED}[✘] Error: $file is HTML! Download failed (GitHub Raw Link Error)${NC}"
        return 1
    fi

    echo -n -e "${YELLOW}[~] Injecting $cc data into $target_set...${NC}"
    
    # Debug: Try to add just the first line to see if ipset is working
    local first_entry=$(grep -v '^#' "$file" | grep -m 1 '/')
    if [ -n "$first_entry" ]; then
        ipset add "$target_set" "$first_entry" -exist 2>/dev/null
    fi

    # Bulk Load
    (
        echo "flush $target_set"
        grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
    ) | ipset restore -exist 2>&1 | grep -v "already exists"
    
    # Verification
    local count=$(ipset list "$target_set" | grep 'Number of entries' | awk '{print $4}')
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        echo -e " ${GREEN}[OK] ($count entries)${NC}"
    else
        echo -e " ${RED}[FAILED - SET STILL EMPTY]${NC}"
        echo -e "${YELLOW}    Diagnostic: File size is $(wc -c < "$file") bytes. First 3 lines:$(head -n 3 "$file")${NC}"
    fi
}

# Auto-Load
for cc in ir ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ "$cc" == "ir" ]; then
        load_set_ultra "Iran" "$FILE" "country_block_out"
    else
        load_set_ultra "$cc" "$FILE" "country_block_in"
        # Mirror RU/CN to outbound
        if [ -s "$FILE" ]; then
            grep -v '^#' "$FILE" | tr -d '\r' | awk 'NF {print "add country_block_out " $1}' | ipset restore -exist
        fi
    fi
done

# 2. CLEAR ALL PREVIOUS RULES
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# 3. IMPLEMENT ZERO-LEAK ROUTING (Table 200)
echo -e "${YELLOW}[~] Setting up Zero-Leak Routing (Table 200)...${NC}"
ip route flush table 200 2>/dev/null
ip route add blackhole default table 200 2>/dev/null

ip rule del fwmark 0x99 2>/dev/null
ip rule add fwmark 0x99 table 200 priority 100

# Marking
iptables -t mangle -I PREROUTING 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99
iptables -t mangle -I OUTPUT 1 -m set --match-set country_block_out dst -j MARK --set-mark 0x99

# 4. TRADITIONAL FILTER DROPS (REJECT with ICMP)
iptables -I FORWARD 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-port-unreachable
iptables -I OUTPUT 1 -m set --match-set country_block_out dst -j REJECT --reject-with icmp-port-unreachable
iptables -t raw -I PREROUTING 1 -m set --match-set country_block_in src -j DROP

# 5. DNS Hijack Prevention
iptables -I OUTPUT 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP
iptables -I FORWARD 1 -p udp --dport 53 -m set --match-set country_block_out dst -j DROP

# 6. Global Access Rules
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
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}[✔] ZERO-LEAK ULTRA-SYNC V3.0.4 ACTIVE.${NC}"
