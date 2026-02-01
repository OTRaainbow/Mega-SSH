#!/bin/bash
# ==============================================================================
# MegaSSH: Total Geofence Lockout (CN, RU, IR Outbound)
# Action: SILENT DROP (Blackhole)
# ==============================================================================

# Search for binaries if not in PATH
IPSET_BIN=$(which ipset)
IPTABLES_BIN=$(which iptables)
RULES_DIR="/etc/megassh/rules"

# Ensure directories exist
mkdir -p "$RULES_DIR"

# 1. Initialize High-Performance Sets
# We use a swap method to ensure zero downtime during updates
echo "[+] Initializing Blocklists..."

$IPSET_BIN create -! country_block_out hash:net maxelem 1000000

# Create a temporary set for atomic swapping
$IPSET_BIN create -! country_block_out_tmp hash:net maxelem 1000000
$IPSET_BIN flush country_block_out_tmp

# 2. Fast Loader Function (Parses .netset files properly)
load_set() {
    local file=$1
    local set_name=$2
    if [ -f "$file" ]; then
        echo "   Processing $file..."
        # Extract only valid CIDRs (skip comments #), format for ipset restore
        grep -vE "^#|^$" "$file" | sed "s/^/add $set_name /" | $IPSET_BIN restore -!
    else
        echo "   [!] File not found: $file"
    fi
}

# 3. Load Data into Temporary Set
load_set "$RULES_DIR/cn.netset" "country_block_out_tmp"
load_set "$RULES_DIR/ru.netset" "country_block_out_tmp"
load_set "$RULES_DIR/ir.netset" "country_block_out_tmp"

# 4. Atomic Swap (Apply new rules instantly)
echo "[+] Swapping sets..."
$IPSET_BIN swap country_block_out_tmp country_block_out
$IPSET_BIN destroy country_block_out_tmp

# 5. Apply Draconian IPTables Rules
echo "[+] Applying Firewall Rules (DROP)..."

# Flush previous related rules to avoid duplication
$IPTABLES_BIN -D OUTPUT -m set --match-set country_block_out dst -j DROP 2>/dev/null
$IPTABLES_BIN -D FORWARD -m set --match-set country_block_out dst -j DROP 2>/dev/null
$IPTABLES_BIN -D OUTPUT -m set --match-set country_block_out dst -j REJECT 2>/dev/null # Remove old reject rules

# Apply DROP rules (Highest Priority in the chain)
# Blocks server itself from reaching targets
$IPTABLES_BIN -I OUTPUT 1 -m set --match-set country_block_out dst -j DROP
# Blocks VPN clients from reaching targets
$IPTABLES_BIN -I FORWARD 1 -m set --match-set country_block_out dst -j DROP

# 6. Persistence (Save rules)
if [ -d "/etc/iptables" ]; then
    if command -v iptables-save >/dev/null; then
        iptables-save > /etc/iptables/rules.v4
    else
        $IPTABLES_BIN-save > /etc/iptables/rules.v4 2>/dev/null || echo "[!] Warning: iptables-save not found."
    fi
fi

echo "[SUCCESS] Outgoing traffic to CN, RU, and IR is now strictly blackholed."
echo "Total subnets blocked: $($IPSET_BIN list country_block_out | grep 'Number of entries' | awk '{print $4}')"
