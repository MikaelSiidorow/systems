# K3s server outputs
output "k3s_ipv4_address" {
  description = "K3s server public IPv4 address"
  value       = hcloud_server.k3s_server.ipv4_address
}

output "k3s_server_id" {
  value = hcloud_server.k3s_server.id
}

output "k3s_ssh_host" {
  value = "root@${hcloud_server.k3s_server.ipv4_address}"
}

output "wger_email" {
  description = "SMTP settings projected into the wger-email Kubernetes Secret."
  sensitive   = true
  # Keep the handoff atomic during a partial apply: until the API key exists,
  # the whole output is unknown instead of exposing a partially known map.
  value = scaleway_iam_api_key.wger_smtp.id != "" ? {
    ENABLE_EMAIL        = "True"
    EMAIL_HOST          = scaleway_tem_domain.notifications.smtp_host
    EMAIL_PORT          = tostring(scaleway_tem_domain.notifications.smtp_port)
    EMAIL_HOST_USER     = scaleway_tem_domain.notifications.smtps_auth_user
    EMAIL_HOST_PASSWORD = scaleway_iam_api_key.wger_smtp.secret_key
    EMAIL_USE_TLS       = "True"
    EMAIL_USE_SSL       = "False"
    FROM_EMAIL          = "wger <wger@${local.mail_domain}>"
  } : null

  depends_on = [scaleway_tem_domain_validation.notifications]
}
