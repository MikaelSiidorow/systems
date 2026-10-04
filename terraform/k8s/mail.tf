data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket                      = "terraform-state"
    key                         = "terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    endpoints = {
      s3 = "https://0d7cd4f74493972b3d64775916c9f6ed.eu.r2.cloudflarestorage.com"
    }
  }
}

locals {
  wger_email = try(data.terraform_remote_state.infrastructure.outputs.wger_email, null)
}

resource "kubernetes_secret_v1" "wger_email" {
  count = local.wger_email == null ? 0 : 1

  metadata {
    name      = "wger-email"
    namespace = kubernetes_namespace_v1.wger.metadata[0].name
  }

  data = local.wger_email
}
