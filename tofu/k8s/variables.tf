variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase that encrypts the OpenTofu state and plan files."
}
