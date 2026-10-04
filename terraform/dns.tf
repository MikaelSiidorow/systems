locals {
  account_id = "0d7cd4f74493972b3d64775916c9f6ed"
}

resource "cloudflare_zone" "draftkingdom_lol" {
  account = { id = local.account_id }
  name    = "draftkingdom.lol"
}

resource "cloudflare_zone" "m12w_me" {
  account = { id = local.account_id }
  name    = "m12w.me"
}

resource "cloudflare_zone" "miksu_app" {
  account = { id = local.account_id }
  name    = "miksu.app"
}

resource "cloudflare_zone" "miksu_link" {
  account = { id = local.account_id }
  name    = "miksu.link"
}

resource "cloudflare_zone" "pluck_pics" {
  account = { id = local.account_id }
  name    = "pluck.pics"
}

resource "cloudflare_zone" "siidorow_com" {
  account = { id = local.account_id }
  name    = "siidorow.com"
}

resource "cloudflare_zone" "siidorow_dev" {
  account = { id = local.account_id }
  name    = "siidorow.dev"
}

resource "cloudflare_zone" "sweepmail_app" {
  account = { id = local.account_id }
  name    = "sweepmail.app"
}

# =============================================================================
# siidorow.dev records
# =============================================================================

resource "cloudflare_dns_record" "siidorow_dev_root_a" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "A"
  name    = "siidorow.dev"
  content = "76.76.21.21"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_dev_www" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "CNAME"
  name    = "www.siidorow.dev"
  content = "cname.vercel-dns.com"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_dev_atproto" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "TXT"
  name    = "_atproto.siidorow.dev"
  content = "\"did=did:plc:7ajjqbub3qxysvscwvugeq5z\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_dev_dmarc" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "TXT"
  name    = "_dmarc.siidorow.dev"
  content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_dev_domainkey_wildcard" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "TXT"
  name    = "*._domainkey.siidorow.dev"
  content = "\"v=DKIM1; p=\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_dev_spf" {
  zone_id = cloudflare_zone.siidorow_dev.id
  type    = "TXT"
  name    = "siidorow.dev"
  content = "\"v=spf1 -all\""
  proxied = false
  ttl     = 1
}

# =============================================================================
# sweepmail.app records
# =============================================================================

resource "cloudflare_dns_record" "sweepmail_app_wildcard" {
  zone_id = cloudflare_zone.sweepmail_app.id
  type    = "CNAME"
  name    = "*.sweepmail.app"
  content = "pixie.porkbun.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "sweepmail_app_root" {
  zone_id = cloudflare_zone.sweepmail_app.id
  type    = "CNAME"
  name    = "sweepmail.app"
  content = "sweepmail.pages.dev"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "sweepmail_app_www" {
  zone_id = cloudflare_zone.sweepmail_app.id
  type    = "CNAME"
  name    = "www.sweepmail.app"
  content = "pixie.porkbun.com"
  proxied = true
  ttl     = 1
}

# =============================================================================
# m12w.me records
# =============================================================================

resource "cloudflare_dns_record" "m12w_me_atproto" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "_atproto.m12w.me"
  content = "\"did=did:plc:7ajjqbub3qxysvscwvugeq5z\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_dmarc" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "_dmarc.m12w.me"
  content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; rua=mailto:mikael@siidorow.com\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_domainkey_wildcard" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "*._domainkey.m12w.me"
  content = "\"v=DKIM1; p=\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_spf" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "m12w.me"
  content = "\"v=spf1 -all\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_verification" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "m.m12w.me"
  content = "\"sl-verification=dchtxgjtjvwawbdbogwuittnywteru\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_mx_1" {
  zone_id  = cloudflare_zone.m12w_me.id
  type     = "MX"
  name     = "m.m12w.me"
  content  = "mx1.simplelogin.co"
  proxied  = false
  ttl      = 1
  priority = 10
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_mx_2" {
  zone_id  = cloudflare_zone.m12w_me.id
  type     = "MX"
  name     = "m.m12w.me"
  content  = "mx2.simplelogin.co"
  proxied  = false
  ttl      = 1
  priority = 20
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_spf" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "m.m12w.me"
  content = "\"v=spf1 include:simplelogin.co ~all\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_dkim" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "CNAME"
  name    = "dkim._domainkey.m.m12w.me"
  content = "dkim._domainkey.simplelogin.co"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_dkim02" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "CNAME"
  name    = "dkim02._domainkey.m.m12w.me"
  content = "dkim02._domainkey.simplelogin.co"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_dkim03" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "CNAME"
  name    = "dkim03._domainkey.m.m12w.me"
  content = "dkim03._domainkey.simplelogin.co"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "m12w_me_simplelogin_dmarc" {
  zone_id = cloudflare_zone.m12w_me.id
  type    = "TXT"
  name    = "_dmarc.m.m12w.me"
  content = "\"v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s\""
  proxied = false
  ttl     = 1
}

# =============================================================================
# miksu.link records
# =============================================================================

resource "cloudflare_dns_record" "miksu_link_root_a" {
  zone_id = cloudflare_zone.miksu_link.id
  type    = "A"
  name    = "miksu.link"
  content = "76.76.21.21"
  proxied = false
  ttl     = 1
  comment = "Vercel root"
}

resource "cloudflare_dns_record" "miksu_link_www" {
  zone_id = cloudflare_zone.miksu_link.id
  type    = "CNAME"
  name    = "www.miksu.link"
  content = "cname.vercel-dns.com"
  proxied = false
  ttl     = 1
}

# =============================================================================
# miksu.app records
# =============================================================================

resource "cloudflare_dns_record" "miksu_app_headscale" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "hs.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "miksu_app_home_assistant" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "ha.miksu.app"
  content = "192.168.67.170"
  proxied = false
  ttl     = 1
  comment = "Private home address for LAN and Headscale subnet access"
}

resource "cloudflare_dns_record" "miksu_app_refinery" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "refinery.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "miksu_app_refinery_zero" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "refinery-zero.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = false
  ttl     = 1
  comment = "DNS-only for WebSocket support"
}

