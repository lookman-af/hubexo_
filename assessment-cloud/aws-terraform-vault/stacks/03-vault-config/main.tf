terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers { vault = { source = "hashicorp/vault", version = "~> 5.0" } }
  backend "s3" {}
}
variable "vault_address" { type = string }
variable "vault_ca_cert_file" { type = string }
variable "environment" { type = string }
variable "application" { type = string }
provider "vault" {
  address          = var.vault_address
  ca_cert_file     = var.vault_ca_cert_file
  skip_child_token = true
  # Short-lived scoped VAULT_TOKEN supplied by a trusted runtime; never a tfvar.
}
resource "vault_mount" "applications" {
  path    = "applications"
  type    = "kv"
  options = { version = "2" }
  lifecycle { prevent_destroy = true }
}
resource "vault_audit" "stdout" {
  type    = "file"
  path    = "stdout"
  options = { file_path = "stdout", log_raw = "false" }
  lifecycle { prevent_destroy = true }
}
resource "vault_auth_backend" "kubernetes" { type = "kubernetes" }
resource "vault_kubernetes_auth_backend_config" "this" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc:443"
  # Vault runs in this cluster and reads its rotating local SA token and CA.
  # Its service account receives TokenReview access through authDelegator.
  disable_local_ca_jwt = false
}
resource "vault_policy" "application" {
  name   = "${var.application}-${var.environment}-read"
  policy = <<-HCL
    path "applications/data/${var.environment}/${var.application}/config" {
      capabilities = ["read"]
    }
  HCL
}
resource "vault_kubernetes_auth_backend_role" "application" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "${var.application}-${var.environment}"
  bound_service_account_names      = [var.application]
  bound_service_account_namespaces = [var.application]
  audience                         = "vault"
  token_policies                   = [vault_policy.application.name]
  token_ttl                        = 900
  token_max_ttl                    = 3600
  depends_on                       = [vault_kubernetes_auth_backend_config.this]
}
resource "vault_policy" "metrics" {
  name   = "metrics-read"
  policy = <<-HCL
    path "sys/metrics" { capabilities = ["read"] }
  HCL
}
output "application_role" { value = vault_kubernetes_auth_backend_role.application.role_name }
