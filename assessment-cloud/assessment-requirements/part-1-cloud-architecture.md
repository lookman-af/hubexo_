# Part 1 — Cloud Architecture

[Requirements index](README.md) · [Repository home](../../README.md) · [Next: Observability](part-2-observability.md)

## Platform approach

Use AWS Organizations and Control Tower for a multi-account landing zone. Separate
security, log archive, networking, and delivery services from workload accounts.
Use separate AWS accounts and EKS clusters for Development, Test, Staging, and
Production within each product/domain boundary. Provision repeatable infrastructure
with Terraform and promote reviewed application image digests through the environments.
Account grouping and baseline governance follow the
[AWS multi-account guidance](https://docs.aws.amazon.com/controltower/latest/userguide/aws-multi-account-landing-zone.html).

## Environment strategy

| Environment | Purpose | Operating approach |
| --- | --- | --- |
| Development | Fast feedback and feature work | Synthetic data, small capacity, expiring preview workloads, and approved automated deployments. |
| Test | Integration and security validation | Repeatable test data; automated functional, contract, and negative authorization tests. |
| Staging | Release confidence | Match production versions, policies, and topology at lower capacity; rehearse load, rollout, and recovery. |
| Production | Serve users reliably | Multi-AZ capacity, protected access, reviewed releases, SLO monitoring, and tested recovery. |

All environments retain identity, encryption, logging, and policy controls. Schedule
eligible nonproduction application capacity down without disrupting shared services
or Vault quorum. Never copy unmasked production data into lower environments.

## Design priorities

| Priority | Recommended approach |
| --- | --- |
| Reliability | Run private EKS workers across three AZs; spread application replicas and use readiness probes, disruption budgets, and gradual rollouts. Keep stable On-Demand system capacity. Back up stateful services and Vault Raft data; test restores. Add regional recovery according to agreed RTO/RPO. |
| Security | Use private EKS APIs, federated human access with MFA, least-privilege IAM and Kubernetes RBAC, and distinct workload identities. Use HashiCorp Vault for runtime secrets and KMS for auto-unseal. Enforce TLS, Pod Security Admission, network policies, and controlled egress. |
| Scalability | Set pod requests/limits and namespace quotas. Use HPA for application replicas and Karpenter for application node capacity. Bound scale by budgets, service quotas, subnet IP capacity, and database limits; verify with load tests. |
| Cost | Tag resources by owner, product, environment, and cost center. Track cost per request or transaction, rightsize capacity, expire previews, and use Spot for interruption-tolerant applications. Keep Vault voters and essential controllers on stable capacity. |
| Governance | Apply Control Tower controls, SCPs, approved Terraform modules, policy checks, and drift detection. SCPs limit permissions; IAM grants access. Protect production state and deployment roles; require independent approval for high-risk changes. |

Application availability needs deliberate scheduling and rollout controls; the managed
EKS control plane alone does not make a workload highly available. See
[AWS EKS application reliability guidance](https://docs.aws.amazon.com/eks/latest/best-practices/application.html).

## Acceptance checks

Before production, demonstrate one-AZ failure handling, least-privilege access,
load-based scaling, and restore of application data and Vault. Agree service-specific
SLOs, RTO, and RPO with owners, then record measured results. Confirm cost allocation,
production approval gates, and policy enforcement with positive and negative tests.

See the [Architecture Design PDF](../aws-architecture/aws-control-tower-architecture.pdf)
for diagrams and the [Design Document](../aws-design-document/aws-eks-design-document.md)
for detailed decisions.
