terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
  backend "s3" {}
}
variable "region" { type = string }
variable "account_id" { type = string }
variable "cluster_name" { type = string }
variable "environment" { type = string }
variable "application" { type = string }
variable "image_digest" {
  type = string
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "Use an approved immutable image URI with a SHA-256 digest."
  }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}
data "aws_eks_cluster" "this" { name = var.cluster_name }
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}
data "kubernetes_namespace_v1" "app" {
  metadata { name = var.application }
}
resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = var.application
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  automount_service_account_token = false
}
resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = var.application
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    replicas = 2
    selector { match_labels = { app = var.application } }
    template {
      metadata {
        labels = { app = var.application }
        annotations = {
          "vault.hashicorp.com/agent-inject"                            = "true"
          "vault.hashicorp.com/role"                                    = "${var.application}-${var.environment}"
          "vault.hashicorp.com/service"                                 = "https://vault-active.vault.svc:8200"
          "vault.hashicorp.com/tls-secret"                              = "vault-client-ca"
          "vault.hashicorp.com/ca-cert"                                 = "/vault/tls/ca.crt"
          "vault.hashicorp.com/tls-server-name"                         = "vault.vault.svc"
          "vault.hashicorp.com/agent-service-account-token-volume-name" = "vault-token"
          "vault.hashicorp.com/agent-inject-secret-config.json"         = "applications/data/${var.environment}/${var.application}/config"
          "vault.hashicorp.com/agent-inject-template-config.json"       = "{{- with secret \"applications/data/${var.environment}/${var.application}/config\" -}}{{ .Data.data | toJSON }}{{- end }}"
        }
      }
      spec {
        service_account_name            = kubernetes_service_account_v1.app.metadata[0].name
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          seccomp_profile { type = "RuntimeDefault" }
        }
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "DoNotSchedule"
          label_selector { match_labels = { app = var.application } }
        }
        volume {
          name = "vault-token"
          projected {
            sources {
              service_account_token {
                audience           = "vault"
                expiration_seconds = 3600
                path               = "token"
              }
            }
          }
        }
        container {
          name  = "application"
          image = var.image_digest
          port { container_port = 8080 }
          env {
            name  = "CONFIG_FILE"
            value = "/vault/secrets/config.json"
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 8080
            }
          }
          liveness_probe {
            http_get {
              path = "/health/live"
              port = 8080
            }
          }
        }
      }
    }
  }
}
resource "kubernetes_service_v1" "app" {
  metadata {
    name      = var.application
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    type     = "ClusterIP"
    selector = { app = var.application }
    port {
      port        = 80
      target_port = 8080
    }
  }
}
resource "kubernetes_pod_disruption_budget_v1" "app" {
  metadata {
    name      = var.application
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    min_available = "1"
    selector { match_labels = { app = var.application } }
  }
}
resource "kubernetes_network_policy_v1" "app" {
  metadata {
    name      = "application-boundary"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
    ingress {
      from {
        pod_selector {}
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
        pod_selector { match_labels = { "k8s-app" = "kube-dns" } }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "vault" } }
        pod_selector { match_labels = { "app.kubernetes.io/name" = "vault", component = "server" } }
      }
      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }
  }
}
