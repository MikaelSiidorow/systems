# Hestia

Hestia is the home server at `192.168.67.170`. It joins the Headscale tailnet
and advertises the home LAN as a Tailscale subnet router. This makes devices
that cannot run Tailscale themselves, including the OpenWrt routers, reachable
without exposing management ports to the internet.

## Enroll Hestia

The NixOS configuration enables `tailscaled`, IP forwarding, the Tailscale UDP
firewall port, and advertisement of `192.168.67.0/24`. Enrollment remains an
intentional one-time operation so a reusable Headscale pre-auth key does not
need to live in this repository.

After the first NixOS activation, enroll the node against the existing
Headscale control server:

```bash
sudo tailscale up \
  --login-server=https://hs.miksu.app \
  --advertise-routes=192.168.67.0/24
```

Complete the registration using the instructions printed by the command. The
node state persists in `/var/lib/tailscale`; later NixOS activations keep the
route advertisement in sync through `services.tailscale.extraSetFlags`.

## Approve the route

Hestia's route announcement does not make the subnet available by itself.
Headscale keeps advertised routes disabled until an administrator approves
them. This approval is runtime state in Headscale's database on the Hetzner VM;
it does not require an infra repository change for the initial test.

On the Headscale server, find Hestia and approve only its home-LAN route:

```bash
headscale nodes list-routes
headscale nodes approve-routes \
  --identifier <HESTIA_NODE_ID> \
  --routes 192.168.67.0/24
```

Linux clients must opt in to subnet routes once:

```bash
sudo tailscale set --accept-routes=true
```

Verify from a remote tailnet client before adding split DNS:

```bash
ping 192.168.67.170
ssh root@192.168.67.1
ssh root@192.168.67.2
```

Router SSH remains LAN-only. Tailscale traffic reaches it through Hestia with
the subnet router's default source NAT, so the OpenWrt routers need no WAN
firewall openings or return routes.

## Headscale integration

After the subnet route works, configure Headscale split DNS for `home.arpa`
through Cerberus at `192.168.67.1`. Then remote clients can use:

```text
cerberus.home.arpa
hermes.home.arpa
hestia.home.arpa
```

Keep Mullvad DoH as the global resolver; only `home.arpa` should use the split
DNS route. Restrict access to the advertised subnet with Headscale policy
grants before treating the setup as complete.

## OpenWrt deployment

The Cerberus and Hermes OpenWrt configurations live in this repository. Router
deployment runs from Hestia's `/etc/nixos-repo` checkout and uses the
SOPS-managed `router-deploy-ssh-key` provided by this Hestia configuration.

## Local reverse proxy

Caddy gives the two local web interfaces memorable HTTP addresses and proxies
them over loopback to their native ports:

```text
https://ha.miksu.app      -> 127.0.0.1:8123
http://ha.home.arpa      -> 127.0.0.1:8123
http://zigbee.home.arpa  -> 127.0.0.1:8080
```

The `ha.miksu.app` certificate is issued by Let's Encrypt with a Cloudflare
DNS-01 challenge. The DNS name resolves to Hestia's private LAN address, so it
works directly at home and through the advertised Headscale subnet without
making Home Assistant reachable from the public Internet. Cerberus also serves
the same private answer locally for clients using DHCP DNS.

Store a Cloudflare API token with `Zone / DNS / Edit` and `Zone / Zone / Read`
permissions scoped only to `miksu.app` in the `cloudflare-dns-api-token` key of
`secrets/hestia.yaml`. NixOS passes it to the ACME client through a systemd
credential file; it is not placed in the Nix store or Caddy configuration.

Home Assistant 2026.8 and newer stores its HTTP server configuration in
`.storage` and ignores `http:` in `configuration.yaml` after the one-time YAML
migration. Configure **Trust X-Forwarded-For** and the trusted proxy
`127.0.0.1/32` under **Settings -> System -> Network**. Confirm the trial
configuration before its five-minute rollback timer expires.

Ports 8123 and 8080 deliberately remain open during the initial rollout. Once
the proxy works from every required client, bind both upstream services to
loopback and remove those ports from the LAN firewall.

After HTTPS works, configure the Home Assistant app with
`http://ha.home.arpa` as its internal URL and `https://ha.miksu.app` as its
external URL. Keep Tailscale enabled when using the external URL away from
home. Chromecast devices on the home LAN use the public hostname with its
private address and do not need Tailscale.
