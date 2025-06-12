First run hypervisor-ct-conf.sh after lxc creation

bash -c "$(wget -qO - https://gitlab.j551n.com/j551n/tailscale_scripts/-/raw/main/hypervisor-ct-conf.sh)"

After this run the next cmd in lxc bash

bash -c "$(wget -qO - https://gitlab.j551n.com/j551n/tailscale_scripts/-/raw/main/tailscale.sh)"

Edit 2025: new script is in the works currently in dev
