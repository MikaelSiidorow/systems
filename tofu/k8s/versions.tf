terraform {
  required_version = "~> 1.11"

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
    use_lockfile                = true
    endpoints = {
      s3 = "https://0d7cd4f74493972b3d64775916c9f6ed.eu.r2.cloudflarestorage.com"
    }
  }

  # State and plan files are encrypted before they leave the machine. The
  # passphrase is TF_VAR_state_passphrase in infra/secrets/ci.yaml.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    # Lets the first apply read the still-plaintext state. Once both roots
    # have applied, remove it and set `enforced = true` on state and plan.
    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.state

      fallback {
        method = method.unencrypted.migrate
      }
    }

    plan {
      method = method.aes_gcm.state
    }

    # For the root state that mail.tf reads.
    remote_state_data_sources {
      default {
        method = method.aes_gcm.state

        fallback {
          method = method.unencrypted.migrate
        }
      }
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
