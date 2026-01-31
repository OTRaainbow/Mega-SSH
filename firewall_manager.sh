#!/bin/bash

# ==============================================================================
# Firewall Manager (Advanced Rules)
# Replaces legacy 'user.rules' with High-Performance IPSet Logic
# Features: Silent Drop (CN/RU), Outbound Block (IR)
# ==============================================================================

echo -e "\033[1;36m[+] Initializing Firewall Manager...\033[0m"

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Install Dependencies
apt update
apt install -y ipset iptables-persistent ufw curl

# 1. Initialize IPSet Lists (High Capacity)
echo -e "\033[1;33m[~] Creating High-Capacity IPSet Lists...\033[0m"
# Set maxelem to 500,000 to handle the huge IP2Location lists
ipset create country_block_in hash:net maxelem 500000 -exist
ipset create country_block_out hash:net maxelem 500000 -exist
ipset flush country_block_in
ipset flush country_block_out

# 2. Populate IP Sets from IP2Location Netset Files
echo -e "\033[1;33m[~] Populating IP Sets from IP2Location Files...\033[0m"

# Load IR (Outbound Only)
if [ -f ip2location_country_ir.netset ]; then
    grep -v '^#' ip2location_country_ir.netset | while read line; do 
        [ -n "$line" ] && ipset -A country_block_out $line
    done
    echo -e "${GREEN}[✔] Loaded IP2Location Iran (Outbound Only)${NC}"
else
    echo -e "${RED}[✘] Error: ip2location_country_ir.netset not found!${NC}"
fi

# Load RU/CN (Inbound & Outbound)
for cc in ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ -f "$FILE" ]; then
        echo -e "${YELLOW}[~] Processing $FILE...${NC}"
        grep -v '^#' "$FILE" | while read line; do
            if [ -n "$line" ]; then
                ipset -A country_block_in $line
                ipset -A country_block_out $line
            fi
        done
        echo -e "${GREEN}[✔] Loaded $FILE (Inbound/Outbound)${NC}"
    else
        echo -e "${RED}[✘] Error: $FILE not found!${NC}"
    fi
done

echo -e "\033[1;32m[+] IP Lists Populated. Total Rules: $(ipset list | grep 'Number of entries' | awk '{sum+=$4} END {print sum}')${NC}"

# 3. Apply IPTable Rules (AGGRESSIVE MODE)
echo -e "\033[1;33m[~] Applying Aggressive Firewall Rules...${NC}"

# Configure UFW (Base Layer)
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

# --- AGGRESSIVE GEO-BLOCKING ---

# [A] INBOUND BLOCK (Russia/China)
# We use -I to ensure these are at the VERY TOP of the RAW table
iptables -t raw -F PREROUTING # Clear previous rules in PREROUTING
iptables -t raw -I PREROUTING -i lo -j ACCEPT
iptables -t raw -I PREROUTING -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t raw -A PREROUTING -m set --match-set country_block_in src -j DROP

# [B] OUTBOUND BLOCK (Iran/Russia/China) - VPN LEAK PROTECTION
# 1. Block for VPN Clients (Forwarded traffic)
iptables -I FORWARD -m set --match-set country_block_out dst -j DROP

# 2. Block for Server Processes (SOCKS/HAProxy/System) - Catching outgoing NEW connections
iptables -I OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m set --match-set country_block_out dst -m state --state NEW -j DROP

# 3. MSS Clamping for Stealth
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360

# --- Persistence ---
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1

echo -e "\033[1;32m[+] Aggressive Firewall Rules Applied.${NC}"
echo -e "${CYAN}--- DEBUG COMMANDS ---${NC}"
echo -e "  To check if IPs are blocked: ${YELLOW}ipset list country_block_out | head -n 20${NC}"
echo -e "  To check active drops:       ${YELLOW}iptables -t raw -L PREROUTING -v -n${NC}"
echo -e "  To check VPN drops:          ${YELLOW}iptables -L FORWARD -v -n${NC}"
echo -e "${CYAN}-----------------------${NC}"
