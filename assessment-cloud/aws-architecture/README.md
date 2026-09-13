# AWS architecture design

Scope: Part 1, architecture design for 30 global product teams, 300 engineers,
Development/Test/Staging/Production, and governed AI engineering agents.

## Deliverables

- `../../output/pdf/aws-control-tower-architecture.pdf`:
  four A4 landscape pages, entirely in English.
- `aws-landing-zone.svg`: vector account/governance diagram.
- `aws-production-workload.svg`: vector production workload and recovery diagram.

The PDF contains two diagrams and supporting explanations. This is an AWS-only
architecture proposal. The earlier Azure Terraform example remains a separate
deliverable and does not implement this AWS design.

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

The requested team-size banner and dated/icon-release footer have been removed.
Only page numbering remains in the footer. Diagram SVGs match the updated PDF.

## Official icon provenance

Source page: https://aws.amazon.com/architecture/icons/

Downloaded official package (31 July 2026 release):
https://d1.awsstatic.com/onedam/marketing-channels/website/public/shared/architecture-icon-release/Icon-package_07312026.5846e92413caa21490223536cc97f1269e44fa92.zip

Selected official SVG service icons are embedded in the diagrams without recoloring.
Boxes, connectors and generic account labels are custom. Use of AWS icons does not
constitute AWS certification or endorsement of this proposal.

## Rebuild / verification

`build_architecture.py` uses ReportLab, svglib and PyMuPDF. It outputs the PDF,
vector diagrams and page renders. PDF page count is asserted to equal four;
all four page renders are inspected visually before delivery.

Official architecture and service references are clickable on page 4 of the PDF.