resource "cloudflare_dns_record" "miksu_app_brawl" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "brawl.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "miksu_app_status" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "status.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "miksu_app_wger" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "A"
  name    = "wger.miksu.app"
  content = hcloud_server.k3s_server.ipv4_address
  proxied = false
  ttl     = 1
  comment = "DNS-only for PowerSync long-lived connections"
}

# =============================================================================
# pluck.pics records
# =============================================================================

resource "cloudflare_dns_record" "pluck_pics_dmarc" {
  zone_id = cloudflare_zone.pluck_pics.id
  type    = "TXT"
  name    = "_dmarc.pluck.pics"
  content = "\"v=DMARC1; p=none; rua=mailto:1670034898de41e9aac244d3998aeb8e@dmarc-reports.cloudflare.net\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "pluck_pics_google_verification" {
  zone_id = cloudflare_zone.pluck_pics.id
  type    = "TXT"
  name    = "pluck.pics"
  content = "\"google-site-verification=Qu4l-Y6pyiEPtghS_3Y63R41v3CCwI717dXqlidaTbU\""
  proxied = false
  ttl     = 3600
}

resource "cloudflare_dns_record" "pluck_pics_spf" {
  zone_id = cloudflare_zone.pluck_pics.id
  type    = "TXT"
  name    = "pluck.pics"
  content = "\"v=spf1 include:_spf.mx.cloudflare.net ~all\""
  proxied = false
  ttl     = 1
}

# =============================================================================
# siidorow.com records
# =============================================================================

resource "cloudflare_dns_record" "siidorow_com_root_a" {
  zone_id = cloudflare_zone.siidorow_com.id
  type    = "A"
  name    = "siidorow.com"
  content = "76.76.21.21"
  proxied = false
  ttl     = 1
}

# CNAME records
resource "cloudflare_dns_record" "siidorow_com_www" {
  zone_id = cloudflare_zone.siidorow_com.id
  type    = "CNAME"
  name    = "www.siidorow.com"
  content = "cname.vercel-dns.com"
  proxied = false
  ttl     = 1
}

# MX records (Google Workspace)
resource "cloudflare_dns_record" "siidorow_com_mx_alt3" {
  zone_id  = cloudflare_zone.siidorow_com.id
  type     = "MX"
  name     = "siidorow.com"
  content  = "alt3.aspmx.l.google.com"
  proxied  = false
  ttl      = 3600
  priority = 10
}

resource "cloudflare_dns_record" "siidorow_com_mx_primary" {
  zone_id  = cloudflare_zone.siidorow_com.id
  type     = "MX"
  name     = "siidorow.com"
  content  = "aspmx.l.google.com"
  proxied  = false
  ttl      = 3600
  priority = 1
}

resource "cloudflare_dns_record" "siidorow_com_mx_alt4" {
  zone_id  = cloudflare_zone.siidorow_com.id
  type     = "MX"
  name     = "siidorow.com"
  content  = "alt4.aspmx.l.google.com"
  proxied  = false
  ttl      = 3600
  priority = 10
}

resource "cloudflare_dns_record" "siidorow_com_mx_alt1" {
  zone_id  = cloudflare_zone.siidorow_com.id
  type     = "MX"
  name     = "siidorow.com"
  content  = "alt1.aspmx.l.google.com"
  proxied  = false
  ttl      = 3600
  priority = 5
}

resource "cloudflare_dns_record" "siidorow_com_mx_alt2" {
  zone_id  = cloudflare_zone.siidorow_com.id
  type     = "MX"
  name     = "siidorow.com"
  content  = "alt2.aspmx.l.google.com"
  proxied  = false
  ttl      = 3600
  priority = 5
}

# TXT records

resource "cloudflare_dns_record" "siidorow_com_dmarc" {
  zone_id = cloudflare_zone.siidorow_com.id
  type    = "TXT"
  name    = "_dmarc.siidorow.com"
  content = "\"v=DMARC1; p=none; rua=mailto:bfc996ec26d74328985ccdce900879a8@dmarc-reports.cloudflare.net\""
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "siidorow_com_spf" {
  zone_id = cloudflare_zone.siidorow_com.id
  type    = "TXT"
  name    = "siidorow.com"
  content = "\"v=spf1 include:_spf.google.com -all\""
  proxied = false
  ttl     = 3600
}

resource "cloudflare_dns_record" "siidorow_com_google_verification" {
  zone_id = cloudflare_zone.siidorow_com.id
  type    = "TXT"
  name    = "siidorow.com"
  content = "\"google-site-verification=mse43FSKT_uszYVj1W6MpwXPs0DPfiXgol8lUgXWqAo\""
  proxied = false
  ttl     = 1
}
