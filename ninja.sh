#!/bin/bash

# ==========================================
#  NINJA TUNNEL - DETERMINISTIC WIREGUARD
#  Code-to-Code Exclusive Tunneling
# ==========================================

# Colors
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function: Logo
show_logo() {
    clear
    echo -e "${BLUE}"
    echo " ███╗   ██╗██╗███╗   ██╗     ██╗ █████╗ "
    echo " ████╗  ██║██║████╗  ██║     ██║██╔══██╗"
    echo " ██╔██╗ ██║██║██╔██╗ ██║     ██║███████║"
    echo " ██║╚██╗██║██║██║╚██╗██║██   ██║██╔══██║"
    echo " ██║ ╚████║██║██║ ╚████║╚█████╔╝██║  ██║"
    echo " ╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═╝"
    echo -e "         WARP SPEED TUNNEL v2.0         ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
}

# 1. Install Dependencies First
echo -e "${CYAN}[Wait] Installing Dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -q > /dev/null 2>&1
apt install wireguard iptables-persistent iproute2 xxd -y -q > /dev/null 2>&1

# Enable IP Forwarding & BBR
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ninja.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-ninja.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-ninja.conf
sysctl --system > /dev/null 2>&1

# Function: Generate Key from Secret (Deterministic)
gen_key() {
    local phrase="$1"
    # Create a 32-byte private key from the hash of the secret
    echo -n "$phrase" | sha256sum | xxd -r -p | base64
}

show_logo

echo -e "Select Server Location:"
echo -e "1) ${RED}Kharej (Remote Server)${NC}"
echo -e "2) ${GREEN}Iran (Local Server)${NC}"
read -p "Option [1-2]: " MODE

if [[ "$MODE" == "1" ]]; then
    # --- KHAREJ SETUP ---
    echo -e "\n${RED}--- KHAREJ SETUP ---${NC}"
    read -p "Enter IRAN Server IP: " PEER_IP
    read -p "Enter Tunnel Secret (Password): " SECRET
    
    # Generate Deterministic Keys
    # Kharej Private Key comes from "Secret" + "Kharej"
    PRIV_KEY=$(gen_key "${SECRET}_Kharej")
    # Iran Public Key comes from "Secret" + "Iran" -> then derived to public
    IRAN_PRIV_TEMP=$(gen_key "${SECRET}_Iran")
    PEER_PUB_KEY=$(echo "$IRAN_PRIV_TEMP" | wg pubkey)
    
    # Config
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.10.10.1/24
ListenPort = 51820
PrivateKey = $PRIV_KEY
MTU = 1280
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $PEER_PUB_KEY
AllowedIPs = 10.10.10.2/32
EOF

    systemctl enable wg0 > /dev/null 2>&1
    systemctl restart wg0
    
    show_logo
    echo -e "${GREEN}✅ Kharej Server is READY!${NC}"
    echo -e "Wait for Iran server to connect..."

elif [[ "$MODE" == "2" ]]; then
    # --- IRAN SETUP ---
    echo -e "\n${GREEN}--- IRAN SETUP ---${NC}"
    read -p "Enter KHAREJ Server IP: " PEER_IP
    read -p "Enter Tunnel Secret (SAME as Kharej): " SECRET
    
    # Generate Deterministic Keys
    PRIV_KEY=$(gen_key "${SECRET}_Iran")
    # Kharej Public Key comes from "Secret" + "Kharej" -> then derived to public
    KHAREJ_PRIV_TEMP=$(gen_key "${SECRET}_Kharej")
    PEER_PUB_KEY=$(echo "$KHAREJ_PRIV_TEMP" | wg pubkey)
    
    # Protocol & Ports
    echo -e "\nSelect Traffic Protocol:"
    echo "1) TCP"
    echo "2) UDP"
    echo "3) Both"
    read -p "Select: " PROTO
    
    echo -e "\nEnter Inbound Ports (comma separated, e.g. 2096,443):"
    read -p "Ports: " PORTS
    
    # Config
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.10.10.2/24
PrivateKey = $PRIV_KEY
MTU = 1280
DNS = 8.8.8.8

[Peer]
PublicKey = $PEER_PUB_KEY
Endpoint = $PEER_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
EOF

    systemctl enable wg0 > /dev/null 2>&1
    systemctl restart wg0
    
    # Apply Port Forwarding
    IFS=',' read -ra PORT_LIST <<< "$PORTS"
    for port in "${PORT_LIST[@]}"; do
        if [[ "$PROTO" == "1" || "$PROTO" == "3" ]]; then
            iptables -t nat -A PREROUTING -p tcp --dport "$port" -j DNAT --to-destination 10.10.10.1
        fi
        if [[ "$PROTO" == "2" || "$PROTO" == "3" ]]; then
            iptables -t nat -A PREROUTING -p udp --dport "$port" -j DNAT --to-destination 10.10.10.1
        fi
    done
    iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
    netfilter-persistent save > /dev/null 2>&1
    
    show_logo
    echo -e "${GREEN}✅ Ninja Tunnel Connected!${NC}"
    echo -e "Traffic on ports [${PORTS}] is now tunneled via Kharej."
    echo -e "Ping Test: $(ping -c 1 -W 1 10.10.10.1 | grep 'bytes from' || echo 'Fail')"
fi
