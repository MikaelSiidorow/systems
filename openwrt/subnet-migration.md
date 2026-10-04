# Home LAN subnet migration

This runbook moves the flat home LAN from `192.168.1.0/24` to
`192.168.67.0/24` without asking Dewclaw to reconnect to a router at a
different address than the one used to start the deployment.

The final addresses are:

| Host     | Address          |
| -------- | ---------------- |
| Cerberus | `192.168.67.1`   |
| Hermes   | `192.168.67.2`   |
| Hestia   | `192.168.67.170` |

Do this while physically at home. Keep the older Ethernet laptop and a known
good cable available. Before changing anything, create fresh OpenWrt backups
of both routers and confirm that Hestia can use its dedicated deployment key
to reach both of them.

## 1. Build and review

From the subnet-migration branch on an x86_64 Linux machine:

```bash
make check
nix build .#cerberus-deploy .#hermes-deploy --no-link
```

Push the reviewed branch before asking Hestia to run it.

Hestia's detached user services must survive the SSH session that launches
them. Enable lingering temporarily:

```bash
ssh -t mikaelsiidorow@192.168.1.170 \
  'sudo loginctl enable-linger mikaelsiidorow'
```

## 2. Add temporary addresses

These commands change only live kernel state. They do not alter UCI or survive
a reboot:

```bash
ssh root@192.168.1.1 \
  'ip address show dev br-lan | grep -q "inet 192.168.67.1/24" || ip address add 192.168.67.1/24 dev br-lan'
ssh root@192.168.1.2 \
  'ip address show dev br-lan | grep -q "inet 192.168.67.2/24" || ip address add 192.168.67.2/24 dev br-lan'
ssh -t mikaelsiidorow@192.168.1.170 \
  'ip address show dev enp31s0 | grep -q "inet 192.168.67.254/24" || sudo ip address add 192.168.67.254/24 dev enp31s0'
```

Use `.254`, which is outside the DHCP pool, only as Hestia's temporary
migration address; `.170` remains its DHCP reservation. Verify from Hestia that
both new router addresses answer and accept its dedicated key:

```bash
ssh mikaelsiidorow@192.168.1.170
ping -c 2 192.168.67.1
ping -c 2 192.168.67.2
ssh -i ~/.ssh/id_ed25519_router_deploy root@192.168.67.1 true
ssh -i ~/.ssh/id_ed25519_router_deploy root@192.168.67.2 true
```

Stop if any check fails. The old network is still authoritative at this point.

## 3. Deploy Hermes from Hestia

Run the Hermes deployment as a detached process on Hestia. It must use the new
target address, its dedicated router SSH key, and a temporary SOPS age key.
Keep that age key in Hestia's RAM-backed runtime directory and remove it when
the process exits. Inspect the complete service journal before continuing.

Hermes will reboot onto `192.168.67.2`. Wi-Fi clients still use the old DHCP
subnet until Cerberus is migrated, but Hermes continues bridging their traffic.

## 4. Deploy Cerberus from Hestia

Run the Cerberus deployment as a detached process on Hestia using the dedicated
router SSH key. No SOPS key is needed for Cerberus. The process connects to the
temporary `192.168.67.1` address; the declarative configuration makes that
address permanent across the reboot. Hestia's temporary `.254` address keeps
the confirmation path alive while DHCP changes underneath it.

This is the cutover. Wi-Fi and internet access will disappear briefly. Do not
interrupt power while Cerberus is rebooting or while Dewclaw may still roll
back.

## 5. Renew clients and clean up

Reconnect Wi-Fi clients so they obtain `192.168.67.x` leases. On Hestia, renew
the Ethernet lease and confirm that the reservation supplied `.170` before
removing the temporary address:

```bash
sudo networkctl renew enp31s0
ip -brief address show dev enp31s0
sudo ip address del 192.168.67.254/24 dev enp31s0
```

Verify the final network from a client and from Hestia:

```bash
getent hosts cerberus.home.arpa hermes.home.arpa hestia.home.arpa
ping -c 2 192.168.67.1
ping -c 2 192.168.67.2
curl --fail --max-time 10 https://example.com >/dev/null
```

Also confirm Mullvad DNS, hardware flow offloading, both Mythos radios, and the
absence of `/overlay/upper.prev`, `/overlay/upper.dead`, and
`/etc/init.d/config_generation` on each router.

After all validation is complete, return Hestia's user-manager policy to its
previous state:

```bash
sudo loginctl disable-linger mikaelsiidorow
```

## Recovery

If a declarative deployment cannot confirm connectivity, wait for Dewclaw's
rollback timer and reboot before intervening. The temporary router addresses
disappear on reboot.

For manual recovery, connect the Ethernet laptop directly to a Cerberus LAN
port and use a static address in the router's active subnet, such as
`192.168.1.10/24` before cutover or `192.168.67.10/24` afterward. Restore the
fresh OpenWrt backup only if the automatic rollback did not return a usable
configuration.
