# Infrastructure-as-Code Example: AWS EKS and HashiCorp Vault

This assessment example provisions an AWS workload foundation, a private HashiCorp
Vault cluster, Vault policies, and a Kubernetes application that receives secrets at
runtime. It emphasizes reusable structure, environment isolation, identity, and clear
bootstrap boundaries. All documentation and comments are in English.

## Assessment requirement mapping

| Requested term | AWS / HashiCorp implementation | Code |
|---|---|---|
| Resource Group | AWS Resource Groups with service/environment tags | `modules/aws-platform/main.tf` |
| VNet | VPC, three AZs, private/public subnets, routes and NAT | `modules/aws-platform/main.tf` |
| Identity | EKS cluster/node IAM roles, IRSA for Vault/add-ons, Kubernetes service accounts and Vault auth roles | Foundation, Vault configuration and application stacks |
| Key Vault | HashiCorp Vault HA with KV v2 and scoped policies | `modules/vault-runtime`, `stacks/03-vault-config` |
| Monitoring capability | Five EKS control-plane log types in CloudWatch; Vault audit output and authenticated Prometheus telemetry | Foundation and Vault configuration |
| Application hosting | Amazon EKS with managed EC2 worker groups; Deployment, Service, probes and disruption budget | Foundation and application stacks |

AWS Resource Groups is a tag-based inventory view, not an Azure Resource Group's
lifecycle/authorization equivalent. The AWS account is the primary isolation boundary.
AWS KMS is used only for Vault auto-unseal; application secret storage is HashiCorp Vault.

## Repository structure

```text
modules/
  aws-platform/       # VPC, AWS Resource Groups, EKS, IAM, KMS and logs
  vault-runtime/      # Official Vault Helm chart, storage and namespace setup
stacks/
  01-foundation/      # AWS-only provider stage
  02-vault-runtime/   # Kubernetes + Helm; requires a reachable EKS API
  03-vault-config/    # Vault provider; requires initialized, unsealed Vault
  04-application/     # Workload identity and secret injection
examples/            # Input and backend templates; placeholders require replacement
docs/                # Deployment, security and verification guidance
```

Use each stack separately for each environment, with its own backend key and scoped
deployment identity. Production and nonproduction backends also need separate IAM
boundaries, not only different key names. Do not create all teams/environments in a
single Terraform state. Commit the provider lock files. Provider constraints allow
reviewed minor upgrades, while lock files reproduce the selected builds.

## Main design decisions

1. **Separate dependency stages.** EKS exists before Kubernetes/Helm providers run.
   Vault is installed before initialization and policy management. No single apply
   attempts to create a service and simultaneously authenticate to that new service.
2. **No secret values in Terraform.** Terraform creates engines, auth configuration,
   policies and role bindings. It does not create/read application secret values,
   recovery shares, root tokens, private TLS keys, or static AWS credentials. The
   application namespace's `vault-client-ca` Secret contains only a public CA bundle.
3. **Distinct identity paths.** Vault's Kubernetes service account uses IRSA only for
   its dedicated KMS key. CNI and EBS CSI use separate IRSA roles. Application pods
   authenticate to Vault with a projected Kubernetes token whose audience is `vault`.
   A service account is bound to one namespace and one exact KV path. The application
   does not receive the Vault KMS role or node credentials.
4. **Durable Vault storage.** Three Raft voters are spread across three AZs on encrypted
   gp3 volumes with Retain reclaim policy. TLS remains enabled. KMS auto-unseal does
   not remove the need for initialization, recovery custody, or tested snapshots.
5. **Private application boundary.** EKS API is private, workers have no public IP,
   Vault uses ClusterIP services, and the sample app has no public ingress. Its
   NetworkPolicy permits same-namespace requests, DNS and Vault access only.
6. **Bootstrap access is explicit.** The supplied platform deployer IAM role receives
   cluster-admin for platform installation. This must be a protected automation role,
   not a developer role. Scope ongoing application deployment to its namespace after
   platform setup. Restrict role assumption and do not grant agents this role.

## Quick local checks - no deployment

```sh
terraform fmt -check -recursive
terraform -chdir=stacks/01-foundation init -backend=false
terraform -chdir=stacks/01-foundation validate
```

Repeat initialization/validation for the other stacks. These commands do not need
AWS/Vault credentials or deploy resources; provider downloads require network access.
Actual plans and applies require the inputs, backend, permissions and network paths
described in [deployment.md](docs/deployment.md).

## Scope and production integration

This is a bounded assessment pattern, not a complete production landing zone. It
creates one environment's EKS/Vault foundation. Control Tower/AFT, organization SCPs,
state bootstrap, PKI issuance, private runners/connectivity, audit forwarding, snapshot
automation, alerts, DR and public application ingress are platform prerequisites or
explicit integration tasks. They are not silently claimed to be provisioned here.

- The baseline uses three On-Demand nodes. Staging/Prod use one NAT per AZ; Dev/Test
  use one NAT and accept its cost/availability trade-off. NAT permits outbound traffic;
  it is not an egress firewall. Add approved inspection and private endpoints before
  sensitive production use. IAM and Kubernetes policies still apply.
- Baseline node groups are not Karpenter NodePools. Karpenter/HPA, GitOps, admission
  signature verification and a public ALB/WAF path belong to the broader platform
  design and are not installed by this sample.
- The Vault service is environment-local. A dedicated secrets-platform cluster/account
  is preferable when separation from workload operators or shared failure domains is
  required. That changes routing, auth mounts and blast-radius controls; do not assume
  namespaces alone isolate a shared Vault deployment.
- Vault is self-managed here. Treat product licensing/support, upgrades, PKI, Raft
  snapshots and incident response as explicit operational responsibilities. Cross-region
  Vault DR is not provided by simply copying EBS volumes; use tested recovery or
  licensed replication capabilities appropriate to the deployment.
- A GitOps controller must not simultaneously own the sample Deployment managed by
  Terraform. Transfer ownership deliberately if adapting stack 04 to GitOps.

See [verification.md](docs/verification.md) for validation status and cloud acceptance
checks, and [deployment.md](docs/deployment.md) for the staged bootstrap sequence.

## Official references

- [AWS Resource Groups](https://docs.aws.amazon.com/ARG/latest/userguide/welcome.html)
- [Amazon EKS best practices](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html)
- [EKS IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Vault Kubernetes deployment guide](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-raft-deployment-guide)
- [Official Vault Helm configuration](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/configuration)
- [Vault AWS KMS auto-unseal](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms)
- [Vault Kubernetes authentication](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Vault Agent Injector annotations](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector/annotations)
- [Vault Terraform provider and state considerations](https://registry.terraform.io/providers/hashicorp/vault/latest/docs)
