variable "scaleway_organization_id" {
  type        = string
  description = "Scaleway organization that owns the transactional email project."

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.scaleway_organization_id))
    error_message = "scaleway_organization_id must be a UUID."
  }
}

variable "scaleway_project_id" {
  type        = string
  description = "Scaleway project used for transactional email."

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.scaleway_project_id))
    error_message = "scaleway_project_id must be a UUID."
  }
}

variable "scaleway_billing_alert_email" {
  type        = string
  description = "Email address notified when Scaleway organization spending crosses a budget threshold."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.scaleway_billing_alert_email))
    error_message = "scaleway_billing_alert_email must be an email address."
  }
}
