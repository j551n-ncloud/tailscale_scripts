#!/bin/bash

# Tailscale Setup Script with Enhanced Security and Error Handling
# Version: 2.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator

# Global variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/tailscale-setup.log"
readonly SYSCTL_BACKUP="/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error_exit "This script should not be run as root for security reasons. Run as a regular user with sudo access."
    fi
}

# Verify sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log "INFO" "This script requires sudo access. You may be prompted for your password."
        sudo -v || error_exit "Failed to obtain sudo access"
    fi
}

# Validate CIDR format
validate_cidr() {
    local cidr="$1"
    if [[ ! $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    
    # Extract IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Validate IP octets
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    
    # Validate prefix length
    if [[ $prefix -gt 32 ]]; then
        return 1
    fi
    
    return 0
}

# Validate auth key format (basic check)
validate_auth_key() {
    local key="$1"
    if [[ ${#key} -lt 20 || ! $key =~ ^tskey- ]]; then
        return 1
    fi
    return 0
}

# Function to install necessary packages
setup_environment() {
    log "INFO" "Setting up environment..."

    # Update package list
    log "INFO" "Updating package list..."
    sudo apt-get update || error_exit "Failed to update package list"

    # Install necessary packages
    local packages=("ethtool" "curl" "systemd")
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "INFO" "Installing $package..."
            sudo apt-get install -y "$package" || error_exit "Failed to install $package"
        else
            log "INFO" "$package is already installed"
        fi
    done

    log "INFO" "Environment setup completed"
}

# Function to configure network optimizations
configure_network_optimizations() {
    log "INFO" "Configuring network optimizations..."

    # Ask if user wants legacy source route settings
    echo "Modern Tailscale typically doesn't require accept_source_route settings."
    echo "These were needed in older versions but can introduce security considerations."
    read -r -p "Enable legacy source route acceptance? (only if you have routing issues) (y/N): " enable_source_route

    # Backup current sysctl configuration
    if [[ -f /etc/sysctl.conf ]]; then
        sudo cp /etc/sysctl.conf "$SYSCTL_BACKUP"
        log "INFO" "Backed up sysctl.conf to $SYSCTL_BACKUP"
    fi

    # Check if settings already exist to avoid duplicates
    local settings=(
        "net.ipv4.ip_forward=1"
        "net.ipv6.conf.all.forwarding=1"
    )
    
    # Add legacy source route settings if requested
    if [[ $enable_source_route =~ ^[Yy]$ ]]; then
        log "INFO" "Adding legacy source route settings..."
        settings+=(
            "net.ipv4.conf.all.accept_source_route=1"
            "net.ipv6.conf.all.accept_source_route=1"
        )
    fi

    for setting in "${settings[@]}"; do
        local key="${setting%=*}"
        if ! grep -q "^$key" /etc/sysctl.conf 2>/dev/null; then
            echo "$setting" | sudo tee -a /etc/sysctl.conf > /dev/null
            log "INFO" "Added $setting to sysctl.conf"
        else
            log "INFO" "$key already configured in sysctl.conf"
        fi
    done

    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.conf || error_exit "Failed to apply sysctl settings"

    # Configure network device optimizations
    local netdev
    netdev=$(ip route show default | awk '/default/ { print $5; exit }')
    
    if [[ -z "$netdev" ]]; then
        log "WARN" "Could not determine default network device, skipping ethtool optimizations"
        return
    fi

    log "INFO" "Configuring network optimizations for device: $netdev"
    
    # Check if the device supports the features before applying
    if sudo ethtool -k "$netdev" | grep -q "rx-udp-gro-forwarding"; then
        sudo ethtool -K "$netdev" rx-udp-gro-forwarding on rx-gro-list off || \
            log "WARN" "Failed to configure ethtool settings for $netdev"
    else
        log "WARN" "Device $netdev does not support rx-udp-gro-forwarding"
    fi

    # Setup persistent network configuration
    if systemctl is-enabled networkd-dispatcher &>/dev/null; then
        local script_path="/etc/networkd-dispatcher/routable.d/50-tailscale"
        sudo mkdir -p "$(dirname "$script_path")"
        
        cat << EOF | sudo tee "$script_path" > /dev/null
#!/bin/sh
# Tailscale network optimizations
# Auto-generated by $SCRIPT_NAME

NETDEV=\$(ip route show default | awk '/default/ { print \$5; exit }')
if [ -n "\$NETDEV" ] && ethtool -k "\$NETDEV" | grep -q "rx-udp-gro-forwarding"; then
    ethtool -K "\$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
fi
EOF
        sudo chmod 755 "$script_path"
        log "INFO" "Persistent network optimizations configured"
    else
        log "WARN" "networkd-dispatcher is not enabled. Network optimizations may not persist after reboot"
    fi
}

# Function to get user input with validation
get_validated_input() {
    local prompt="$1"
    local validator="$2"
    local input
    
    while true; do
        read -r -p "$prompt" input
        if [[ -n "$input" ]] && $validator "$input"; then
            echo "$input"
            return 0
        else
            echo "Invalid input. Please try again." >&2
        fi
    done
}

# Function to get auth key securely
get_auth_key() {
    local auth_key
    echo "Enter your Tailscale auth key (input will be hidden):"
    read -r -s auth_key
    echo  # New line after hidden input
    
    if ! validate_auth_key "$auth_key"; then
        error_exit "Invalid auth key format. Auth keys should start with 'tskey-' and be at least 20 characters long."
    fi
    
    echo "$auth_key"
}

# Function to install and configure Tailscale
install_and_configure_tailscale() {
    log "INFO" "Installing and configuring Tailscale..."

    # Check if Tailscale is already installed
    if command -v tailscale &>/dev/null; then
        log "INFO" "Tailscale is already installed"
        if sudo tailscale status &>/dev/null; then
            log "WARN" "Tailscale appears to already be configured and running"
            read -r -p "Do you want to reconfigure? (y/N): " reconfigure
            if [[ ! $reconfigure =~ ^[Yy]$ ]]; then
                log "INFO" "Skipping Tailscale configuration"
                return 0
            fi
        fi
    else
        # Install Tailscale
        log "INFO" "Downloading and installing Tailscale..."
        if ! curl -fsSL https://tailscale.com/install.sh | sh; then
            error_exit "Failed to install Tailscale"
        fi
    fi

    # Start tailscaled service
    sudo systemctl enable tailscaled || error_exit "Failed to enable tailscaled service"
    sudo systemctl start tailscaled || error_exit "Failed to start tailscaled service"

    # Wait for service to be ready
    sleep 2

    # Get authentication key securely
    local auth_key
    auth_key=$(get_auth_key)

    # Get subnet configuration
    local subnets=()
    local subnet_cidr
    
    subnet_cidr=$(get_validated_input "Enter first subnet CIDR (e.g., 192.168.1.0/24): " validate_cidr)
    subnets+=("$subnet_cidr")

    # Ask for additional subnets
    while true; do
        read -r -p "Do you want to add another subnet? (y/N): " add_subnet
        if [[ $add_subnet =~ ^[Yy]$ ]]; then
            subnet_cidr=$(get_validated_input "Enter subnet CIDR: " validate_cidr)
            subnets+=("$subnet_cidr")
        else
            break
        fi
    done

    # Ask about exit node
    read -r -p "Configure as exit node? (y/N): " exit_node
    
    # Build Tailscale command
    local tailscale_args=(
        "--auth-key=$auth_key"
        "--accept-routes"
    )
    
    if [[ ${#subnets[@]} -gt 0 ]]; then
        local subnet_list
        subnet_list=$(IFS=','; echo "${subnets[*]}")
        tailscale_args+=("--advertise-routes=$subnet_list")
    fi
    
    if [[ $exit_node =~ ^[Yy]$ ]]; then
        tailscale_args+=("--advertise-exit-node")
    fi

    # Connect to Tailscale
    log "INFO" "Connecting to Tailscale with subnets: ${subnets[*]}"
    if ! sudo tailscale up "${tailscale_args[@]}"; then
        error_exit "Failed to connect to Tailscale"
    fi
    
    # Check if routes need manual approval
    log "INFO" "Checking route approval status..."
    if sudo tailscale status | grep -q "route.*pending"; then
        echo "⚠️  IMPORTANT: Some routes are pending approval."
        echo "   Go to https://login.tailscale.com/admin/machines"
        echo "   and approve the advertised routes for this device."
    fi

    # Clear the auth key from memory (best effort)
    auth_key=""
    unset auth_key

    log "INFO" "Tailscale setup completed successfully!"
    
    # Display status
    echo "=== Tailscale Status ==="
    sudo tailscale status
    
    echo "=== IP Address ==="
    sudo tailscale ip -4
}

# Function to cleanup on exit
cleanup() {
    log "INFO" "Script execution completed"
}

# Main execution function
main() {
    log "INFO" "Starting Tailscale setup script"
    
    check_root
    check_sudo
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    setup_environment
    configure_network_optimizations
    install_and_configure_tailscale
    
    log "INFO" "All tasks completed successfully!"
    echo "Log file available at: $LOG_FILE"
}

# Run main function
main "$@"
