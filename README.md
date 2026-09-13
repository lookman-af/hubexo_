# AWS Cloud Platform Assessment

Architecture and engineering assessment for an AWS platform using Amazon EKS and
HashiCorp Vault across Development, Test, Staging, and Production.

## Start here

Read the sections in order. Each folder contains its documents and supporting files.

| Part | Guide | Main deliverable |
| --- | --- | --- |
| 1. Architecture Design | [Architecture overview](assessment-cloud/aws-architecture/README.md) | [PDF — 4 pages](assessment-cloud/aws-architecture/aws-control-tower-architecture.pdf) |
| 2. Design Document | [Design overview](assessment-cloud/aws-design-document/README.md) | [PDF — 6 pages](assessment-cloud/aws-design-document/aws-eks-design-document.pdf) |
| 3. Infrastructure as Code | [Terraform and Vault guide](assessment-cloud/aws-terraform-vault/README.md) | [Download Terraform ZIP](assessment-cloud/aws-terraform-vault/aws-eks-vault-terraform.zip) |
| 4. Deployment Pipeline | [Pipeline overview and status](assessment-cloud/deployment-pipeline/README.md) | [Pipeline draft](assessment-cloud/deployment-pipeline/pipeline.md) |

The pipeline draft retains earlier deployment-slot terminology and needs adaptation
before it serves as the AWS EKS deployment specification.

## Repository layout

```text
README.md                             Main navigation
assessment-cloud/
  README.md                           Assessment index
  aws-architecture/                   Architecture PDF, SVG diagrams, icon assets, builder
  aws-design-document/                Design PDF, readable Markdown, builder
  aws-terraform-vault/                 Terraform modules, stacks, examples, guides, ZIP
  deployment-pipeline/                Pipeline draft and status
```

## Implementation status

The Terraform example has passed schema validation for four stacks, three mocked
test runs, and a local Vault Helm render check. No AWS resources have been deployed.
See the [verification report](assessment-cloud/aws-terraform-vault/docs/verification.md)
and [deployment prerequisites](assessment-cloud/aws-terraform-vault/docs/deployment.md)
for the checks still required before production use.

The architecture describes the wider platform; the Terraform example implements a
bounded EKS and Vault pattern. Each section documents its scope and assumptions.
