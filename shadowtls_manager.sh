#!/bin/bash

# ==============================================================================
# ShadowTLS Manager (v3)
# Advanced "Wrapper" that mimics legitimate TLS handshakes (e.g., to Microsoft)
# Listen: 9443 -> Handshake: www.microsoft.com -> Forward: 2222 (SSH)
# ==============================================================================

PORT_SHADOWTLS=9443
PORT_SSH_INTERNAL=2222
HANDSHAKE_DOMAIN="www.microsoft.com:443"
# 1. Download Registry
echo -e "\033[1;33m[~] Fetching latest ShadowTLS version...\033[0m"
LATEST_TAG=$(curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest | grep -oP '"tag_name": "\K[^"]+')
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v0.2.25" # Fallback if API fails
    echo -e "\033[1;31m[!] Failed to fetch tag, using fallback: $LATEST_TAG\033[0m"
fi

DOWNLOAD_URL="https://github.com/ihciah/shadow-tls/releases/download/${LATEST_TAG}/shadow-tls-x86_64-unknown-linux-musl"

echo -e "\033[1;33m[~] Downloading ShadowTLS ${LATEST_TAG}...\033[0m"
curl -L -o /usr/local/bin/shadow-tls "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo -e "\033[0;31m[✘] Failed to download ShadowTLS binary.\033[0m"
    exit 1
fi
chmod +x /usr/local/bin/shadow-tls

# 2. Create Service
echo -e "\033[1;33m[~] Configuring Service (Port $PORT_SHADOWTLS)...\033[0m"
cat > /etc/systemd/system/shadow-tls.service <<EOF
[Unit]
Description=ShadowTLS Wrapper
After=network.target

[Service]
# Mode: Server
# Listen: $PORT_SHADOWTLS
# Server to mimicking: $HANDSHAKE_DOMAIN
# Target (our SSH): 127.0.0.1:$PORT_SSH_INTERNAL
# Password: Let's use a random or fixed password. For SSH wrapper, the password is used by the client wrapper.
# We'll use the same PASSWORD variable style if needed, or a fixed one for the tunnel.
# ShadowTLS V3 syntax: shadow-tls --fastopen server --listen 0.0.0.0:9443 --server 127.0.0.1:2222 --tls www.microsoft.com:443 --password mypassword
ExecStart=/usr/local/bin/shadow-tls --fastopen server --listen 0.0.0.0:${PORT_SHADOWTLS} --server 127.0.0.1:${PORT_SSH_INTERNAL} --tls ${HANDSHAKE_DOMAIN} --password megassh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable & Start
systemctl daemon-reload
systemctl enable --now shadow-tls

echo -e "\033[1;32m[+] ShadowTLS Active on Port $PORT_SHADOWTLS.\033[0m"
echo -e "    - Mimicking: $HANDSHAKE_DOMAIN"
echo -e "    - Password:  megassh"
