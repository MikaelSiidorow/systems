# shellcheck shell=bash

tailscale_bin=/usr/bin/tailscale
login_server=https://hs.miksu.app

if [[ ! -x "$tailscale_bin" ]]; then
  echo "Tailscale is not installed at $tailscale_bin." >&2
  echo "Install and enable the Pop!_OS tailscaled service first." >&2
  exit 1
fi

control_url="$($tailscale_bin debug prefs | jq -r '.ControlURL // ""')"

if [[ "$control_url" == "$login_server" ]]; then
  sudo "$tailscale_bin" set \
    --accept-dns=true \
    --accept-routes=true
else
  sudo "$tailscale_bin" up \
    --login-server="$login_server" \
    --accept-dns=true \
    --accept-routes=true
fi

exec "$tailscale_bin" status
