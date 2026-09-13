terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

data "aws_partition" "current" {}
locals {
  prefix = "${var.name}-${var.environment}"
  ha     = contains(["staging", "prod"], var.environment)
  tags   = merge(var.tags, { Service = var.name, Environment = var.environment, ManagedBy = "Terraform" })
  zones  = { for index, az in var.availability_zones : az => index }
  arn    = "arn:${data.aws_partition.current.partition}"
}

# A tag-based inventory group. The AWS account remains the isolation boundary.
resource "aws_resourcegroups_group" "this" {
  name = local.prefix
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        { Key = "Service", Values = [var.name] },
        { Key = "Environment", Values = [var.environment] }
      ]
    })
  }
  tags = local.tags
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = local.prefix })
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}
resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value)
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = "${local.prefix}-egress-${each.key}" })
}
resource "aws_subnet" "private" {
  for_each          = local.zones
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.value + 4)
  tags = merge(local.tags, {
    Name                              = "${local.prefix}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = local.tags
}
resource "aws_route_table_association" "public" {
  for_each       = local.zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  for_each = local.ha ? local.zones : { (var.availability_zones[0]) = 0 }
  domain   = "vpc"
  tags     = local.tags
}
resource "aws_nat_gateway" "this" {
  for_each      = aws_eip.nat
  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = local.tags
  depends_on    = [aws_internet_gateway.this]
}
resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[local.ha ? each.key : var.availability_zones[0]].id
  }
  tags = local.tags
}
resource "aws_route_table_association" "private" {
  for_each       = local.zones
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_iam_role" "cluster" {
  name = "${local.prefix}-cluster"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
  tags = local.tags
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.arn}:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.prefix}/cluster"
  retention_in_days = local.ha ? 90 : 30
  tags              = local.tags
}
resource "aws_eks_cluster" "this" {
  name                      = local.prefix
  role_arn                  = aws_iam_role.cluster.arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }
  tags       = local.tags
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.eks]
}
resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.platform_deployer_role_arn
  type          = "STANDARD"
  tags          = local.tags
}
resource "aws_eks_access_policy_association" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.deployer.principal_arn
  policy_arn    = "${local.arn}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

resource "aws_iam_openid_connect_provider" "eks" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}
locals {
  oidc_host = trimprefix(aws_iam_openid_connect_provider.eks.url, "https://")
  service_accounts = {
    cni   = "system:serviceaccount:kube-system:aws-node"
    ebs   = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    vault = "system:serviceaccount:vault:vault"
  }
}
# IRSA is used here for Vault KMS auto-unseal and AWS add-ons. Application -> Vault
# authentication is separate and uses Vault's Kubernetes auth method.
resource "aws_iam_role" "service_account" {
  for_each = local.service_accounts
  name     = "${local.prefix}-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
    Action = "sts:AssumeRoleWithWebIdentity"
    Condition = { StringEquals = {
      "${local.oidc_host}:sub" = each.value
      "${local.oidc_host}:aud" = "sts.amazonaws.com"
    } }
  }] })
  tags = local.tags
}
resource "aws_iam_role_policy_attachment" "addons" {
  for_each   = { cni = "AmazonEKS_CNI_Policy", ebs = "service-role/AmazonEBSCSIDriverPolicy" }
  role       = aws_iam_role.service_account[each.key].name
  policy_arn = "${local.arn}:iam::aws:policy/${each.value}"
}
resource "aws_kms_key" "vault_unseal" {
  description             = "Dedicated Vault auto-unseal key for ${local.prefix}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${local.prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}
resource "aws_iam_role_policy" "vault_unseal" {
  name = "kms-auto-unseal-only"
  role = aws_iam_role.service_account["vault"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow"
    Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    Resource = aws_kms_key.vault_unseal.arn
  }] })
}
resource "aws_eks_addon" "cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_versions.vpc_cni
  service_account_role_arn    = aws_iam_role.service_account["cni"].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  configuration_values        = jsonencode({ enableNetworkPolicy = "true" })
  depends_on                  = [aws_iam_role_policy_attachment.addons]
  tags                        = local.tags
}
resource "aws_iam_role" "nodes" {
  name = "${local.prefix}-nodes"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
  tags = local.tags
}
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryReadOnly"])
  role       = aws_iam_role.nodes.name
  policy_arn = "${local.arn}:iam::aws:policy/${each.value}"
}
resource "aws_launch_template" "nodes" {
  name_prefix = "${local.prefix}-"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tags = local.tags
}
# One On-Demand baseline group per AZ guarantees initial Vault placement capacity.
resource "aws_eks_node_group" "baseline" {
  for_each        = local.zones
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "baseline-${each.value}"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [aws_subnet.private[each.key].id]
  instance_types  = ["m6i.large"]
  capacity_type   = "ON_DEMAND"
  ami_type        = "AL2023_x86_64_STANDARD"
  version         = var.kubernetes_version
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 3
  }
  update_config { max_unavailable = 1 }
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }
  labels     = { "platform-baseline" = "true" }
  tags       = local.tags
  depends_on = [aws_iam_role_policy_attachment.nodes, aws_eks_addon.cni, aws_route_table_association.private]
}
resource "aws_eks_addon" "after_nodes" {
  for_each = {
    "coredns"            = var.addon_versions.coredns
    "kube-proxy"         = var.addon_versions.kube_proxy
    "aws-ebs-csi-driver" = var.addon_versions.ebs_csi
  }
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value
  service_account_role_arn    = each.key == "aws-ebs-csi-driver" ? aws_iam_role.service_account["ebs"].arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags
  depends_on                  = [aws_eks_node_group.baseline]
}
