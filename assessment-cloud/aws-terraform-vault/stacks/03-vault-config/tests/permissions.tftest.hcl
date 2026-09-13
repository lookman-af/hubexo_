mock_provider "vault" {}

variables {
  vault_address      = "https://vault.example.invalid:8200"
  vault_ca_cert_file = "/unused-public-ca.pem"
  environment        = "prod"
  application        = "orders"
}
run "exact_application_scope" {
  command = plan
  assert {
    condition     = vault_kubernetes_auth_backend_role.application.audience == "vault" && vault_kubernetes_auth_backend_role.application.token_max_ttl == 3600
    error_message = "Workload tokens require the explicit audience and bounded maximum lifetime."
  }
  assert {
    condition     = vault_kubernetes_auth_backend_role.application.bound_service_account_names == toset(["orders"]) && vault_kubernetes_auth_backend_role.application.bound_service_account_namespaces == toset(["orders"])
    error_message = "Application identity must be bound to an exact service account and namespace."
  }
  assert {
    condition     = strcontains(vault_policy.application.policy, "applications/data/prod/orders/config") && !strcontains(vault_policy.application.policy, "*") && !strcontains(vault_policy.application.policy, "write")
    error_message = "The application may read only its exact secret path."
  }
  assert {
    condition     = vault_audit.stdout.options["log_raw"] == "false"
    error_message = "Audit configuration must not record raw secret values."
  }
}
