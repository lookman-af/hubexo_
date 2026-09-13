terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
  backend "s3" {}
}
variable "region" { type = string }
variable "account_id" { type = string }
variable "cluster_name" { type = string }
variable "unseal_key_arn" { type = string }
variable "vault_role_arn" { type = string }
variable "vault_tls_secret_name" { type = string }
variable "application" { type = string }
variable "vault_ca_cert_file" { type = string }
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
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}
module "vault" {
  source                = "../../modules/vault-runtime"
  region                = var.region
  unseal_key_arn        = var.unseal_key_arn
  vault_role_arn        = var.vault_role_arn
  vault_tls_secret_name = var.vault_tls_secret_name
  application_namespace = var.application
  vault_ca_pem          = file(var.vault_ca_cert_file)
}
output "vault_address" { value = module.vault.vault_address }
