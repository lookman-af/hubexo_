terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
  backend "s3" {}
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = var.owner, CostCenter = var.cost_center } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Use dev, test, staging, or prod."
  }
}
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.name))
    error_message = "Use a 3-20 character lowercase service name."
  }
}
variable "owner" { type = string }
variable "cost_center" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "kubernetes_version" { type = string }
variable "addon_versions" {
  type = object({ coredns = string, kube_proxy = string, vpc_cni = string, ebs_csi = string })
}
variable "platform_deployer_role_arn" { type = string }
module "platform" {
  source                     = "../../modules/aws-platform"
  name                       = var.name
  environment                = var.environment
  region                     = var.region
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  kubernetes_version         = var.kubernetes_version
  addon_versions             = var.addon_versions
  platform_deployer_role_arn = var.platform_deployer_role_arn
  tags                       = { Owner = var.owner, CostCenter = var.cost_center }
}
output "platform" { value = module.platform }
