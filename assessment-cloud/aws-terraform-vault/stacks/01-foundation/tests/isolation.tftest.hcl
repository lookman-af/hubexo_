mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock-platform-role" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = { identity = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/MOCK" }] }] }
  }
}

variables {
  name               = "orders"
  environment        = "prod"
  region             = "eu-west-1"
  vpc_cidr           = "10.40.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  kubernetes_version = "1.35"
  addon_versions = {
    coredns    = "v1.0.0-eksbuild.1"
    kube_proxy = "v1.0.0-eksbuild.1"
    vpc_cni    = "v1.0.0-eksbuild.1"
    ebs_csi    = "v1.0.0-eksbuild.1"
  }
  platform_deployer_role_arn = "arn:aws:iam::111122223333:role/protected-platform-deployer"
  tags                       = { Owner = "team-orders", CostCenter = "commerce" }
}

run "production_isolation" {
  command = plan
  module { source = "../../modules/aws-platform" }
  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "Production must keep the EKS API private."
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eks_node_group.baseline) == 3
    error_message = "Production needs AZ-local NAT and baseline capacity in all three AZs."
  }
  assert {
    condition     = aws_cloudwatch_log_group.eks.retention_in_days == 90 && length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "Production control-plane audit/log coverage must not silently regress."
  }
}

run "development_cost_boundary" {
  command = plan
  module { source = "../../modules/aws-platform" }
  variables { environment = "dev" }
  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eks_node_group.baseline) == 3
    error_message = "Dev may share NAT but must preserve three-AZ Vault placement capacity."
  }
  assert {
    condition     = !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "Lower-cost development must not enable public EKS API access."
  }
}
