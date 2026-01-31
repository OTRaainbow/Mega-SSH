#!/bin/bash

# ==============================================================================
# Bulletproof Firewall Manager (Nuclear Geo-Blocking)
# Replaces all previous rules with strict, high-priority blocks.
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[+] Starting Nuclear Firewall Harden...${NC}"

# 1. Nuke IPv6 (High Risk of Leaks)
echo -e "${YELLOW}[~] Nuking IPv6...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1

ip6tables -F
ip6tables -X
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# 2. Setup High-Capacity IPSets
echo -e "${YELLOW}[~] Initializing High-Capacity Sets (524k)...${NC}"
ipset create country_block_in hash:net maxelem 524288 -exist
ipset create country_block_out hash:net maxelem 524288 -exist
ipset flush country_block_in
ipset flush country_block_out

# 3. Fast Loading with ipset-restore format
load_set() {
    local country=$1
    local file=$2
    local target_set=$3
    if [ -f "$file" ]; then
        echo -e "${YELLOW}[~] Loading $file into $target_set...${NC}"
        # Convert to ipset restore format for speed
        # tr -d '\r' removes Windows line endings
        # awk cleans empty lines and comments, formats for ipset
        (
            echo "create $target_set hash:net maxelem 524288 -exist"
            grep -v '^#' "$file" | tr -d '\r' | awk -v set="$target_set" 'NF {print "add " set " " $1}'
        ) | ipset restore
        echo -e "${GREEN}[✔] Loaded $country successfully.${NC}"
    else
        echo -e "${RED}[✘] Error: $file not found! Skipping...${NC}"
    fi
}

# Load Iran (Outbound Only)
load_set "Iran" "ip2location_country_ir.netset" "country_block_out"

# Load Russia & China (Inbound & Outbound)
for cc in ru cn; do
    FILE="ip2location_country_${cc}.netset"
    load_set "$cc" "$FILE" "country_block_in"
    # Also add to outbound block
    if [ -f "$FILE" ]; then
        grep -v '^#' "$FILE" | tr -d '\r' | awk 'NF {print "add country_block_out " $1}' | ipset restore -exist
    fi
done

# 4. Applying Chain Rules (Absolute Top Priority)
echo -e "${YELLOW}[~] Applying Strict Filter Rules...${NC}"

# Clear existing mangle/raw for fresh start
iptables -t raw -F
iptables -t mangle -F
iptables -F

# Define Base Interface Rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- THE BLOCKS (INSERTED AT TOP) ---

# [A] Block Inbound RU/CN (RAW table is fastest)
iptables -t raw -I PREROUTING 1 -m set --match-set country_block_in src -j DROP

# [B] Block Outbound IR/RU/CN (FORWARDING - VPN Clients)
iptables -I FORWARD 1 -m set --match-set country_block_out dst -j DROP

# [C] Block Outbound IR/RU/CN (LOCAL - Server Apps)
iptables -I OUTPUT 1 -m set --match-set country_block_out dst -m state --state NEW -j DROP

# 5. UFW Integration (Allow our ports)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 7301/tcp
ufw allow 7301/udp
ufw allow 8443/tcp
ufw allow 9443/tcp
ufw --force enable

# 6. Persistence
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}[✔] NUCLEAR FIREWALL ACTIVE.${NC}"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Total Filtered Ranges: $(ipset list | grep 'Number of entries' | awk '{sum+=$4} END {print sum}')"
echo -e "${CYAN}--------------------------------------------------${NC}"
echo -e "Testing Iranian IP (5.1.43.1): $(ipset test country_block_out 5.1.43.1 2>&1)"
echo -e "Testing Russian IP (5.8.32.1): $(ipset test country_block_in 5.8.32.1 2>&1)"
echo -e "${CYAN}--------------------------------------------------${NC}"
