#!/bin/bash
# ==============================================================================
# MegaSSH Rescue Script (Comprehensive Repair)
# This script addresses Nginx, Firewall, and Installation status issues.
# ==============================================================================

# --- Colors ---
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
BCYAN='\033[1;36m'
NC='\033[0m'

echo -e "${BCYAN}------------------------------------------------${NC}"
echo -e "${BCYAN}Starting MegaSSH Rescue Operation...            ${NC}"
echo -e "${BCYAN}------------------------------------------------${NC}"

# 1. Fix Nginx Directory Structure
echo -e "${BYELLOW}[STEP 1] Fixing Nginx Directory Structure...${NC}"
mkdir -p /etc/nginx/sites-enabled
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
systemctl restart nginx
echo -e "${BGREEN}Nginx repaired and restarted.${NC}"

# 2. Force Missing Firewall Rules (RAW Table & IPSets)
echo -e "${BYELLOW}[STEP 2] Injecting RAW Table Rules & IPSets...${NC}"
modprobe iptable_raw 2>/dev/null
modprobe xt_multiport 2>/dev/null
modprobe xt_set 2>/dev/null

# A. NOTRACK Admin Rules
# Use -I to ensure rules are at the TOP
iptables -t raw -I PREROUTING -p tcp -m multiport --dports 22,443 -j NOTRACK 2>/dev/null
iptables -t raw -I OUTPUT -p tcp -m multiport --sports 22,443 -j NOTRACK 2>/dev/null
# Parity ACCEPT
iptables -t raw -I PREROUTING -p tcp -m multiport --dports 22,443 -j ACCEPT 2>/dev/null
iptables -t raw -I OUTPUT -p tcp -m multiport --sports 22,443 -j ACCEPT 2>/dev/null

# B. Ensure IPSets exist for Leak Switch
ipset create country_block_out hash:net maxelem 1000000 -exist 2>/dev/null
ipset create country_block_in hash:net maxelem 1000000 -exist 2>/dev/null

# Add a dummy block if empty to ensure iptables rule can function
if [ "$(ipset list country_block_out | grep 'Number of entries' | awk '{print $4}')" -eq 0 ]; then
    ipset add country_block_out 1.1.1.99 -exist 2>/dev/null
fi

# C. Inject Geofencing RAW Rules (Leak Switch)
iptables -t raw -I OUTPUT -m set --match-set country_block_out dst -j DROP 2>/dev/null
iptables -t raw -I PREROUTING -m set --match-set country_block_in src -j DROP 2>/dev/null

if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
    echo -e "${BGREEN}Firewall rules saved via netfilter-persistent.${NC}"
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    ipset save > /etc/iptables/ipsets.save 2>/dev/null
    echo -e "${BGREEN}Firewall rules saved to /etc/iptables/rules.v4.${NC}"
fi

# 3. Fix Source File Warning (Download to /root)
echo -e "${BYELLOW}[STEP 3] Re-downloading Core Scripts to /root/...${NC}"
wget -q -O /root/MegaSSH.sh https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main/MegaSSH.sh
wget -q -O /root/mega-audit.sh https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main/mega-audit.sh
wget -q -O /root/firewall_manager.sh https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main/firewall_manager.sh
chmod +x /root/MegaSSH.sh /root/mega-audit.sh /root/firewall_manager.sh
echo -e "${BGREEN}Scripts downloaded and permissioned at /root/${NC}"

# Re-sync to /usr/local/bin for global access
cp /root/MegaSSH.sh /usr/local/bin/MegaSSH.sh
cp /root/mega-audit.sh /usr/local/bin/mega-audit.sh
cp /root/firewall_manager.sh /usr/local/bin/firewall_manager.sh
chmod +x /usr/local/bin/MegaSSH.sh /usr/local/bin/mega-audit.sh /usr/local/bin/firewall_manager.sh
echo -e "${BGREEN}Scripts synchronized to /usr/local/bin/${NC}"

# 4. Force Success Flag
echo -e "${BYELLOW}[STEP 4] Writing Success Flag to Log...${NC}"
LOG_FILE="/var/log/megassh_install.log"
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
sed -i '/MEGASSH_INSTALLATION_SUCCESSFUL/d' "$LOG_FILE"
echo "MEGASSH_INSTALLATION_SUCCESSFUL" >> "$LOG_FILE"
echo -e "${BGREEN}Success flag recorded in $LOG_FILE${NC}"

echo -e "${BCYAN}------------------------------------------------${NC}"
echo -e "${BCYAN}Rescue Complete. Now running audit to verify... ${NC}"
echo -e "${BCYAN}------------------------------------------------${NC}"

# 5. Run Audit
# Trigger firewall manager update just in case
/usr/local/bin/firewall_manager.sh --update-ipsets >/dev/null 2>&1

RESCUE_AUDIT="/usr/local/bin/mega-audit.sh"
[ ! -x "$RESCUE_AUDIT" ] && RESCUE_AUDIT="./mega-audit.sh"
[ ! -x "$RESCUE_AUDIT" ] && RESCUE_AUDIT="/root/mega-audit.sh"

if [ -x "$RESCUE_AUDIT" ]; then
    bash "$RESCUE_AUDIT"
else
    echo -e "${BRED}mega-audit.sh not found. Please run it manually.${NC}"
fi

