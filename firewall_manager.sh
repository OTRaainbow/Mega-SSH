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

# 2. Populate IP Sets from IP2Location Netset Files
echo -e "\033[1;33m[~] Populating IP Sets from IP2Location Files...\033[0m"

# Create Iran Set (For Outbound Block)
ipset -L country_block_out >/dev/null 2>&1 || ipset create country_block_out hash:net
ipset flush country_block_out # Clear existing entries for fresh load
if [ -f ip2location_country_ir.netset ]; then
    grep -v '^#' ip2location_country_ir.netset | while read line; do 
        [ -n "$line" ] && ipset -A country_block_out $line
    done
    echo -e "${GREEN}[✔] Loaded IP2Location Iran (Outbound Block)${NC}"
else
    echo -e "${RED}[✘] Error: ip2location_country_ir.netset not found!${NC}"
fi

# Create Russia/China Sets (For Inbound & Outbound Block)
ipset -L country_block_in >/dev/null 2>&1 || ipset create country_block_in hash:net
ipset flush country_block_in # Clear existing entries for fresh load
for cc in ru cn; do
    FILE="ip2location_country_${cc}.netset"
    if [ -f "$FILE" ]; then
        grep -v '^#' "$FILE" | while read line; do
            if [ -n "$line" ]; then
                ipset -A country_block_in $line
                ipset -A country_block_out $line # Also block outbound to these countries
            fi
        done
        echo -e "${GREEN}[✔] Loaded $FILE (Inbound/Outbound Block)${NC}"
    else
        echo -e "${RED}[✘] Error: $FILE not found!${NC}"
    fi
done

echo -e "\033[1;32m[+] IP Lists Populated (Blocked: RU/CN Inbound/Outbound, IR Outbound).\033[0m"

# 3. Apply IPTable Rules
echo -e "\033[1;33m[~] Applying Whitelist Rules (Paranoid Mode)...\033[0m"

# Configure UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 127.0.0.1 to any # Allow Localhost for HAProxy/Nginx internals
ufw allow 80/tcp           # HTTP (Decoy Redirect)
ufw allow ${PORT_HAPROXY}/tcp  # 443
ufw allow ${PORT_UDPGW}/tcp    # 7301
ufw allow ${PORT_UDPGW}/udp    # 7301
ufw allow 8443/tcp             # Stunnel (SSL SSH)
ufw allow 9443/tcp             # ShadowTLS (Advanced)
ufw allow 22/tcp               # Rescue SSH (CRITICAL)
# ufw allow 2222:2225/tcp    # (Disabled: Only Port 443 External)

# --- GEO-LOCKING (IRAN ONLY) ---
# Strategy: Drop everything NOT from Iran (Whitelist)
# Warning: Ensure you have console access or are in Iran!
# We use RAW table for performance (XDP-Lite)

# Allow Localhost
iptables -t raw -A PREROUTING -i lo -j ACCEPT
# Allow Established
iptables -t raw -A PREROUTING -m state --state RELATED,ESTABLISHED -j ACCEPT

# SAFETY CHECK: Only apply DROP if the Whitelist is populated
if ipset list country_allow_in | grep -q "Number of entries: [1-9]"; then
    echo -e "\033[1;32m[+] Geo-Whitelist populated.\033[0m"
    echo -e "\033[1;31m[!] Dropping Inbound connections from Blocked Countries (RU/CN)... \033[0m"
    # Drop if in the Block In Set (Ingress)
    iptables -t raw -A PREROUTING -m set --match-set country_block_in src -j DROP
    # Drop if NOT in Iran IP Set (Ingress) - DISABLED BY DEFAULT (Risk of lockout if user not in IR)
    # iptables -t raw -A PREROUTING -m set ! --match-set country_allow_in src -j DROP
else
    echo -e "\033[1;31m[!] WARNING: Geo-Whitelist is EMPTY. Skipping Drop Rule to prevent Lockout.\033[0m"
fi

# Drop Outgoing to IR (Prevent Leaks) - STATEFUL MODE
# OLD (Stateless): Dropped everything, killing SSH.
# iptables -t raw -I PREROUTING -m set --match-set country_block_out dst -j DROP
# iptables -t raw -I OUTPUT -m set --match-set country_block_out dst -j DROP

# NEW (Stateful): Allow SSH (Established), Block Browsing (New/Forward)
echo -e "\033[1;36m[+] Applying Smart Geo-Blocking (Allow SSH, Block Browsing)...\033[0m"

# 1. Allow ESTABLISHED connections (Fixes SSH reply)
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# 2. Block VPN Clients from accessing Iran, Russia, China (Forwarding)
iptables -A FORWARD -m set --match-set country_block_out dst -j DROP
iptables -A FORWARD -m set --match-set country_block_out dst -j LOG --log-prefix "FIREWALL_BLOCK_OUT: "

# 3. Block Server from initiating NEW connections to these countries
iptables -A OUTPUT -m set --match-set country_block_out dst -m state --state NEW -j DROP

# MSS Clamping (Packet Size Tuning - 1360)
# Helps evade filtering by limiting packet size to avoid fragmentation
# User Strategy Point 4: "Eliminate fingerprint of classic VPN tunnels"
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360

# 4. Save Rules (Persistence)
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1
systemctl enable netfilter-persistent

echo -e "\033[1;32m[+] Firewall Rules Applied & Saved.\033[0m"
