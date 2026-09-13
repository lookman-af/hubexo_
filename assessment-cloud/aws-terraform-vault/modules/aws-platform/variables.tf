variable "name" { type = string }
variable "environment" { type = string }
variable "region" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(distinct(var.availability_zones)) == 3
    error_message = "Provide three distinct AZs for Vault Raft quorum placement."
  }
}
variable "kubernetes_version" { type = string }
variable "addon_versions" {
  type = object({ coredns = string, kube_proxy = string, vpc_cni = string, ebs_csi = string })
}
variable "platform_deployer_role_arn" { type = string }
variable "tags" { type = map(string) }
