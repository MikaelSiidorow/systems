#!/usr/bin/env bash
# Update the flake inputs, then move each router whose pinned OpenWrt release
# fell out of the ImageBuilder cache to the newest cached patch release of the
# same series. ImageBuilder drops superseded patch releases, so a stale pin
# stops evaluating. Minor and major upgrades stay manual.
set -euo pipefail
cd "$(dirname "$0")"

nix flake update

cache="$(nix flake archive --json | jq -r '.inputs["openwrt-imagebuilder"].path')/cache"

for firmware in */firmware.nix; do
  current=$(sed -nE 's/^  release = "([^"]+)";$/\1/p' "$firmware")
  if [ -z "$current" ]; then
    echo "$firmware: no release pin found" >&2
    exit 1
  fi
  [ -d "$cache/$current" ] && continue

  series=${current%.*}
  latest=$(find "$cache" -mindepth 1 -maxdepth 1 -type d -name "$series.*" -printf '%f\n' |
    grep -E "^${series//./\\.}\.[0-9]+$" | sort -V | tail -n 1 || true)
  if [ -z "$latest" ]; then
    echo "$firmware: OpenWrt $current is no longer cached and no $series.x release is" >&2
    exit 1
  fi

  sed -i "s/^  release = \"$current\";$/  release = \"$latest\";/" "$firmware"
  echo "• $firmware: OpenWrt $current → $latest"
done
