locals {
  scaleway_billing_alert_thresholds = toset(["50", "80", "100"])
}

# Provider 2.80 maps consumption_limit directly to the API's whole currency units.
resource "scaleway_billing_budget" "organization" {
  organization_id   = var.scaleway_organization_id
  consumption_limit = 1
  enabled           = true
}

resource "scaleway_billing_budget_alert" "organization" {
  for_each = local.scaleway_billing_alert_thresholds

  budget_id = scaleway_billing_budget.organization.id
  threshold = tonumber(each.value)
}

resource "scaleway_billing_budget_alert_notification" "email" {
  for_each = local.scaleway_billing_alert_thresholds

  budget_alert_id = scaleway_billing_budget_alert.organization[each.key].id
  email_addresses = [var.scaleway_billing_alert_email]
}
