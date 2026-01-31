#!/bin/bash

# ==============================================================================
# UDPGW Installer (BadVPN)
# Optimized for Ubuntu 24.04
# ==============================================================================

PORT_UDPGW=7301

echo -e "\033[1;36m[+] Starting UDPGW (BadVPN) Installation...\033[0m"

# Install Build Dependencies
apt update
apt install -y git cmake make gcc build-essential

# Build BadVPN if not present
if [ ! -f /usr/local/bin/badvpn-udpgw ]; then
    echo -e "\033[1;33m[~] Compiling BadVPN-UDPGW (This may take a minute)...\033[0m"
    mkdir -p /root/badvpn_build
    cd /root/badvpn_build
    
    # Clone specific tag or master
    git clone https://github.com/ambrop72/badvpn.git .
    
    # Compile
    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .
    make
    
    # Install
    cp udpgw/badvpn-udpgw /usr/local/bin/
    chmod +x /usr/local/bin/badvpn-udpgw
    
    # Cleanup
    cd /root
    rm -rf /root/badvpn_build
    echo -e "\033[1;32m[+] BadVPN Compiled Successfully.\033[0m"
else
    echo -e "\033[1;32m[+] BadVPN is already installed.\033[0m"
fi

# Create Systemd Service
echo -e "\033[1;33m[~] Creating UDPGW Service on Port ${PORT_UDPGW}...\033[0m"
cat > /etc/systemd/system/udpgw.service <<EOF
[Unit]
Description=BadVPN UDPGW
After=network.target

[Service]
# Optimized UDPGW Flags for High Volume
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT_UDPGW} --max-clients 2000 --max-connections-for-client 10 --loglevel 0
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable & Start
systemctl daemon-reload
systemctl enable --now udpgw

echo -e "\033[1;32m[+] UDPGW Service Started.\033[0m"
