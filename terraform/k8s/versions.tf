terraform {
  required_version = "~> 1.12"

  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "k8s/terraform.tfstate"
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

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
