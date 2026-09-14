# 1. Architecture Design

[Repository home](../../README.md) · [Assessment index](../README.md) · [Next: Design Document](../aws-design-document/README.md)

AWS Control Tower landing zone and Amazon EKS architecture for Development, Test,
Staging, and Production.

## Read the deliverables

- [Architecture Design PDF](aws-control-tower-architecture.pdf) — four A4 landscape pages in English, with diagrams and supporting explanations.
- [Landing zone diagram](aws-landing-zone.svg) — account structure and governance.
- [Production workload diagram](aws-production-workload.svg) — EKS workload and recovery.
- [Terraform implementation](../aws-terraform-vault/README.md) — the bounded EKS and HashiCorp Vault example.

## Assumptions and boundaries

- Four workload accounts per product/domain, refined according to ownership/risk.
- AFT management, delivery and AI tooling are separate accounts.
- Security and Log Archive follow the configured Control Tower landing-zone baseline;
  additional OUs/accounts, security integrations and application services are configured explicitly.
- Amazon EKS is the Kubernetes runtime, with separate clusters per environment.
- Private EC2 workers span Availability Zones. An On-Demand managed node group
  hosts system controllers; Karpenter NodePools provide application capacity.
- EKS Pod Identity, Kubernetes RBAC, NetworkPolicy, Pod Security Admission,
  AWS Load Balancer Controller, HPA and GitOps provide workload controls.
- CloudFront VPC origins require supported regions/protocols and the documented VPC prerequisites.
- Critical-tier DR uses an independently prepared secondary region, Aurora Global Database,
  available artifacts/configuration/secrets, and an exercised promotion/switch procedure.
- SLO 99.9%, RTO 60 minutes and RPO 15 minutes are proposed targets, not validated guarantees.
- No AWS resources were provisioned.
