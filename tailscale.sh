#!/bin/bash

# Install sudo if not already installed
if ! command -v sudo &>/dev/null; then
    echo "sudo is not installed. Installing..."
    apt-get update
    apt-get install -y sudo
fi

# Enable IP forwarding and IPv6 forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf

# Update and install prerequisites (curl)
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl start tailscaled

# Prompt for Tailscale authentication key
read -p "Enter Tailscale authentication key: " AUTH_KEY

# Prompt for first subnet CIDR
read -p "Enter first subnet CIDR (e.g., 192.168.0.0/24): " SUBNET_CIDR

# Prompt if user wants to add a second subnet
read -p "Do you want to add a second subnet? (y/n): " ADD_SECOND_SUBNET

if [[ $ADD_SECOND_SUBNET == "y" ]]; then
    # Prompt for second subnet CIDR
    read -p "Enter second subnet CIDR (e.g., 10.0.0.0/24): " SECOND_SUBNET_CIDR
    
    if [[ -n "$SECOND_SUBNET_CIDR" ]]; then
        # Start Tailscale with both subnets
        sudo tailscale up --auth-key="$AUTH_KEY" --accept-routes --advertise-routes="$SUBNET_CIDR,$SECOND_SUBNET_CIDR" --advertise-exit-node &
    else
        echo "Invalid input for second subnet CIDR."
        exit 1
    fi
else
    # Start Tailscale with only the first subnet
    sudo tailscale up --auth-key="$AUTH_KEY" --accept-routes --advertise-routes="$SUBNET_CIDR" --advertise-exit-node &
fi

# Display Tailscale status
sudo tailscale status

# Keep the script running to maintain the Tailscale connection
read -r -d '' _ </dev/tty
