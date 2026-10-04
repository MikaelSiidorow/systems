variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "refinery_postgres_password" {
  type      = string
  sensitive = true
}

variable "refinery_encryption_key" {
  type      = string
  sensitive = true
}

variable "refinery_github_client_secret" {
  type      = string
  sensitive = true
}

variable "refinery_linkedin_client_secret" {
  type      = string
  sensitive = true
}

variable "refinery_zero_admin_password" {
  type      = string
  sensitive = true
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "brawl_stars_api_key" {
  type      = string
  sensitive = true

  validation {
    condition     = length(trimspace(var.brawl_stars_api_key)) > 0
    error_message = "brawl_stars_api_key must be set."
  }
}

variable "wger_postgres_password" {
  type      = string
  sensitive = true

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{32,}$", var.wger_postgres_password))
    error_message = "wger_postgres_password must be at least 32 URL-safe characters."
  }
}

variable "wger_powersync_password" {
  type      = string
  sensitive = true

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{32,}$", var.wger_powersync_password))
    error_message = "wger_powersync_password must be at least 32 URL-safe characters."
  }
}

variable "wger_secret_key" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.wger_secret_key) >= 50
    error_message = "wger_secret_key must be at least 50 characters."
  }
}

variable "wger_jwt_public_key" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.wger_jwt_public_key) > 100
    error_message = "wger_jwt_public_key must be set to the generated public JWK."
  }
}

variable "wger_jwt_private_key" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.wger_jwt_private_key) > 100
    error_message = "wger_jwt_private_key must be set to the generated private JWK."
  }
}
