#!/bin/bash

# ==============================================================================
# Stunnel Manager (SSL Wrapping for SSH)
# Adds a layer of TLS encryption to hide SSH traffic
# Listen: 8443 (SSL) -> Forward: 2222 (SSH)
# ==============================================================================

PORT_STUNNEL=8443
PORT_SSH_INTERNAL=2222
CERT_DIR="/etc/stunnel"
CERT_FILE="$CERT_DIR/stunnel.pem"

echo -e "\033[1;36m[+] Initializing Stunnel (SSL Wrapper)...\033[0m"

# 1. Install Stunnel
apt update
apt install -y stunnel4 openssl

# 2. Generate Certificate
if [ ! -f "$CERT_FILE" ]; then
    echo -e "\033[1;33m[~] Generating Self-Signed SSL Certificate...\033[0m"
    mkdir -p "$CERT_DIR"
    openssl req -new -x509 -days 365 -nodes \
        -out "$CERT_FILE" -keyout "$CERT_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=www.rubika.ir" >/dev/null 2>&1
    chmod 600 "$CERT_FILE"
    echo -e "\033[1;32m[+] Certificate Generated.\033[0m"
else
    echo -e "\033[1;32m[+] Certificate already exists.\033[0m"
fi

# 3. Configure Stunnel
echo -e "\033[1;33m[~] 配置 Stunnel Config...\033[0m"
cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel4/stunnel.pid
cert = $CERT_FILE
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-tls]
accept = $PORT_STUNNEL
connect = 127.0.0.1:$PORT_SSH_INTERNAL
EOF

# 4. Enable and Start
sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
systemctl enable stunnel4
systemctl restart stunnel4

echo -e "\033[1;32m[+] Stunnel is running on Port $PORT_STUNNEL.\033[0m"
echo -e "    - Connect using an Stunnel client -> YourIP:$PORT_STUNNEL"
