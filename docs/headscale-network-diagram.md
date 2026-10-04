# Headscale Network Architecture

## Infrastructure Overview

```mermaid
graph TB
    subgraph Internet
        CLIENT_A[VPN Client A<br/>Laptop / Phone]
        CLIENT_B[VPN Client B<br/>Other Device]
        CF[Cloudflare DNS<br/>hs.miksu.app → 89.167.124.71]
    end

    subgraph Hetzner Cloud
        subgraph Firewall["Hetzner Firewall"]
            FW_443[TCP 443 HTTPS]
            FW_80[TCP 80 HTTP]
            FW_3478[UDP 3478 STUN]
            FW_22[TCP 22 SSH]
        end

        subgraph Server["k3s-server (cx33 · Helsinki)<br/>89.167.124.71"]
            subgraph K8s["Kubernetes (K3s)"]
                TRAEFIK["Traefik Ingress<br/>hostPort 80/443<br/>TLS termination"]
                CERTMGR["cert-manager<br/>Let's Encrypt"]
                INGRESS["Ingress: hs.miksu.app"]
                SVC["K8s Service: headscale:8080"]
                EP["EndpointSlice → 10.42.0.1"]
                ARGOCD["ArgoCD<br/>argocd.miksu.app<br/>100.64.0.1 only"]
            end

            subgraph NixOS["NixOS Host Services"]
                HS["Headscale<br/>0.0.0.0:8080"]
                DERP["Embedded DERP Server<br/>region 999"]
                STUN["STUN Server<br/>0.0.0.0:3478"]
                TS["Tailscale Client<br/>tailscale0 interface"]
            end
        end
    end

    subgraph Tailscale Network ["Tailscale VPN (100.64.0.0/10)"]
        TS_SERVER["Server: 100.64.0.1"]
        TS_CLIENT_A["Client A: 100.64.0.x"]
        TS_CLIENT_B["Client B: 100.64.0.y"]
    end

    CLIENT_A -->|DNS lookup| CF
    CLIENT_B -->|DNS lookup| CF
    CF -->|A record| FW_443
    FW_443 --> TRAEFIK
    FW_80 --> TRAEFIK
    FW_3478 --> STUN
    TRAEFIK --> INGRESS
    INGRESS --> SVC
    SVC --> EP
    EP --> HS
    CERTMGR -->|TLS cert| INGRESS
    HS --- DERP
    HS --- STUN
    HS --- TS

    TS --- TS_SERVER
    CLIENT_A -.- TS_CLIENT_A
    CLIENT_B -.- TS_CLIENT_B
    TS_CLIENT_A <-->|WireGuard| TS_CLIENT_B
    TS_CLIENT_A <-->|WireGuard| TS_SERVER
    TS_SERVER --> ARGOCD
```

## HTTPS Control Plane Flow

Client registration, key exchange, and coordination all happen over HTTPS.

```mermaid
flowchart TD
    START([VPN Client starts]) --> DNS[Resolve hs.miksu.app<br/>via Cloudflare DNS]
    DNS --> CONNECT[Connect to 89.167.124.71:443<br/>TLS handshake]

    CONNECT --> HFW{Hetzner Firewall<br/>TCP 443}
    HFW -->|Allowed| TRAEFIK[Traefik Ingress Controller<br/>hostPort 443]
    HFW -->|Blocked| REJECT([Connection refused])

    TRAEFIK --> TLS[TLS Termination<br/>cert: headscale-tls<br/>Let's Encrypt]
    TLS --> MATCH[Host match: hs.miksu.app]
    MATCH --> K8S_SVC[K8s Service: headscale:8080]
    K8S_SVC --> ENDPOINT[EndpointSlice<br/>10.42.0.1:8080]
    ENDPOINT --> HEADSCALE[NixOS Headscale Service<br/>0.0.0.0:8080]

    HEADSCALE --> AUTH{Client<br/>authenticated?}
    AUTH -->|Pre-authorized key<br/>or approved| REGISTER[Register node<br/>Assign IP from 100.64.0.0/10]
    AUTH -->|Not approved| DENY([Registration denied])

    REGISTER --> PEERLIST[Distribute peer list<br/>+ WireGuard public keys]
    PEERLIST --> DNSCONFIG[Push DNS config<br/>MagicDNS: *.vpn.miksu.app<br/>Extra: argocd.miksu.app → 100.64.0.1]
    DNSCONFIG --> DERP_MAP[Push DERP map<br/>Region 999: hs.miksu.app]
    DERP_MAP --> CONNECTED([Client connected to control plane])

    style START fill:#4a9eff,color:#fff
    style CONNECTED fill:#2ecc71,color:#fff
    style REJECT fill:#e74c3c,color:#fff
    style DENY fill:#e74c3c,color:#fff
```

