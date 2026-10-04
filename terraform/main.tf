data "hcloud_ssh_key" "this" {
  name = "mikaelsiidorow@pop-os"
}

# =============================================================================
# K3s Server (NixOS)
# =============================================================================

resource "hcloud_firewall" "k3s" {
  name = "k3s-fw"

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # STUN (Headscale DERP)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "k3s_server" {
  name        = "k3s-server"
  server_type = "cx33"      # 4 vCPU / 8GB RAM / 80GB (shared)
  image       = "debian-12" # Will be replaced with NixOS via nixos-anywhere
  location    = "hel1"
  ssh_keys    = [data.hcloud_ssh_key.this.id]

  firewall_ids = [hcloud_firewall.k3s.id]

  lifecycle {
    ignore_changes = [image] # Image changes after nixos-anywhere install
  }
}

resource "cloudflare_r2_bucket" "terraform_state" {
  account_id   = "0d7cd4f74493972b3d64775916c9f6ed"
  name         = "terraform-state"
  jurisdiction = "eu"
}
