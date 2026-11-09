provider "hcloud" {}

provider "cloudflare" {}

provider "scaleway" {
  organization_id = var.scaleway_organization_id
  project_id      = var.scaleway_project_id
  region          = "fr-par"
}
