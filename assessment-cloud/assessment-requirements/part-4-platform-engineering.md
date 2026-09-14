# Part 4 — Platform Engineering

[Requirements index](README.md) · [Repository home](../../README.md) · [Previous: Security & Access](part-3-security-access.md) · [Next: FinOps](part-5-finops.md)

## Developer workflow

Provide a small internal developer portal backed by versioned templates and Git.
Start with common needs: create a service, request infrastructure, deploy a release,
and view service health. The portal submits requests to controlled automation;
it does not give developers platform-admin credentials. This follows
[AWS internal developer platform principles](https://docs.aws.amazon.com/prescriptive-guidance/latest/internal-developer-platform/principles.html).

## Self-service infrastructure

1. An engineer chooses an approved template and supplies service name, owner, environment, data classification, and capacity tier.
2. The portal creates a PR using a versioned Terraform module. Defaults include private networking, workload identity, Vault references, resource tags, quotas, and observability configuration.
3. Automation checks formatting, security, policy, proposed cost, and the Terraform plan. Low-risk requests can follow a pre-approved policy; production or privileged changes require the designated reviewer.
4. An environment-scoped runner applies the approved saved plan with protected remote state and locking. If the plan becomes stale, regenerate it and repeat the checks.
5. The portal records outputs, ownership, documentation, and expiry for temporary resources. Deletion uses a reviewed workflow with data-retention and dependency checks.

Account and cluster creation remain platform-owned catalog actions. Product teams
normally request namespaces and approved service dependencies within their boundary.

## Deploy applications

Build an application image once, run tests and scans, create an SBOM, and sign the
image and provenance. Store it in Amazon ECR and promote the same digest through
Development, Test, Staging, and Production.

Use an environment-scoped GitOps controller to reconcile reviewed deployment manifests.
Validate admission policies, resource limits, probes, and workload identity before
rollout. Use progressive delivery with health/SLO gates; on regression, halt the rollout
and restore the previous approved digest and Git configuration. Keep database changes
backward compatible because an application rollback does not reverse data changes.

Protect production branches and approvals. Scope each controller to its environment;
application repositories must not change cluster security policy. The existing
Terraform application example owns its Deployment directly; transfer ownership
explicitly before introducing GitOps for that same resource.

## Consume platform services safely

| Service | Developer experience and control |
| --- | --- |
| Secrets | Request an approved Vault path and use runtime file injection. Access is tied to the workload service account; no shared tokens. |
| Data and messaging | Choose supported service tiers with private connectivity, scoped credentials, backup policy, quota, and a named owner. |
| Networking | Request approved ingress and dependency access through templates; enforce network policies and egress controls. |
| Observability | Receive standard instrumentation, dashboards, alerts, and runbooks with team-scoped access. |
| Operational tasks | Run versioned, allowlisted actions through an authenticated API with validated parameters, bounded permissions, and audit records. |

AI agents use the same catalog and validation controls with distinct task identities.
They cannot approve their own changes, alter policy, or bypass production gates.

## Ownership and success measures

Platform engineers own templates, cluster lifecycle, shared services, and their SLOs.
Product teams own application code, data, cost, and on-call response. Publish supported
versions, deprecation dates, and an exception path with an owner and expiry.
Measure time to first deployment, deployment lead time, failure/recovery rates,
self-service completion rate, and support demand. Pilot with a small set of services
and improve templates from engineer feedback.

The portal, GitOps, and policy automation are target platform capabilities; they are
not installed by the current Terraform sample. See the
[implementation scope](../aws-terraform-vault/README.md).
