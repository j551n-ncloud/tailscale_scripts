#!/bin/bash

# Tailscale authentication key if key is invalid paste new one in
AUTH_KEY="tskey-auth-kuNbtx2CNTRL-9svk36a1gM7XHyMfLWzFN7qksbcTBzFs"

# Subnet CIDR replace if it differs& put " ," for other cidr
SUBNET_CIDR="192.168.0.0/24"

#curl install
sudo apt update
sudo apt upgrade
sudo apt install curl

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Enable IP forwarding and IPv6 forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf

# Configure iptables for subnet routing
sudo iptables -t nat -A POSTROUTING -s $SUBNET_CIDR ! -d $SUBNET_CIDR -o tailscale0 -j MASQUERADE

# Start Tailscale as an exit node and subnet router
sudo tailscale up --auth-key=$AUTH_KEY --accept-routes --advertise-exit-node --advertise-routes=$SUBNET_CIDR &

# Display Tailscale status
sudo tailscale status

# Keep the script running to maintain the Tailscale connection
read -r -d '' _ </dev/tty
