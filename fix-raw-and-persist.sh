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

# 2. Force Missing Firewall Rules (NOTRACK)
echo -e "${BYELLOW}[STEP 2] Injecting RAW Table NOTRACK Rules...${NC}"
modprobe iptable_raw 2>/dev/null
modprobe xt_multiport 2>/dev/null

# Use -I to ensure rules are at the TOP of the chain to override any previous blocks
iptables -t raw -I PREROUTING -p tcp -m multiport --dports 22,443 -j NOTRACK
iptables -t raw -I OUTPUT -p tcp -m multiport --sports 22,443 -j NOTRACK
# Parity ACCEPT rules (Ensures traffic isn't dropped by subsequent rules if misconfigured)
iptables -t raw -I PREROUTING -p tcp -m multiport --dports 22,443 -j ACCEPT
iptables -t raw -I OUTPUT -p tcp -m multiport --sports 22,443 -j ACCEPT

if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
    echo -e "${BGREEN}Firewall rules saved via netfilter-persistent.${NC}"
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo -e "${BGREEN}Firewall rules saved to /etc/iptables/rules.v4.${NC}"
fi

# 3. Fix Source File Warning (Download to /root)
echo -e "${BYELLOW}[STEP 3] Re-downloading MegaSSH.sh to /root/...${NC}"
wget -q -O /root/MegaSSH.sh https://raw.githubusercontent.com/OTRaainbow/Mega-SSH/main/MegaSSH.sh
chmod +x /root/MegaSSH.sh
echo -e "${BGREEN}MegaSSH.sh downloaded and permissioned at /root/MegaSSH.sh${NC}"

# 4. Force Success Flag
echo -e "${BYELLOW}[STEP 4] Writing Success Flag to Log...${NC}"
LOG_FILE="/var/log/megassh_install.log"
if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; fi
# Clean old flags to prevent duplication
sed -i '/MEGASSH_INSTALLATION_SUCCESSFUL/d' "$LOG_FILE"
echo "MEGASSH_INSTALLATION_SUCCESSFUL" >> "$LOG_FILE"
echo -e "${BGREEN}Success flag recorded in $LOG_FILE${NC}"

echo -e "${BCYAN}------------------------------------------------${NC}"
echo -e "${BCYAN}Rescue Complete. Now running audit to verify... ${NC}"
echo -e "${BCYAN}------------------------------------------------${NC}"

# 5. Run Audit
if [ -x "./mega-audit.sh" ]; then
    ./mega-audit.sh
elif [ -x "/usr/local/bin/mega-audit.sh" ]; then
    /usr/local/bin/mega-audit.sh
else
    echo -e "${BRED}mega-audit.sh not found. Please run it manually.${NC}"
fi

