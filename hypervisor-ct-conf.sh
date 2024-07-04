#!/usr/bin/env bash

function header_info {
clear
cat <<"EOF"
  ______      _ __                __
 /_  __/___ _(_) /_____________ _/ /__
  / / / __ `/ / / ___/ ___/ __ `/ / _ \
 / / / /_/ / / (__  ) /__/ /_/ / /  __/
/_/  \__,_/_/_/____/\___/\__,_/_/\___/

EOF
}
header_info
set -e
while true; do
  read -p "This will add Tailscale configuration to an existing LXC Container ONLY. Proceed(y/n)?" yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*) exit ;;
  *) echo "Please answer yes or no." ;;
  esac
done
header_info
echo "Loading..."
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

NODE=$(hostname)
MSG_MAX_LENGTH=0
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  ITEM=$(echo "$line" | awk '{print substr($0,36)}')
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  CTID_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

while [ -z "${CTID:+x}" ]; do
  CTID=$(whiptail --backtitle "j551n Scripts" --title "Containers on $NODE" --radiolist \
    "\nSelect a container to configure for Tailscale:\n" \
    16 $(($MSG_MAX_LENGTH + 23)) 6 \
    "${CTID_MENU[@]}" 3>&1 1>&2 2>&3) || exit
done

CTID_CONFIG_PATH=/etc/pve/lxc/${CTID}.conf
cat <<EOF >>$CTID_CONFIG_PATH
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
header_info
msg "Tailscale configuration added to container ${CTID}."
msg "To complete setup, you need to manually install Tailscale inside the container and configure it."
msg "After installation, run 'tailscale up' within the container to activate Tailscale."
msg "Please reboot the ${CTID} LXC container to apply the changes."

