resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_api_token
  }
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = "monitoring"
  }

  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password
  }
}

resource "kubernetes_secret_v1" "alertmanager_telegram_token" {
  metadata {
    name      = "alertmanager-telegram-token"
    namespace = "monitoring"
  }

  data = {
    bot-token = var.telegram_bot_token
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

resource "kubernetes_namespace_v1" "wger" {
  metadata {
    name = "wger"
  }

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = kubernetes_namespace_v1.wger
  id = "wger"
}

resource "kubernetes_service_v1" "wger_db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace_v1.wger.metadata[0].name
  }

  spec {
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_endpoints_v1" "wger_db" {
  metadata {
    name      = kubernetes_service_v1.wger_db.metadata[0].name
    namespace = kubernetes_namespace_v1.wger.metadata[0].name
  }

  subset {
    address {
      ip = "10.42.0.1"
    }

    port {
      port = 5432
    }
  }
}

resource "random_password" "wger_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "wger_admin_bootstrap" {
  metadata {
    name      = "wger-admin-bootstrap"
    namespace = kubernetes_namespace_v1.wger.metadata[0].name
  }

  data = {
    ADMIN_PASSWORD = random_password.wger_admin.result
  }
}

resource "kubernetes_secret_v1" "wger_secrets" {
  metadata {
    name      = "wger-secrets"
    namespace = kubernetes_namespace_v1.wger.metadata[0].name
  }

  data = {
    SECRET_KEY        = var.wger_secret_key
    JWT_PUBLIC_KEY    = var.wger_jwt_public_key
    JWT_PRIVATE_KEY   = var.wger_jwt_private_key
    PS_DATABASE_URI   = "postgresql://wger:${urlencode(var.wger_postgres_password)}@db:5432/wger"
    PS_STORAGE_PG_URI = "postgresql://powersync_storage:${urlencode(var.wger_powersync_password)}@db:5432/wger"
  }
}
