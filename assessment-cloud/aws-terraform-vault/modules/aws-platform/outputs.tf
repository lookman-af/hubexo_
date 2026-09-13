output "cluster_name" { value = aws_eks_cluster.this.name }
output "vpc_id" { value = aws_vpc.this.id }
output "vault_unseal_key_arn" { value = aws_kms_key.vault_unseal.arn }
output "vault_role_arn" { value = aws_iam_role.service_account["vault"].arn }
output "cluster_log_group" { value = aws_cloudwatch_log_group.eks.name }
output "resource_group_name" { value = aws_resourcegroups_group.this.name }
