terraform {
  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
}
variable "region" { type = string }
variable "unseal_key_arn" { type = string }
variable "vault_role_arn" { type = string }
variable "vault_tls_secret_name" { type = string }
variable "application_namespace" { type = string }
variable "vault_ca_pem" {
  type        = string
  description = "Public CA certificate only. Never a private key."
}

resource "kubernetes_namespace_v1" "application" {
  metadata {
    name = var.application_namespace
    labels = {
      "vault-injection"                    = "enabled"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}
resource "kubernetes_secret_v1" "client_ca" {
  metadata {
    name      = "vault-client-ca"
    namespace = kubernetes_namespace_v1.application.metadata[0].name
  }
  # This certificate is public trust material, not a secret/private key.
  data = { "ca.crt" = var.vault_ca_pem }
}

resource "kubernetes_namespace_v1" "vault" {
  metadata {
    name   = "vault"
    labels = { "pod-security.kubernetes.io/enforce" = "baseline" }
  }
}
resource "kubernetes_storage_class_v1" "vault" {
  metadata { name = "vault-gp3-retain" }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters             = { type = "gp3", encrypted = "true", fsType = "ext4" }
}

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = kubernetes_namespace_v1.vault.metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.34.1"
  # A brand-new Vault needs a controlled initialization ceremony before readiness.
  # A separate deployment gate checks initialization, unseal, and Raft health.
  wait   = false
  atomic = false
  values = [yamlencode({
    global = { tlsDisable = false }
    injector = {
      enabled  = true
      replicas = 2
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      webhook = {
        failurePolicy     = "Fail"
        namespaceSelector = { matchLabels = { "vault-injection" = "enabled" } }
      }
      image      = { repository = "hashicorp/vault-k8s", tag = "1.7.6" }
      agentImage = { repository = "hashicorp/vault", tag = "2.0.4" }
    }
    server = {
      image = { repository = "hashicorp/vault", tag = "2.0.4" }
      serviceAccount = {
        create      = true
        name        = "vault"
        annotations = { "eks.amazonaws.com/role-arn" = var.vault_role_arn }
      }
      authDelegator      = { enabled = true }
      updateStrategyType = "OnDelete"
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      nodeSelector = { "platform-baseline" = "true" }
      affinity = yamlencode({
        podAntiAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = [{
            topologyKey = "topology.kubernetes.io/zone"
            labelSelector = { matchLabels = {
              "app.kubernetes.io/name" = "vault", "app.kubernetes.io/instance" = "vault", component = "server"
            } }
          }]
        }
      })
      dataStorage = { enabled = true, size = "20Gi", storageClass = kubernetes_storage_class_v1.vault.metadata[0].name }
      standalone  = { enabled = false }
      extraEnvironmentVars = {
        VAULT_CACERT               = "/vault/userconfig/tls/ca.crt"
        VAULT_TLS_SERVER_NAME      = "vault.vault.svc"
        AWS_STS_REGIONAL_ENDPOINTS = "regional"
      }
      volumes      = [{ name = "tls", secret = { secretName = var.vault_tls_secret_name } }]
      volumeMounts = [{ name = "tls", mountPath = "/vault/userconfig/tls", readOnly = true }]
      ha = {
        enabled          = true
        replicas         = 3
        apiAddr          = "https://vault-active.vault.svc:8200"
        disruptionBudget = { enabled = true, maxUnavailable = 1 }
        raft = {
          enabled   = true
          setNodeId = true
          config    = <<-HCL
            ui = false
            disable_mlock = true
            api_addr = "https://vault-active.vault.svc:8200"
            listener "tcp" {
              address = "[::]:8200"
              cluster_address = "[::]:8201"
              tls_cert_file = "/vault/userconfig/tls/tls.crt"
              tls_key_file = "/vault/userconfig/tls/tls.key"
              tls_min_version = "tls12"
            }
            storage "raft" {
              path = "/vault/data"
              retry_join {
                leader_api_addr = "https://vault-0.vault-internal.vault.svc:8200"
                leader_ca_cert_file = "/vault/userconfig/tls/ca.crt"
                leader_tls_servername = "vault.vault.svc"
              }
              retry_join {
                leader_api_addr = "https://vault-1.vault-internal.vault.svc:8200"
                leader_ca_cert_file = "/vault/userconfig/tls/ca.crt"
                leader_tls_servername = "vault.vault.svc"
              }
              retry_join {
                leader_api_addr = "https://vault-2.vault-internal.vault.svc:8200"
                leader_ca_cert_file = "/vault/userconfig/tls/ca.crt"
                leader_tls_servername = "vault.vault.svc"
              }
            }
            seal "awskms" {
              region = "${var.region}"
              kms_key_id = "${var.unseal_key_arn}"
            }
            service_registration "kubernetes" {}
            telemetry {
              prometheus_retention_time = "30s"
              disable_hostname = true
            }
          HCL
        }
      }
    }
    ui = { enabled = false }
  })]
}
output "vault_address" { value = "https://vault-active.vault.svc:8200" }
