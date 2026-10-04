# NETGEAR R6220 OpenWrt setup

This directory has two deliberately separate pieces:

- `firmware.nix` builds an OpenWrt 25.12.5 image for the
  `netgear_r6220` profile. It owns the OpenWrt release and package set.
- `config.nix` owns the captured network topology, firewall with hardware flow
  offloading, and disabled-radio state. DHCP, LuCI, SSH, and other untouched
  UCI packages remain retained.

Build the firmware and Dewclaw deployment on `x86_64-linux`. The upstream
ImageBuilder contains Linux x86-64 executables, so these outputs do not build
directly on macOS.

## Why boot official OpenWrt first?

"Official OpenWrt" means an unmodified image from `downloads.openwrt.org`, not
the NETGEAR OEM firmware.

Booting it once proves that the exact router, factory flashing path, Ethernet
ports, radios, and recovery path work before adding a custom image. OpenWrt also
generates board-specific UCI sections on first boot. Capturing those sections
keeps us from guessing interface names, radio paths, MAC-address assignments,
or anonymous section ordering in `config.nix`.

The custom Nix image can technically be the first OpenWrt image. It uses the
same upstream profile and generated defaults. The official-first sequence is
recommended because it gives firmware problems and Nix customization problems
separate debugging steps.

## 1. Verify the hardware and prepare recovery

Read the underside label and confirm that the device is exactly `R6220`. Do not
use this image for an `R6220v2`, `R6230`, or another AC1200 model merely because
the case looks similar.

Before flashing:

1. Connect a computer to a LAN port with Ethernet. Disconnect the WAN cable.
2. Download the current NETGEAR OEM firmware and keep it locally.
3. Read the
   [OpenWrt R6220 device page](https://openwrt.org/toh/netgear/r6220), including
   its `nmrpflash` recovery notes.
4. Record the OEM WAN settings if the ISP requires PPPoE credentials, a VLAN,
   or a cloned MAC address.

The R6220 device page notes that its physical LAN numbering is reversed in the
switch mapping. Do not configure VLANs until the actual port mapping has been
tested.

## 2. Install official OpenWrt

Download these files from the OpenWrt 25.12.5 `ramips/mt7621` release:

- `openwrt-25.12.5-ramips-mt7621-netgear_r6220-squashfs-factory.img`
- `sha256sums`

Verify the image against `sha256sums`. From the NETGEAR interface, open
**Advanced > Administration > Firmware Update** and upload the `factory.img`.
Do not upload a `sysupgrade.bin` from the OEM interface.

Do not interrupt power. After the router reboots, connect a computer to a LAN
port and open `http://192.168.1.1`. OpenWrt disables Wi-Fi initially, so use
Ethernet.

Set a root password immediately, either in LuCI or over SSH:

```bash
ssh -t root@192.168.1.1 passwd
```

Do not configure Wi-Fi passwords or other secrets yet; the first capture is
most useful before secret values exist.

## 3. Capture the board-generated configuration

The capture is reference material for completing the TODOs in `config.nix`. It
is not imported directly into the firmware.

Run this from a trusted machine:

```bash
capture_dir=$(mktemp -d /tmp/r6220-openwrt.XXXXXX)

ssh root@192.168.1.1 'ubus call system board' > "$capture_dir/board.json"
ssh root@192.168.1.1 'ip -br link' > "$capture_dir/links.txt"
ssh root@192.168.1.1 'wifi status' > "$capture_dir/wifi-status.json"
ssh root@192.168.1.1 'apk list --installed' > "$capture_dir/packages.txt"

for config_name in network wireless firewall dhcp dropbear system; do
  ssh root@192.168.1.1 "uci show $config_name" \
    > "$capture_dir/$config_name.show"
  ssh root@192.168.1.1 "uci export $config_name" \
    > "$capture_dir/$config_name.uci"
done

printf 'Capture written to %s\n' "$capture_dir"
```

Review the files before copying anything into the repository. UCI exports can
contain passwords, tokens, or other secrets once a router has been configured.
Never commit those values.

Use the capture to fill in `uci.settings` in `config.nix`. Move a package such
as `network` or `wireless` out of `uci.retain` only when its complete required
state is declared.

## 4. Build the custom firmware

On the Pop!\_OS/Linux machine:

```bash
nix build .#cerberus-firmware
find -L result -maxdepth 1 -type f -print
```

The result contains several artifacts. Use:

- `*-factory.img` only when moving from NETGEAR OEM firmware to OpenWrt.
- `*-sysupgrade.bin` when OpenWrt is already installed.

The image adds `luci-ssl`, `htop`, `tcpdump`, and the lightweight HTTPS DNS
proxy with its LuCI application. Its bootstrap UCI setting is the non-secret
hostname `cerberus`. It also installs the personal SSH public key from
`openwrt/files`; private keys never enter the repository or Nix store.

## 5. Move from official OpenWrt to the Nix-built image

First make a backup:

```bash
ssh root@192.168.1.1 'sysupgrade -b /tmp/r6220-backup.tar.gz'
scp root@192.168.1.1:/tmp/r6220-backup.tar.gz .
```

Select and validate the Nix-built sysupgrade image:

```bash
firmware=$(find -L result -maxdepth 1 -type f -name '*sysupgrade.bin' -print -quit)
test -n "$firmware"
scp "$firmware" root@192.168.1.1:/tmp/r6220-sysupgrade.bin
ssh root@192.168.1.1 'sysupgrade -T /tmp/r6220-sysupgrade.bin'
```

If validation succeeds, flash while connected over Ethernet:

```bash
ssh root@192.168.1.1 'sysupgrade /tmp/r6220-sysupgrade.bin'
```

This transition stays within OpenWrt 25.12.5 and preserves the initial
configuration. For a future major OpenWrt upgrade, review the release notes and
expect to use `sysupgrade -n` followed by a fresh declarative deployment.

## 6. Review and deploy the Dewclaw configuration

The official OpenWrt 25.12.5 board-generated network and wireless state has
been captured and translated into `config.nix`. The radios remain disabled and
the R6220 becomes the router at `192.168.67.1` with a DHCP WAN. Software and
hardware flow offloading are enabled for full WAN throughput; do not combine
them with SQM/QoS. Dnsmasq forwards upstream queries through Mullvad Base DoH
at `https://base.dns.mullvad.net/dns-query`; DNS interception remains disabled.
The LAN uses `home.arpa`, with `cerberus.home.arpa` at `192.168.67.1`,
`hermes.home.arpa` at `192.168.67.2`, and a fixed Hestia lease and record at
`192.168.67.170`. The `ha.home.arpa` and `zigbee.home.arpa` service records
also resolve to Hestia for its local HTTP reverse proxy.

Build the deployment script without contacting the router:

```bash
nix build .#cerberus-deploy
```

After reviewing the generated configuration, deploy it with:

```bash
nix run .#cerberus-deploy
```

Dewclaw snapshots the overlay before applying changes. It confirms the new
configuration by reconnecting after reboot and rolls back when confirmation
does not arrive. Keep the computer connected by Ethernet throughout a network
or firewall deployment.

OpenWrt 25.12 uses `apk`, while the released Dewclaw package deployment still
uses `opkg`. This configuration therefore disables Dewclaw package management;
`firmware.nix` is the only package source of truth.

## Secrets

Do not put secrets in `firmware.nix`, `files/`, or a Nix string used to build
the firmware. They would be stored as plaintext in `/nix/store`.

Runtime secrets should be added to `secrets/openwrt.yaml` with `sops`, then
referenced through Dewclaw's `_secret` values. Secrets are decrypted on the
deploying machine and interpolated during deployment rather than firmware
construction.

## Updating

1. Change the explicit `release` in `firmware.nix` only after the corresponding
   release exists in the pinned ImageBuilder input.
2. Update the input with `nix flake update openwrt-imagebuilder`.
3. Build and inspect `.#cerberus-firmware`.
4. Back up the router and validate the image with `sysupgrade -T`.
5. Flash by Ethernet.
6. Re-run `nix run .#cerberus-deploy` after completing the Dewclaw configuration.

Always retain the previous working sysupgrade image and the NETGEAR OEM image
for recovery.