## WireGuard Connection Flow

After control plane registration, clients establish WireGuard tunnels.

```mermaid
flowchart TD
    START([Client registered with Headscale]) --> PEERS[Receive peer list<br/>+ WireGuard public keys<br/>+ DERP map]

    PEERS --> STUN_REQ[STUN request to<br/>89.167.124.71:3478 UDP]
    STUN_REQ --> HFW{Hetzner Firewall<br/>UDP 3478}
    HFW -->|Allowed| STUN_SRV[Headscale STUN Server<br/>0.0.0.0:3478]
    STUN_SRV --> DISCOVER[Discover own public IP<br/>and NAT type]

    DISCOVER --> ATTEMPT{Attempt direct<br/>WireGuard connection<br/>to peer}
    ATTEMPT -->|NAT allows<br/>hole punching| DIRECT[Direct WireGuard Tunnel<br/>Client A ↔ Client B<br/>UDP peer-to-peer]
    DIRECT --> P2P([Direct P2P tunnel established])

    ATTEMPT -->|NAT blocks<br/>direct connection| DERP_CONNECT[Connect to DERP relay<br/>hs.miksu.app:443<br/>via Traefik → Headscale]

    DERP_CONNECT --> RELAY[DERP Relay<br/>Region 999 · Embedded<br/>Headscale server]
    RELAY --> RELAYED([Traffic relayed via DERP])

    RELAYED -.->|Periodically retry<br/>direct connection| ATTEMPT

    style START fill:#4a9eff,color:#fff
    style P2P fill:#2ecc71,color:#fff
    style RELAYED fill:#f39c12,color:#fff
```

## Client-to-ArgoCD Access Flow

ArgoCD is only reachable through the Tailscale VPN (no public DNS record).

```mermaid
flowchart LR
    CLIENT[VPN Client] -->|Query argocd.miksu.app| TS_DNS[Tailscale DNS<br/>intercepted locally]
    TS_DNS -->|MagicDNS lookup| HS_DNS[Headscale DNS<br/>extra_records]
    HS_DNS -->|100.64.0.1| RESOLVE[Resolved to<br/>Tailscale IP]
    RESOLVE -->|WireGuard tunnel<br/>to 100.64.0.1| SERVER[K3s Server<br/>tailscale0 interface]
    SERVER -->|Local traffic| ARGOCD[ArgoCD<br/>Internal K8s service]

    style CLIENT fill:#4a9eff,color:#fff
    style ARGOCD fill:#2ecc71,color:#fff
```

## Network Layers Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PUBLIC INTERNET                             │
│  Clients ──DNS──▶ Cloudflare ──▶ 89.167.124.71                     │
├─────────────────────────────────────────────────────────────────────┤
│                      HETZNER FIREWALL                               │
│  TCP 22 (SSH) │ TCP 80/443 (HTTP/S) │ UDP 3478 (STUN)             │
├─────────────────────────────────────────────────────────────────────┤
│                     KUBERNETES (K3s)                                │
│  Traefik (hostPort) ──▶ Ingress ──▶ Service ──▶ EndpointSlice     │
│  cert-manager (Let's Encrypt TLS)                                  │
│  Pod CIDR: 10.42.0.0/16  │  Service CIDR: 10.43.0.0/16           │
├─────────────────────────────────────────────────────────────────────┤
│                      NixOS HOST                                     │
│  Headscale (0.0.0.0:8080)  │  DERP (embedded)  │  STUN (:3478)   │
│  Tailscale client (tailscale0, trustedInterface)                   │
├─────────────────────────────────────────────────────────────────────┤
│                    TAILSCALE VPN OVERLAY                            │
│  CGNAT: 100.64.0.0/10  │  IPv6: fd7a:115c:a1e0::/48              │
│  MagicDNS: *.vpn.miksu.app                                        │
│  Server: 100.64.0.1  │  Clients: 100.64.0.x                      │
│  ArgoCD reachable at argocd.miksu.app → 100.64.0.1                │
└─────────────────────────────────────────────────────────────────────┘
```

## Port Reference

| Port  | Protocol | Purpose                                                              | Source       |
| ----- | -------- | -------------------------------------------------------------------- | ------------ |
| 443   | TCP      | HTTPS — Traefik ingress, TLS termination, control plane + DERP relay | Public       |
| 80    | TCP      | HTTP — Redirected to HTTPS by Traefik                                | Public       |
| 3478  | UDP      | STUN — NAT discovery for WireGuard hole punching                     | Public       |
| 8080  | TCP      | Headscale HTTP — internal only, behind Traefik                       | K8s internal |
| 41641 | UDP      | WireGuard — direct peer-to-peer tunnels                              | Peer-to-peer |
