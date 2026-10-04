locals {
  mail_domain = "notify.miksu.app"
  tem_mx_parts = regex(
    "^([0-9]+)\\s+(.+)$",
    scaleway_tem_domain.notifications.mx_config,
  )
}

resource "scaleway_tem_domain" "notifications" {
  name       = local.mail_domain
  accept_tos = true
}

resource "cloudflare_dns_record" "notifications_spf" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "TXT"
  name    = local.mail_domain
  content = scaleway_tem_domain.notifications.spf_value
  proxied = false
  ttl     = 300
  comment = "Scaleway TEM SPF for transactional notifications"
}

resource "cloudflare_dns_record" "notifications_dkim" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "TXT"
  name    = trimsuffix(scaleway_tem_domain.notifications.dkim_name, ".")
  content = scaleway_tem_domain.notifications.dkim_config
  proxied = false
  ttl     = 300
  comment = "Scaleway TEM DKIM for transactional notifications"
}

resource "cloudflare_dns_record" "notifications_dmarc" {
  zone_id = cloudflare_zone.miksu_app.id
  type    = "TXT"
  name    = trimsuffix(scaleway_tem_domain.notifications.dmarc_name, ".")
  content = scaleway_tem_domain.notifications.dmarc_config
  proxied = false
  ttl     = 300
  comment = "DMARC policy for transactional notifications"
}

resource "cloudflare_dns_record" "notifications_mx" {
  zone_id  = cloudflare_zone.miksu_app.id
  type     = "MX"
  name     = local.mail_domain
  content  = trimsuffix(local.tem_mx_parts[1], ".")
  priority = tonumber(local.tem_mx_parts[0])
  proxied  = false
  ttl      = 300
  comment  = "Scaleway TEM blackhole MX for transactional notifications"
}

resource "scaleway_tem_domain_validation" "notifications" {
  domain_id = scaleway_tem_domain.notifications.id
  timeout   = 300

  depends_on = [
    cloudflare_dns_record.notifications_spf,
    cloudflare_dns_record.notifications_dkim,
    cloudflare_dns_record.notifications_dmarc,
    cloudflare_dns_record.notifications_mx,
  ]
}

resource "scaleway_iam_application" "wger_smtp" {
  name        = "wger-smtp"
  description = "SMTP identity for wger transactional email"
}

resource "scaleway_iam_policy" "wger_smtp" {
  name           = "wger-smtp"
  description    = "Allow wger to send transactional email over SMTP"
  application_id = scaleway_iam_application.wger_smtp.id

  rule {
    project_ids          = [var.scaleway_project_id]
    permission_set_names = ["TransactionalEmailEmailSmtpCreate"]
  }
}

resource "time_rotating" "wger_smtp" {
  # Rotate before Scaleway's one-year organization limit leaves the key
  # unusable. The 65-day renewal buffer allows for delayed Terraform runs.
  rotation_days = 300
}

resource "scaleway_iam_api_key" "wger_smtp" {
  application_id = scaleway_iam_application.wger_smtp.id
  description    = "wger SMTP credential"
  expires_at     = timeadd(time_rotating.wger_smtp.rfc3339, "8760h")

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [scaleway_iam_policy.wger_smtp]
}
