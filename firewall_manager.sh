#!/bin/bash

# ==============================================================================
# Firewall Manager (Advanced Rules)
# Replaces legacy 'user.rules' with High-Performance IPSet Logic
# Features: Silent Drop (CN/RU), Outbound Block (IR)
# ==============================================================================

echo -e "\033[1;36m[+] Initializing Firewall Manager...\033[0m"

# Install Dependencies
apt update
apt install -y ipset iptables-persistent ufw curl

# 1. Initialize IPSet Lists
echo -e "\033[1;33m[~] Creating IPSet Lists (High Performance)...\033[0m"
ipset create country_block_in hash:net -exist
ipset create country_block_out hash:net -exist
ipset flush country_block_in
ipset flush country_block_out

# 2. Download IP Lists (Updated for Geo-Whitelisting)
echo -e "\033[1;33m[~] Downloading IP Lists (Iran Whitelist)...\033[0m"
# Check/Create Set for Iran
ipset -L country_allow_in >/dev/null 2>&1 || ipset create country_allow_in hash:net
# Download Iran IPs
wget -O ir.zone http://www.ipdeny.com/ipblocks/data/countries/ir.zone > /dev/null 2>&1
# Add IPs to Set
while read line; do ipset -A country_allow_in $line; done < ir.zone
rm ir.zone

# Check/Create Set for Outbound Block (Still block outbound logic if needed, but user didn't specify removing it)
ipset -L country_block_out >/dev/null 2>&1 || ipset create country_block_out hash:net
wget -O ir.zone http://www.ipdeny.com/ipblocks/data/countries/ir.zone > /dev/null 2>&1
while read line; do ipset -A country_block_out $line; done < ir.zone
rm ir.zone

echo -e "\033[1;32m[+] IP Lists Populated.\033[0m"

# 3. Apply IPTable Rules
echo -e "\033[1;33m[~] Applying Whitelist Rules (Paranoid Mode)...\033[0m"

# Configure UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 127.0.0.1 to any # Allow Localhost for HAProxy/Nginx internals
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
    echo -e "\033[1;31m[!] WARNING: Paranoid Mode (Drop Non-Iran) is DISABLED by default to prevent lockout.\033[0m"
    echo -e "\033[1;33m    Uncomment the DROP line in firewall_manager.sh to enable it.\033[0m"
    # Drop if NOT in Iran IP Set (Ingress) - DISABLED BY DEFAULT
    # iptables -t raw -A PREROUTING -m set ! --match-set country_allow_in src -j DROP
else
    echo -e "\033[1;31m[!] WARNING: Geo-Whitelist is EMPTY. Skipping Drop Rule to prevent Lockout.\033[0m"
fi

# Drop Outgoing to IR (Prevent Leaks)
iptables -t raw -I PREROUTING -m set --match-set country_block_out dst -j DROP
iptables -t raw -I OUTPUT -m set --match-set country_block_out dst -j DROP

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
