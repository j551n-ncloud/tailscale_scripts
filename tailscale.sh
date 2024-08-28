#!/bin/bash

# Function to install necessary packages and enable network optimizations
setup_environment() {
    echo "=== Setting up environment ==="

    # Install necessary packages (sudo, ethtool, curl)
    if ! command -v sudo &>/dev/null; then
        echo "sudo is not installed. Installing..."
        apt-get update
        apt-get install -y sudo
    fi

    if ! command -v ethtool &>/dev/null; then
        echo "ethtool is not installed. Installing..."
        sudo apt-get install -y ethtool
    fi

    if ! command -v curl &>/dev/null; then
        echo "curl is not installed. Installing..."
        sudo apt-get install -y curl
    fi

    # Enable IP forwarding and IPv6 forwarding
    echo "Enabling IP forwarding and IPv6 forwarding..."
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
    echo 'net.ipv4.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.accept_source_route = 1' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p /etc/sysctl.conf
}

# Function to configure network optimizations for Tailscale
configure_network_optimizations() {
    echo "=== Configuring network optimizations ==="

    # Identify the network device for default route
    NETDEV=$(ip route show 0/0 | cut -f5 -d' ')
    
    # Enable UDP GRO forwarding and disable GRO list
    echo "Configuring UDP GRO forwarding and disabling GRO list for $NETDEV..."
    sudo ethtool -K $NETDEV rx-udp-gro-forwarding on rx-gro-list off

    # Check if networkd-dispatcher is enabled
    if systemctl is-enabled networkd-dispatcher &>/dev/null; then
        # Create a script in networkd-dispatcher for persistent settings
        printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off\n' "$NETDEV" | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale > /dev/null
        sudo chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale
        echo "Persistent network optimizations configured."
    else
        echo "Warning: networkd-dispatcher is not enabled. Skipping persistent configuration."
    fi
}

# Function to install Tailscale and configure
install_and_configure_tailscale() {
    echo "=== Installing and configuring Tailscale ==="

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
    echo "=== Tailscale status ==="
    sudo tailscale status

    # Keep the script running to maintain the Tailscale connection
    read -r -d '' _ </dev/tty
}

# Main script execution
setup_environment
configure_network_optimizations
install_and_configure_tailscale
exit
