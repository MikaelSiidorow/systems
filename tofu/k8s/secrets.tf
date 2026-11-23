# Managed by Flux (k8s/cert-manager/cloudflare-api-token.sops.yaml).
removed {
  from = kubernetes_secret_v1.cloudflare_api_token

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/monitoring/grafana-admin.sops.yaml).
removed {
  from = kubernetes_secret_v1.grafana_admin

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/monitoring/alertmanager-telegram-token.sops.yaml).
removed {
  from = kubernetes_secret_v1.alertmanager_telegram_token

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/gatus/gatus-telegram-token.sops.yaml).
removed {
  from = kubernetes_secret_v1.gatus_telegram_token

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/refinery/refinery-secrets.sops.yaml).
removed {
  from = kubernetes_secret_v1.refinery_secrets

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/namespace.yaml).
removed {
  from = kubernetes_namespace_v1.wger

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/db.yaml).
removed {
  from = kubernetes_service_v1.wger_db

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/db.yaml).
removed {
  from = kubernetes_endpoints_v1.wger_db

  lifecycle {
    destroy = false
  }
}

# No longer generated; its value is in k8s/wger/wger-admin-bootstrap.sops.yaml.
removed {
  from = random_password.wger_admin

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/wger-admin-bootstrap.sops.yaml).
removed {
  from = kubernetes_secret_v1.wger_admin_bootstrap

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/wger-secrets.sops.yaml).
removed {
  from = kubernetes_secret_v1.wger_secrets

  lifecycle {
    destroy = false
  }
}

# Managed by Flux (k8s/wger/wger-email.sops.yaml).
removed {
  from = kubernetes_secret_v1.wger_email

  lifecycle {
    destroy = false
  }
}
