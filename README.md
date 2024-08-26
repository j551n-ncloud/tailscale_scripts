First run hypervisor-ct-conf.sh after lxc creation

bash -c "$(wget -qO - https://gitlab.com/j551n/tailscale_scripts/raw/main/hypervisor-ct-conf.sh)"

After this run the next cmd in lxc bash

bash -c "$(wget -qO - https://gitlab.com/j551n/tailscale_scripts/raw/main/tailscale.sh)"

