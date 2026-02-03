#!/bin/bash
# MegaSSH Quick Fix: RAW Table & Persistence
# Run this to achieve "Elite Status" immediately.

# --- Colors ---
BGREEN='\033[1;32m'
BRED='\033[1;31m'
NC='\033[0m'

echo -e "${BGREEN}[ PHASE A ] Injecting RAW Table Rules...${NC}"
iptables -t raw -A PREROUTING -p tcp -m multiport --dports 22,443 -j NOTRACK
iptables -t raw -A OUTPUT -p tcp -m multiport --sports 22,443 -j NOTRACK
# Parity ACCEPT rules
iptables -t raw -A PREROUTING -p tcp -m multiport --dports 22,443 -j ACCEPT
iptables -t raw -A OUTPUT -p tcp -m multiport --sports 22,443 -j ACCEPT

echo -e "${BGREEN}[ PHASE B ] Forcing Persistence...${NC}"
# Save currently active rules
if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

# Ensure crontab entry exists
CRON_FILE="/etc/cron.d/megassh_maintenance"
if [ ! -f "$CRON_FILE" ] || ! grep -q "firewall_manager.sh" "$CRON_FILE"; then
    echo "@reboot root /usr/local/bin/firewall_manager.sh >> /var/log/megassh_maintenance.log 2>&1" >> "$CRON_FILE"
    chmod 644 "$CRON_FILE"
    systemctl restart cron 2>/dev/null
fi

echo -e "${BGREEN}[ PHASE C ] Finalizing Status...${NC}"
LOG_FILE="/var/log/megassh_install.log"
if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; fi
sed -i '/MEGASSH_INSTALLATION_SUCCESSFUL/d' "$LOG_FILE"
echo "MEGASSH_INSTALLATION_SUCCESSFUL" >> "$LOG_FILE"

echo ""
echo -e "${BGREEN}DONE! Please run ./mega-audit.sh to verify.${NC}"
