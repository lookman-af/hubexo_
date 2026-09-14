# Part 2 — Observability

[Requirements index](README.md) · [Repository home](../../README.md) · [Previous: Cloud Architecture](part-1-cloud-architecture.md)

## Observability approach

Provide a shared observability service with access scoped by team and environment.
Use consistent service, environment, region, release, and trace identifiers so an
operator can move from an alert to the relevant metrics, logs, and traces. Prioritize
user impact and actionable signals, following
[AWS EKS monitoring guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-eks-observability-best-practices/monitoring-best-practices.html).

| Capability | Implementation |
| --- | --- |
| Monitoring | Use CloudWatch Container Insights for EKS infrastructure and Amazon Managed Service for Prometheus for application/Vault metrics. Monitor request rate, errors, latency, saturation, pod restarts, pending pods, node health, and Vault seal/Raft status. Scrape Vault metrics using a dedicated read-only identity. |
| Logging | Send structured application/container logs through Fluent Bit to CloudWatch Logs. Enable EKS control-plane audit logs; collect CloudTrail AWS API events and Vault audit output separately. Aggregate across accounts with restricted access; redact sensitive data and set explicit retention and archive policies. |
| Tracing | Instrument services with OpenTelemetry, propagate trace context across HTTP and messaging, and export through a collector to AWS X-Ray. Correlate trace IDs with application logs. Configure sampling to control cost while retaining useful error and slow-request traces; exclude sensitive attributes. |
| Alerting | Define service SLOs and alert on sustained error-budget burn, user-visible failures, and critical platform faults. Route incidents to the owning on-call through the approved incident integration. Deduplicate alerts and include severity, environment, runbook, and dashboard links. Use tickets for nonurgent capacity trends. |
| Dashboards | Use Amazon Managed Grafana with CloudWatch and Prometheus data sources. Provide a platform health view, a service/SLO view, and a release comparison view. Include cost and capacity trends; enforce team access and production data restrictions. |

Collect each signal once where possible, and define ownership of collectors and alerts.
Use a shared Observability account for access and aggregation; retain security audit
archives under separate security ownership. Monitor ingestion failures, dropped
telemetry, collector health, and alert delivery. Test a synthetic incident end to end.
AWS describes the supported collection options in its
[EKS monitoring documentation](https://docs.aws.amazon.com/eks/latest/userguide/eks-observe.html).

## Visibility into AI-driven activities

Treat each agent task as an attributable engineering operation. Give it a unique
agent identity and task ID, and correlate its activity across the tool gateway,
repository, CI/CD, AWS, Kubernetes, and Vault. CloudTrail records AWS API activity;
it does not capture every model request or Kubernetes action.

| Area | Record or display |
| --- | --- |
| Task audit | Requester, agent identity, task ID, model/version, target environment/resource, policy decision, approval reference, tool/action, timestamps, result, and linked PR/deployment. Include denied and failed actions. |
| Operational dashboard | Task success/failure, execution duration, tool errors, approval wait time, deployment outcomes, and policy denials. Show model token usage, model cost, and resulting infrastructure cost separately. |
| Security alerts | Unexpected production actions, attempted privilege escalation, repeated denied calls, unusual egress, and budget breaches. Route to security and the platform owner; support immediate agent suspension. |
| Evidence protection | Forward gateway events, CI/repository audit events, CloudTrail, EKS audit logs, and Vault audit logs to access-controlled storage. Use S3 Object Lock where immutable retention is required, with a reviewed retention policy. |

Do not log secrets, raw credentials, or private chain-of-thought. Redact prompts and
tool outputs, minimize retained content, and restrict access. An audit record documents
an approval; it does not grant permission. Enforce permissions at the tool gateway and
target service. Keep task/trace IDs in logs and traces rather than high-cardinality
metric labels.

## Acceptance checks

Trigger a test application failure and verify alert routing, dashboard context, and
trace-to-log correlation. Execute one approved agent task and one denied task, then
reconstruct who requested each, what was permitted, and what actually happened.
Verify telemetry outages are detected and sensitive values remain excluded.

The Terraform sample exposes EKS control-plane logs and Vault telemetry/audit output;
collectors, shared dashboards, alert routes, and the AI audit gateway remain platform
integration work. See the [verification report](../aws-terraform-vault/docs/verification.md).
