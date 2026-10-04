# TP-Link Archer C6 v2 access point

This directory describes the EU hardware revision 2.0 currently running
official OpenWrt 25.12.5 as a wired access point:

- management address `192.168.67.2/24`
- hostname `hermes` and local name `hermes.home.arpa`
- gateway and DNS through the R6220 at `192.168.67.1`
- DHCPv4 disabled on the Archer
- LAN-to-LAN uplink; the Archer WAN port remains unused
- `Mythos` on 5 GHz channel 36 at VHT80 and 2.4 GHz auto at HT20
- Finland regulatory domain and WPA2/WPA3 mixed mode

`firmware.nix` builds the official `tplink_archer-c6-v2` ImageBuilder profile
without optional packages because the device has only 8 MB of flash.
`config.nix` is the Dewclaw runtime configuration translated from the working
router capture.

## Build

Build these outputs on x86_64 Linux:

```bash
nix build .#hermes-firmware
nix build .#hermes-deploy
```

The firmware result contains factory and sysupgrade images. Since OpenWrt is
already installed, use only the `*-sysupgrade.bin` image for future upgrades.
Validate it on the device with `sysupgrade -T` before flashing. The image also
installs the personal SSH public key from `openwrt/files`; private keys never
enter the repository or Nix store.

## Wi-Fi secret prerequisite

The Wi-Fi password is deliberately absent from Git and the Nix store. Before
the first Dewclaw deployment, edit the encrypted secrets file:

```bash
sops secrets/openwrt.yaml
```

Add a top-level value named `openwrt_archer_wifi`. Do not put the password in a
Nix file, firmware overlay, shell history, or unencrypted capture.

Builds do not decrypt the secret. Deployment does, and fails before changing
the router if the key is missing:

```bash
nix run .#hermes-deploy
```

Keep a wired connection available for the first declarative deployment. The
script snapshots the overlay and reconnects after reboot before accepting the
new configuration.

## Deliberate omissions

The WAN port remains separate rather than becoming a fifth LAN port. AdGuard,
VLANs, guest Wi-Fi, roaming, statistics, and other services are deferred until
the flat network has remained stable. Those services belong on the R6220 or a
server, not this flash-constrained access point.
